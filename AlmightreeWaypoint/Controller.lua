local _, A = ...
local N = A.Navigation

local events = {
    "SUPER_TRACKING_CHANGED", "SUPER_TRACKING_PATH_UPDATED", "USER_WAYPOINT_UPDATED",
    "QUEST_POI_UPDATE", "AREA_POIS_UPDATED", "NAVIGATION_DESTINATION_REACHED",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

function A.NewController(api, driver, view, db)
    local C = { enabled = false, generation = 0, preview = false, model = nil }
    local elapsed, pending = 0, false
    local key, waitingForWorld
    local function combat()
        return N.Read(api, "InCombatLockdown")[1] ~= false
    end

    function C:Invalidate()
        self.generation = self.generation + 1
        self.model, key = nil, nil
        elapsed, pending = 0, false
        driver:SetScript("OnUpdate", nil)
        view:Render(nil)
    end

    function C:Render()
        if not self.enabled or combat() or waitingForWorld then view:Render(nil); return end
        if self.preview or not db.locked then
            view:Render({ preview = true, destination = "Waypoint preview", instruction = "Drag when unlocked /atway lock",
                distance = 125, rotation = -math.pi / 4 })
        else
            view:Render(self.model)
        end
    end

    function C:Refresh()
        if not self.enabled or combat() or waitingForWorld then self:Invalidate(); return end
        if self.preview or not db.locked then self:Render(); return end
        local ok, target = pcall(N.Identity, api)
        if not ok or not target then self:Invalidate(); return end
        if key ~= target.key then
            self:Invalidate()
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
        if not identityOK or not current or current.key ~= key then self:Invalidate(); self:Queue(); return end
        self.model = success and model or nil
        self:Render()
        -- A target with no usable coordinates still refreshes at a lower rate for route readiness.
        self:RunUpdates()
    end

    function C:RunUpdates()
        if not self.enabled or self.preview or not db.locked or combat() or waitingForWorld then return end
        driver:SetScript("OnUpdate", function(_, delta)
            if not C.enabled or waitingForWorld then C:Invalidate(); return end
            if not N.Number(delta) or delta < 0 then return end
            elapsed = elapsed + delta
            local interval = pending and 0.25 or (C.model and C.model.rotation and 0.1 or 0.5)
            if elapsed < interval then return end
            elapsed = 0
            if pending then pending = false end
            C:Refresh()
        end)
    end

    function C:Queue()
        if not self.enabled or combat() or waitingForWorld then return end
        if self.preview or not db.locked then self:Render(); return end
        pending = true
        self:RunUpdates()
    end

    function C:SetEnabled(value)
        self:Invalidate()
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
        C:Invalidate() -- Clear every displayed field before any fresh read or delayed work.
        if event == "PLAYER_LEAVING_WORLD" then waitingForWorld = true; return end
        if event == "PLAYER_ENTERING_WORLD" then waitingForWorld = false end
        C:Queue()
    end)
    return C
end
