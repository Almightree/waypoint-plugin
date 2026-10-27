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

local contextFields = { "event", "time", "playerMap", "zone", "subzone", "realZone" }
local resolutionFields = { "key", "source", "poiID", "localPOIStatus", "localPOIReason",
    "eventMapStatus", "eventMap", "eventPOIStatus", "returnedPOIID", "eventIdentity", "eventMapValidation",
    "playerMap", "targetMap", "targetX", "targetY", "coordinateSpace", "conversionAttempted", "conversionResult",
    "playerWorldID", "targetWorldID", "unitWorldID", "playerWorldX", "playerWorldY",
    "targetWorldX", "targetWorldY", "unitWorldX", "unitWorldY", "hideReason", "sequence", "time", "event" }
local invalidationFields = { "sequence", "reason", "comparison", "changedFields", "oldKey", "newKey",
    "old_kind", "old_trackingType", "old_mapPinType", "old_id", "old_mapID", "old_x", "old_y",
    "new_kind", "new_trackingType", "new_mapPinType", "new_id", "new_mapID", "new_x", "new_y",
    "event", "time", "playerMap", "zone", "subzone", "realZone" }

local function readRecord(method, fields)
    local namespace = AlmightreeWaypointDiagnostics
    if type(namespace) ~= "table" or type(namespace[method]) ~= "function" then return { status = "missing" } end
    local ok, result = pcall(function()
        local record = namespace[method]()
        if restricted(record) or type(record) ~= "table" then return { status = "ok", value = scalar(record) } end
        local clean = { status = "ok" }
        for _, field in ipairs(fields) do clean[field] = scalar(record[field]) end
        return clean
    end)
    return ok and result or { status = "error" }
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
        zone = read(_G, "GetZoneText"),
        subzone = read(_G, "GetSubZoneText"),
        realZone = read(_G, "GetRealZoneText"),
        arrowState = read(AlmightreeWaypointDiagnostics, "GetArrowState"),
        arrowTarget = read(AlmightreeWaypointDiagnostics, "GetTarget"),
        arrowUpdatedAt = read(AlmightreeWaypointDiagnostics, "GetUpdatedAt"),
        arrowInvalidation = readRecord("GetLastInvalidation", invalidationFields),
        arrowEvent = readRecord("GetLastEvent", contextFields),
        arrowZoneEvent = readRecord("GetLastZoneEvent", contextFields),
        arrowCoordinateSpace = read(AlmightreeWaypointDiagnostics, "GetCoordinateSpace"),
        arrowWorldIDs = read(AlmightreeWaypointDiagnostics, "GetWorldIDs"),
        arrowResolution = readRecord("GetResolution", resolutionFields),
        arrowLastConversion = readRecord("GetLastConversion", resolutionFields),
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
        and pinType == areaType and number(pinID) and pinID > 0 then
        if s.map.status == "ok" and number(mapID) then
            s.areaPOIPosition = readProjected(C_AreaPoiInfo, "GetAreaPOIInfo", areaPosition, mapID, pinID)
        end
        -- Separate investigation: an event's reported map is not the task quest's map.
        s.areaPOIEventMap = read(C_EventScheduler, "GetEventUiMapID", pinID)
        s.areaPOIEventZone = read(C_EventScheduler, "GetEventZoneName", pinID)
        local eventMap = s.areaPOIEventMap[1]
        if s.areaPOIEventMap.status == "ok" and number(eventMap) and eventMap > 0 and eventMap % 1 == 0 then
            s.areaPOIEventPosition = readProjected(C_AreaPoiInfo, "GetAreaPOIInfo", areaPosition, eventMap, pinID)
        end
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
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_REGEN_ENABLED",
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
    if event == "SUPER_TRACKING_CHANGED" or event == "SUPER_TRACKING_PATH_UPDATED"
        or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
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
            "flying", "mounted", "zone", "subzone", "realZone", "arrowState", "arrowTarget", "arrowUpdatedAt",
            "arrowCoordinateSpace", "arrowWorldIDs", "areaPOIEventMap", "areaPOIEventZone", "areaPOIEventPosition" }
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
        for _, key in ipairs({ "arrowInvalidation", "arrowEvent", "arrowZoneEvent", "arrowResolution", "arrowLastConversion" }) do
            local row = last[key]
            if row then
                say(key .. ": " .. row.status)
                local fields = key == "arrowInvalidation" and invalidationFields
                    or (key == "arrowResolution" or key == "arrowLastConversion") and resolutionFields or contextFields
                if row.value ~= nil then say(key .. ".value: " .. tostring(scalar(row.value)):gsub("|", "||")) end
                for _, field in ipairs(fields) do
                    if row[field] ~= nil then
                        say(key .. "." .. field .. ": " .. tostring(scalar(row[field])):gsub("|", "||"))
                    end
                end
            end
        end
    else
        say("Commands: sample, dump, start, stop, clear. Recording is off by default.")
    end
end
