-- Diagnostic prototype: no tracking setters, hooks, or Blizzard frame access.
local frame = CreateFrame("Frame")
local enabled, elapsed = false, 0
local LIMIT = 40
local SETTLE_DELAY = 0.25
local pendingReason, pendingElapsed

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

local function readProjected(namespace, method, project, ...)
    if type(namespace) ~= "table" or type(namespace[method]) ~= "function" then
        return { status = "missing" }
    end
    local ok, a, b, c = pcall(namespace[method], ...)
    if not ok then return { status = "error" } end
    if project and not restricted(a) and a ~= nil then
        ok, a, b, c = pcall(project, a)
        if not ok then return { status = "error" } end
    end
    return { status = "ok", scalar(a), scalar(b), scalar(c) }
end

local function read(namespace, method, ...)
    return readProjected(namespace, method, nil, ...)
end

local function number(value)
    return not restricted(value) and type(value) == "number"
end

local function questPosition(namespace, mapID, questID)
    return readProjected(namespace, "GetQuestsOnMap", function(rows)
        -- Keep only the first matching POI, never the map's entire quest list.
        local hidden = false
        for i = 1, math.min(#rows, 512) do
            local row = rows[i]
            if restricted(row) then
                hidden = true
            elseif type(row) == "table" then
                if restricted(row.questID) then
                    hidden = true
                elseif row.questID == questID then
                    return row.mapID, row.x, row.y
                end
            end
        end
        if hidden then return "<restricted>" end
        if #rows > 512 then return "<scan-limit>" end
    end, mapID)
end

local function areaPosition(info)
    local pos = info.position
    if restricted(pos) then return pos end
    if pos == nil then return nil end
    return pos.x, pos.y
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
        mapPinTracked = read(C_SuperTrack, "IsSuperTrackingMapPin"),
        trackedMapPin = read(C_SuperTrack, "GetSuperTrackedMapPin"),
        destination = read(C_SuperTrack, "GetSuperTrackedItemName"),
        distance = read(C_Navigation, "GetDistance"),
        navigationState = read(C_Navigation, "GetTargetState"),
        screenPositionValid = read(C_Navigation, "HasValidScreenPosition"),
        facing = read(_G, "GetPlayerFacing"),
        flying = read(_G, "IsFlying", "player"),
        mounted = read(_G, "IsMounted"),
        arrowState = read(AlmightreeWaypointDiagnostics, "GetArrowState"),
        arrowTarget = read(AlmightreeWaypointDiagnostics, "GetTarget"),
        arrowUpdatedAt = read(AlmightreeWaypointDiagnostics, "GetUpdatedAt"),
        map = read(C_Map, "GetBestMapForUnit", "player"),
    }
    local mapID = s.map[1]
    local questID = s.questID[1]
    if s.questTracked.status == "ok" and s.questTracked[1] == true
        and s.questID.status == "ok" and number(questID) and questID > 0 then
        s.questNextWaypoint = read(C_QuestLog, "GetNextWaypoint", questID)
        s.questNextWaypointText = read(C_QuestLog, "GetNextWaypointText", questID)
        s.taskQuestZone = read(C_TaskQuest, "GetQuestZoneID", questID)
        if s.map.status == "ok" and number(mapID) then
            s.questNextWaypointForMap = read(C_QuestLog, "GetNextWaypointForMap", questID, mapID)
            s.questPOIPosition = questPosition(C_QuestLog, mapID, questID)
            s.taskQuestPOIPosition = questPosition(C_TaskQuest, mapID, questID)
            s.taskQuestLocation = read(C_TaskQuest, "GetQuestLocation", questID, mapID)
        end
        local zoneID = s.taskQuestZone[1]
        if s.taskQuestZone.status == "ok" and number(zoneID) and zoneID > 0 then
            s.taskQuestZoneLocation = read(C_TaskQuest, "GetQuestLocation", questID, zoneID)
            s.questPOIPositionInTaskZone = questPosition(C_QuestLog, zoneID, questID)
            s.taskQuestPOIPositionInTaskZone = questPosition(C_TaskQuest, zoneID, questID)
        end
    end
    local pinType, pinID = s.trackedMapPin[1], s.trackedMapPin[2]
    local areaType = Enum and Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.AreaPOI
    if s.mapPinTracked.status == "ok" and s.mapPinTracked[1] == true
        and s.trackedMapPin.status == "ok" and number(pinType) and number(areaType)
        and pinType == areaType and number(pinID) and pinID > 0
        and s.map.status == "ok" and number(mapID) then
        s.areaPOIPosition = readProjected(C_AreaPoiInfo, "GetAreaPOIInfo", areaPosition, mapID, pinID)
    end
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
    "QUEST_POI_UPDATE", "AREA_POIS_UPDATED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
}

local function stop()
    enabled = false
    pendingReason, pendingElapsed = nil, nil
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
        if pendingReason then
            pendingElapsed = pendingElapsed + delta
            if pendingElapsed >= SETTLE_DELAY then
                local reason = pendingReason
                pendingReason, pendingElapsed = nil, nil
                sample(reason .. ":settled")
            end
        end
        elapsed = elapsed + delta
        if elapsed < 2 then return end
        elapsed = 0
        sample("poll")
    end)
    sample("start")
end

frame:SetScript("OnEvent", function(_, event)
    if not enabled then return end
    sample(event)
    if event == "SUPER_TRACKING_CHANGED" or event == "SUPER_TRACKING_PATH_UPDATED" then
        -- Coalesce bursts; the follow-up reads the current target, never cached IDs.
        pendingReason, pendingElapsed = event, 0
    end
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
            "nextWaypoint", "questNextWaypoint", "questNextWaypointForMap",
            "questNextWaypointText", "playerPosition", "facing", "placedPin",
            "mapPinTracked", "trackedMapPin", "questPOIPosition",
            "taskQuestPOIPosition", "taskQuestLocation", "taskQuestZone", "taskQuestZoneLocation",
            "questPOIPositionInTaskZone", "taskQuestPOIPositionInTaskZone", "areaPOIPosition",
            "flying", "mounted", "arrowState", "arrowTarget", "arrowUpdatedAt" }
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
