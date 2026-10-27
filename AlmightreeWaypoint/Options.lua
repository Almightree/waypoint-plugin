local _, A = ...
local N = A.Navigation

function A.Settings(saved)
    local db = N.Table(saved) and saved or {}
    if type(db.enabled) ~= "boolean" then db.enabled = true end
    if type(db.locked) ~= "boolean" then db.locked = true end
    if not N.Number(db.x) then db.x = 0 end
    if not N.Number(db.y) then db.y = 180 end
    if not N.Number(db.scale) or db.scale < 0.6 or db.scale > 2 then db.scale = 1 end
    if not N.Number(db.opacity) or db.opacity < 0.2 or db.opacity > 1 then db.opacity = 1 end
    return db
end

function A.RegisterOptions(eui, C, V, db)
    if not eui or not eui.RegisterPlugin then return end
    eui.RegisterPlugin("AlmightreeWaypoint", {
        label = "Almightree Waypoint",
        modules = { {
            key = "General", title = "Navigation arrow", pages = { "Display" },
            description = "Read-only prototype. Position and settings are independent of EUI profiles.",
            buildPage = function(_, parent, yOffset)
                local W, y = eui.Widgets, yOffset
                local _, h = W:SectionHeader(parent, "NAVIGATION", y); y = y - h
                _, h = W:Toggle(parent, "Enable navigation arrow", y,
                    function() return db.enabled end, function(v) C:SetEnabled(v) end); y = y - h
                _, h = W:Toggle(parent, "Preview", y,
                    function() return C.preview end, function(v) C:SetPreview(v) end); y = y - h
                _, h = W:Toggle(parent, "Unlock for dragging", y,
                    function() return not db.locked end, function(v) C:SetLocked(not v) end); y = y - h
                _, h = W:Button(parent, "Reset position", y, function() V:ResetPosition() end); y = y - h
                _, h = W:Slider(parent, "Scale", y, 0.6, 2, 0.05,
                    function() return db.scale end,
                    function(v) if N.Number(v) then db.scale = math.max(0.6, math.min(2, v)); V:ApplyAppearance() end end); y = y - h
                _, h = W:Slider(parent, "Opacity", y, 0.2, 1, 0.05,
                    function() return db.opacity end,
                    function(v) if N.Number(v) then db.opacity = math.max(0.2, math.min(1, v)); V:ApplyAppearance() end end); y = y - h
                return math.abs(y)
            end,
        } },
    })
end

function A.RegisterCommands(eui, C, V)
    SLASH_ALMIGHTREEWAYPOINT1 = "/atway"
    SlashCmdList.ALMIGHTREEWAYPOINT = function(message)
        local command = (message or ""):match("^%s*(%S*)"):lower()
        if command == "disable" then C:SetEnabled(false); return end
        if InCombatLockdown() then return end
        if command == "enable" then C:SetEnabled(true)
        elseif command == "preview" then C:SetPreview(not C.preview)
        elseif command == "unlock" then C:SetLocked(false)
        elseif command == "lock" then C:SetLocked(true)
        elseif command == "reset" then V:ResetPosition()
        elseif command == "options" and eui and eui.OpenPlugin then eui.OpenPlugin("AlmightreeWaypoint")
        else print("Almightree Waypoint: /atway enable, disable, preview, unlock, lock, reset, options") end
    end
end
