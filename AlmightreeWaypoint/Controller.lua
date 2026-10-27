local _, A = ...
local N = A.Navigation

local events = {
    "SUPER_TRACKING_CHANGED", "SUPER_TRACKING_PATH_UPDATED", "USER_WAYPOINT_UPDATED",
    "QUEST_POI_UPDATE", "AREA_POIS_UPDATED", "NAVIGATION_DESTINATION_REACHED",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local contextChanges = {
    PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true, ZONE_CHANGED = true,
    PLAYER_REGEN_ENABLED = true,
}

function A.NewController(api, driver, view, db)
    local C = { enabled = false, generation = 0, preview = false, model = nil }
    local elapsed, pending, refreshQueued = 0, false, false
    local key, waitingForWorld
    local function suppressed()
        if not C.enabled then return "disabled" end
        if waitingForWorld then return "loading_screen" end
        local row = N.Read(api, "InCombatLockdown")
        if row.status ~= "ok" then return "combat_status_" .. row.status end
        if row[1] == true then return "combat_suppressed" end
        if row[1] ~= false then return "combat_status_invalid" end
    end

    function C:Invalidate(reason)
        self.hideReason = reason or "invalidated"
        self.generation = self.generation + 1
        self.model, key = nil, nil
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

    function C:Refresh()
        local reason = suppressed()
        if reason then self:Invalidate(reason); return end
        if self.preview or not db.locked then self:Render(); return end
        local ok, target, why = pcall(N.Identity, api)
        if not ok or not target then self:Invalidate(ok and why or "identity_error"); return end
        if key ~= target.key then
            self:Invalidate("target_changed_pending")
            key = target.key
            pending = true
            self:RunUpdates()
            return
        end
        local generation = self.generation
        local success, model = pcall(N.Capture, api, target)
        -- Re-read identity after collecting data; never publish a mixed-target snapshot.
        local identityOK, current = pcall(N.Identity, api)
        if generation ~= self.generation or not self.enabled then return end
        if not identityOK or not current or current.key ~= key then self:Invalidate("identity_changed_during_capture"); self:Queue(); return end
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
            C:Refresh()
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
        self:Invalidate("settings_changed")
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
        if event == "PLAYER_LEAVING_WORLD" then waitingForWorld = true; C:Invalidate("loading_screen"); return end
        if event == "PLAYER_REGEN_DISABLED" then C:Invalidate("combat_suppressed"); return end
        if contextChanges[event] then
            if event == "PLAYER_ENTERING_WORLD" then waitingForWorld = false end
            C:Invalidate("refresh_pending")
            C:Queue()
            return
        end
        local reason = suppressed()
        if reason then C:Invalidate(reason); return end
        if C.preview or not db.locked then C:Render(); return end

        -- Check identity on every event, even during a coalesced refresh. A routine
        -- path/POI notification is not evidence that the active target changed.
        local ok, target, why = pcall(N.Identity, api)
        if not ok or not target then C:Invalidate(ok and why or "identity_error"); return end
        if key ~= target.key then
            C:Invalidate("target_changed_pending")
            key, pending = target.key, true
            C:RunUpdates()
            return
        end

        -- First event revalidates immediately, replacing the model only with fresh
        -- data (including an unusable result). Further events share the next tick;
        -- neither pending acquisition nor its elapsed time is reset by a burst.
        if not pending and not refreshQueued then
            refreshQueued = true
            C:Refresh()
        end
        C:RunUpdates()
    end)
    return C
end
