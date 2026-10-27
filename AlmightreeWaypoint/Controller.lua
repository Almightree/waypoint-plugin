local _, A = ...
local N = A.Navigation

local events = {
    "SUPER_TRACKING_CHANGED", "SUPER_TRACKING_PATH_UPDATED", "USER_WAYPOINT_UPDATED",
    "QUEST_POI_UPDATE", "AREA_POIS_UPDATED", "NAVIGATION_DESTINATION_REACHED",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local locationChanges = { ZONE_CHANGED_NEW_AREA = true, ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true }

function A.NewController(api, driver, view, db)
    local C = { enabled = false, generation = 0, preview = false, model = nil }
    local elapsed, pending, refreshQueued = 0, false, false
    local destination, waitingForWorld
    local sequence = 0
    local function diagnosticRead(namespace, method, ...)
        local row = N.Read(namespace, method, ...)
        if row.status == "ok" then return N.Scalar(row[1]) end
        return "<" .. row.status .. ">"
    end
    local function context(trigger)
        local record = { event = trigger or "internal", time = diagnosticRead(api, "GetTime") }
        if N.Read(api, "InCombatLockdown")[1] ~= false then
            record.playerMap, record.zone, record.subzone, record.realZone = "<suppressed>", "<suppressed>", "<suppressed>", "<suppressed>"
        else
            record.playerMap = diagnosticRead(api.C_Map, "GetBestMapForUnit", "player")
            record.zone = diagnosticRead(api, "GetZoneText")
            record.subzone = diagnosticRead(api, "GetSubZoneText")
            record.realZone = diagnosticRead(api, "GetRealZoneText")
        end
        return record
    end
    local function copy(record)
        if not record then return end
        local result = {}
        for k, v in pairs(record) do result[k] = v end
        return result
    end
    local function suppressed()
        if not C.enabled then return "disabled" end
        if waitingForWorld then return "loading_screen" end
        local row = N.Read(api, "InCombatLockdown")
        if row.status ~= "ok" then return "combat_status_" .. row.status end
        if row[1] == true then return "combat_suppressed" end
        if row[1] ~= false then return "combat_status_invalid" end
    end

    function C:RecordInvalidation(reason, new, compared, trigger)
        local record = context(trigger)
        sequence = sequence + 1
        record.sequence, record.reason = sequence, reason
        record.comparison = compared and "compared" or "not_checked"
        record.changedFields = compared and N.IdentityChanges(destination, new) or "not_checked"
        if compared and record.changedFields == "" then record.changedFields = "none" end
        if not compared then new = destination end -- retained identity; no claim of a fresh read
        record.oldKey, record.newKey = destination and destination.key, new and new.key
        for _, field in ipairs(N.IdentityFields) do
            record["old_" .. field] = destination and destination[field]
            record["new_" .. field] = new and new[field]
        end
        self.lastInvalidation = record
    end

    function C:GetLastInvalidation() return copy(self.lastInvalidation) end
    function C:GetLastEvent() return copy(self.lastEvent) end
    function C:GetLastZoneEvent() return copy(self.lastZoneEvent) end
    function C:GetResolution() return copy(self.model) end
    function C:GetLastConversion() return copy(self.lastConversion) end
    function C:GetCoordinateSpace()
        local model = self.model or {}
        return N.Scalar(model.coordinateSpace), N.Scalar(model.playerMap), N.Scalar(model.targetMap)
    end
    function C:GetWorldIDs()
        local model = self.model or {}
        return N.Scalar(model.playerWorldID), N.Scalar(model.targetWorldID), N.Scalar(model.unitWorldID)
    end

    function C:Invalidate(reason, new, compared, trigger)
        self.hideReason = reason or "invalidated"
        self:RecordInvalidation(self.hideReason, new, compared, trigger)
        self.generation = self.generation + 1
        self.model = nil -- display invalidation does not erase destination identity
        elapsed, pending, refreshQueued = 0, false, false
        driver:SetScript("OnUpdate", nil)
        view:Render(nil, self.hideReason)
    end

    function C:Render()
        local reason = suppressed()
        if reason then view:Render(nil, reason); return end
        if self.preview or not db.locked then
            view:Render({ preview = true, destination = "Waypoint preview", instruction = "Drag when unlocked /atway lock",
                distance = 125, rotation = -math.pi / 4 })
        else
            view:Render(self.model, self.model and self.model.hideReason or self.hideReason)
        end
    end

    function C:Refresh(trigger)
        local reason = suppressed()
        if reason then self:Invalidate(reason, nil, false, trigger); return end
        if self.preview or not db.locked then self:Render(); return end
        local ok, target, why = pcall(N.Identity, api)
        if not ok or not target then
            self:Invalidate(ok and why or "identity_error", nil, ok and why == "no_tracking", trigger)
            if ok and why == "no_tracking" then destination = nil end
            return
        end
        if not N.SameDestination(destination, target) then
            self:Invalidate(destination and "target_changed_pending" or "target_acquired_pending", target, true, trigger)
            destination = target
            pending = true
            self:RunUpdates()
            return
        end
        local generation = self.generation
        local success, model = pcall(N.Capture, api, target)
        -- Re-read identity after collecting data; never publish a mixed-target snapshot.
        local identityOK, current, currentWhy = pcall(N.Identity, api)
        if generation ~= self.generation or not self.enabled then return end
        if not identityOK or not current or not N.SameDestination(destination, current) then
            self:Invalidate("identity_changed_during_capture", current, identityOK and (current ~= nil or currentWhy == "no_tracking"), trigger)
            if identityOK and currentWhy == "no_tracking" then destination = nil end
            self:Queue()
            return
        end
        if not success or not model or not N.Number(model.rotation) then
            local hide = success and model and model.hideReason or "capture_error"
            if self.model and N.Number(self.model.rotation) or self.hideReason ~= hide then
                self:RecordInvalidation(hide, target, true, trigger)
            end
        end
        if success and model and model.conversionAttempted then
            self.lastConversion = copy(model)
            self.lastConversion.time = diagnosticRead(api, "GetTime")
            self.lastConversion.event = trigger or "internal"
            self.lastConversion.sequence = (self.conversionSequence or 0) + 1
            self.conversionSequence = self.lastConversion.sequence
        end
        self.model = success and model or nil
        self.hideReason = success and model and model.hideReason or (not success and "capture_error" or nil)
        self:Render()
        -- A target with no usable coordinates still refreshes at a lower rate for route readiness.
        self:RunUpdates()
    end

    function C:RunUpdates()
        if self.preview or not db.locked or suppressed() then return end
        driver:SetScript("OnUpdate", function(_, delta)
            if not C.enabled or waitingForWorld then C:Invalidate(suppressed()); return end
            if not N.Number(delta) or delta < 0 then return end
            elapsed = elapsed + delta
            local interval = pending and 0.25 or (refreshQueued and 0.1 or (C.model and C.model.rotation and 0.1 or 0.5))
            if elapsed < interval then return end
            elapsed = 0
            refreshQueued = false
            if pending then pending = false end
            C:Refresh("active_update")
        end)
    end

    function C:Queue()
        local reason = suppressed()
        if reason then view:Render(nil, reason); return end
        if self.preview or not db.locked then self:Render(); return end
        self.hideReason = "refresh_pending"
        view:Render(nil, self.hideReason)
        pending = true
        self:RunUpdates()
    end

    function C:SetEnabled(value)
        self:Invalidate("settings_changed", nil, false, "SetEnabled")
        self.enabled, db.enabled = value == true, value == true
        driver:UnregisterAllEvents()
        if self.enabled then
            for _, event in ipairs(events) do pcall(driver.RegisterEvent, driver, event) end
            self:Queue()
        else
            self.preview = false
        end
        self:Render()
    end

    function C:SetPreview(value)
        self:Invalidate()
        self.preview = value == true
        if self.preview and not self.enabled then self:SetEnabled(true); self.preview = true end
        self:Queue()
        self:Render()
    end

    function C:SetLocked(value)
        self:Invalidate()
        db.locked = value == true
        view:SetLocked(db.locked)
        self:Queue()
        self:Render()
    end

    driver:SetScript("OnEvent", function(_, event)
        if not C.enabled then return end
        C.lastEvent = context(event)
        if locationChanges[event] or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEAVING_WORLD" then
            C.lastZoneEvent = copy(C.lastEvent)
        end
        if event == "PLAYER_LEAVING_WORLD" then waitingForWorld = true; C:Invalidate("loading_screen", nil, false, event); return end
        if event == "PLAYER_REGEN_DISABLED" then C:Invalidate("combat_suppressed", nil, false, event); return end
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
            if event == "PLAYER_ENTERING_WORLD" then waitingForWorld = false end
            C:Invalidate("refresh_pending", nil, false, event)
            C:Queue()
            return
        end
        local reason = suppressed()
        if reason then C:Invalidate(reason, nil, false, event); return end
        if C.preview or not db.locked then C:Render(); return end

        -- Check identity on every event, even during a coalesced refresh. A routine
        -- path/POI notification is not evidence that the active target changed.
        local ok, target, why = pcall(N.Identity, api)
        if not ok or not target then
            C:Invalidate(ok and why or "identity_error", nil, ok and why == "no_tracking", event)
            if ok and why == "no_tracking" then destination = nil end
            return
        end
        if not N.SameDestination(destination, target) then
            C:Invalidate(destination and "target_changed_pending" or "target_acquired_pending", target, true, event)
            destination, pending = target, true
            C:RunUpdates()
            return
        end

        -- First event revalidates immediately, replacing the model only with fresh
        -- data (including an unusable result). Further events share the next tick;
        -- neither pending acquisition nor its elapsed time is reset by a burst.
        if not pending and (not refreshQueued or locationChanges[event]) then
            refreshQueued = true
            C:Refresh(event)
        end
        C:RunUpdates()
    end)
    return C
end
