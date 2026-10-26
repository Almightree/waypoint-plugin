-- Diagnostic prototype: no tracking setters, hooks, or Blizzard frame access.
local frame = CreateFrame("Frame")
local enabled, elapsed = false, 0
local LIMIT = 40

local function restricted(value)
    return issecretvalue and issecretvalue(value)
end

local function scalar(value)
    if restricted(value) then return "<restricted>" end
    local kind = type(value)
    if kind == "nil" then return "<nil>" end
    if kind == "number" or kind == "boolean" then return value end
    if kind == "string" then return value:sub(1, 200) end
    return "<unsupported>"
end

local function read(namespace, method, ...)
    if type(namespace) ~= "table" or type(namespace[method]) ~= "function" then
        return { status = "missing" }
    end
    local ok, a, b, c = pcall(namespace[method], ...)
    if not ok then return { status = "error" } end
    return { status = "ok", scalar(a), scalar(b), scalar(c) }
end

local function number(value)
    return not restricted(value) and type(value) == "number"
end

local function database()
    if type(WaypointProbeDB) ~= "table" then WaypointProbeDB = {} end
    if type(WaypointProbeDB.samples) ~= "table" then WaypointProbeDB.samples = {} end
    return WaypointProbeDB
end

local function sample(reason)
    -- Avoid recording or printing combat-derived data. Retry manually after combat.
    if InCombatLockdown() then return false end
    local db = database()
    local s = {
        reason = reason,
        time = read(_G, "GetTime"),
        build = read(_G, "GetBuildInfo"),
        tracking = read(C_SuperTrack, "IsSuperTrackingAnything"),
        trackingType = read(C_SuperTrack, "GetHighestPrioritySuperTrackingType"),
        userWaypointTracked = read(C_SuperTrack, "IsSuperTrackingUserWaypoint"),
        questTracked = read(C_SuperTrack, "IsSuperTrackingQuest"),
        questID = read(C_SuperTrack, "GetSuperTrackedQuestID"),
        destination = read(C_SuperTrack, "GetSuperTrackedItemName"),
        distance = read(C_Navigation, "GetDistance"),
        navigationState = read(C_Navigation, "GetTargetState"),
        screenPositionValid = read(C_Navigation, "HasValidScreenPosition"),
        facing = read(_G, "GetPlayerFacing"),
        map = read(C_Map, "GetBestMapForUnit", "player"),
    }
    local mapID = s.map[1]
    if s.map.status == "ok" and number(mapID) then
        s.nextWaypoint = read(C_Navigation, "GetNextWaypointForMap", mapID)
        s.mapSize = read(C_Map, "GetMapWorldSize", mapID)
        local ok, x, y = pcall(function()
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if restricted(pos) or not pos then return nil, nil end
            return pos.x, pos.y
        end)
        s.playerPosition = ok and { status = "ok", scalar(x), scalar(y) }
            or { status = "unavailable" }
    end
    local ok, id, x, y = pcall(function()
        if not C_Map or not C_Map.GetUserWaypoint then return nil end
        local pin = C_Map.GetUserWaypoint()
        if restricted(pin) or not pin then return nil end
        local pos = pin.position
        if restricted(pos) or not pos then return pin.uiMapID end
        return pin.uiMapID, pos.x, pos.y
    end)
    s.placedPin = ok and { status = "ok", scalar(id), scalar(x), scalar(y) }
        or { status = "unavailable" }
    -- placedPin may exist without being tracked: never treat it as the active target.
    db.samples[#db.samples + 1] = s
    while #db.samples > LIMIT do table.remove(db.samples, 1) end
    return true
end

local events = {
    "SUPER_TRACKING_CHANGED", "SUPER_TRACKING_PATH_UPDATED",
    "USER_WAYPOINT_UPDATED", "NAVIGATION_DESTINATION_REACHED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
}

local function stop()
    enabled = false
    frame:UnregisterAllEvents()
    frame:SetScript("OnUpdate", nil)
end

local function start()
    stop()
    enabled, elapsed = true, 0
    local db = database()
    db.unavailableEvents = {}
    for _, event in ipairs(events) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then db.unavailableEvents[#db.unavailableEvents + 1] = event end
    end
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 2 then return end
        elapsed = 0
        sample("poll")
    end)
    sample("start")
end

frame:SetScript("OnEvent", function(_, event)
    if enabled then sample(event) end
end)

local function say(message)
    print("WaypointProbe: " .. message)
end

SLASH_WAYPOINTPROBE1 = "/wpprobe"
SlashCmdList.WAYPOINTPROBE = function(message)
    -- No chat/history mutations from this diagnostic in combat.
    if InCombatLockdown() then return end
    local command = (message or ""):match("^%s*(%S*)"):lower()
    if command == "start" then
        start()
        say("Recording up to 40 samples; /wpprobe stop when finished.")
    elseif command == "stop" then
        stop()
        say("Stopped. /reload to flush samples to SavedVariables.")
    elseif command == "clear" then
        database().samples = {}
        say("Samples cleared.")
    elseif command == "sample" then
        sample("manual")
        say("Snapshot recorded.")
    elseif command == "dump" then
        local samples = database().samples
        local last = samples[#samples]
        if not last then say("No samples. Use /wpprobe sample."); return end
        say("Latest snapshot (" .. last.reason .. "); full samples are in SavedVariables.")
        local keys = { "tracking", "trackingType", "userWaypointTracked", "questTracked",
            "questID", "destination", "distance", "navigationState", "map",
            "nextWaypoint", "playerPosition", "facing", "placedPin" }
        for _, key in ipairs(keys) do
            local row = last[key]
            if row then
                local values = {}
                for i = 1, #row do
                    -- Stored values were sanitized before saving. Escape chat markup.
                    values[i] = tostring(scalar(row[i])):gsub("|", "||")
                end
                say(key .. ": " .. row.status .. " " .. table.concat(values, ", "))
            end
        end
    else
        say("Commands: sample, dump, start, stop, clear. Recording is off by default.")
    end
end
