local _, A = ...
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    loader:UnregisterAllEvents()
    AlmightreeWaypointDB = A.Settings(AlmightreeWaypointDB)
    local db = AlmightreeWaypointDB
    local view = A.NewDisplay(db)
    local driver = CreateFrame("Frame")
    local controller = A.NewController(_G, driver, view, db)
    -- Optional read-only bridge for WaypointProbe; no frame or controller is exposed.
    AlmightreeWaypointDiagnostics = {
        GetArrowState = function() return view:GetArrowState() end,
        GetTarget = function() return view:GetTarget() end,
        GetUpdatedAt = function() return view:GetUpdatedAt() end,
    }
    view:RegisterSkin(EllesmereUI)
    A.RegisterOptions(EllesmereUI, controller, view, db)
    A.RegisterCommands(EllesmereUI, controller, view)
    controller:SetEnabled(db.enabled)
end)
