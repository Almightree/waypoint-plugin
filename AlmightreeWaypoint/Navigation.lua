local _, A = ...
local N = {}
A.Navigation = N

local function secret(v)
    return issecretvalue and issecretvalue(v)
end

function N.Number(v)
    return not secret(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function N.ID(v)
    return N.Number(v) and v > 0 and v % 1 == 0
end

function N.Table(v)
    return not secret(v) and type(v) == "table"
end

function N.Text(v)
    if not secret(v) and type(v) == "string" then return v:sub(1, 200) end
end

function N.Scalar(v)
    if secret(v) then return "<restricted>" end
    if v == nil or type(v) == "boolean" then return v end
    if N.Number(v) then return v end
    return N.Text(v) or "<unsupported>"
end

-- Only destination fields participate. Player location, labels, route source,
-- event names, timestamps, and the derived printable key are not identity.
N.IdentityFields = { "kind", "trackingType", "mapPinType", "id", "mapID", "x", "y" }
function N.IdentityChanges(old, new)
    local changed = {}
    for _, field in ipairs(N.IdentityFields) do
        if (old and old[field]) ~= (new and new[field]) then changed[#changed + 1] = field end
    end
    return table.concat(changed, ",")
end

function N.SameDestination(old, new)
    return old ~= nil and new ~= nil and N.IdentityChanges(old, new) == ""
end

function N.Point(x, y)
    return N.Number(x) and N.Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- Keep missing/error/restricted distinct from a successful getter returning nil.
function N.Read(namespace, method, ...)
    if not N.Table(namespace) or type(namespace[method]) ~= "function" then
        return { status = "missing" }
    end
    local ok, a, b, c, d = pcall(namespace[method], ...)
    if not ok then return { status = "error" } end
    local row = { status = "ok" }
    for i, v in pairs({ a, b, c, d }) do
        if secret(v) then row.status = "restricted" else row[i] = v end
    end
    return row
end

local function xy(object)
    if secret(object) then return nil, nil, "restricted" end
    if object == nil then return nil, nil, "missing" end
    if not N.Table(object) then return nil, nil, "invalid" end
    local ok, x, y = pcall(function() return object.x, object.y end)
    if ok and N.Point(x, y) then return x, y end
    if not ok then return nil, nil, "error" end
    return nil, nil, (secret(x) or secret(y)) and "restricted" or "invalid"
end

local function unavailable(row, prefix)
    return prefix .. "_" .. (row.status ~= "ok" and row.status
        or row[1] == nil and "nil" or row[1] == false and "false" or "invalid")
end

local function enum(api, group, key)
    local enums = api.Enum
    if N.Table(enums) and N.Table(enums[group]) then
        local value = enums[group][key]
        if N.Number(value) then return value end
    end
end

function N.Identity(api)
    local tracking = N.Read(api.C_SuperTrack, "IsSuperTrackingAnything")
    if tracking.status ~= "ok" then return nil, unavailable(tracking, "tracking") end
    if tracking[1] == false then return nil, "no_tracking" end
    if tracking[1] ~= true then return nil, "tracking_invalid" end
    local typeRow = N.Read(api.C_SuperTrack, "GetHighestPrioritySuperTrackingType")
    local kind = typeRow[1]
    if not N.Number(kind) then return nil, unavailable(typeRow, "tracking_type") end
    if kind == enum(api, "SuperTrackingType", "Quest") then
        local flag = N.Read(api.C_SuperTrack, "IsSuperTrackingQuest")
        if flag[1] ~= true then return nil, unavailable(flag, "quest_tracking") end
        local row = N.Read(api.C_SuperTrack, "GetSuperTrackedQuestID")
        local id = row[1]
        if N.ID(id) then return { kind = "quest", trackingType = kind, id = id, key = "quest:" .. id } end
        return nil, unavailable(row, "quest_id")
    elseif kind == enum(api, "SuperTrackingType", "UserWaypoint") then
        local flag = N.Read(api.C_SuperTrack, "IsSuperTrackingUserWaypoint")
        if flag[1] ~= true then return nil, unavailable(flag, "pin_tracking") end
        local row = N.Read(api.C_Map, "GetUserWaypoint")
        local pin = row[1]
        if not N.Table(pin) then return nil, unavailable(row, "pin") end
        if not N.ID(pin.uiMapID) then return nil, secret(pin.uiMapID) and "pin_map_restricted" or "pin_map_invalid" end
        local x, y, why = xy(pin.position)
        if x then
            return { kind = "pin", trackingType = kind, mapID = pin.uiMapID, x = x, y = y,
                key = table.concat({ "pin", pin.uiMapID, x, y }, ":") }
        end
        return nil, "pin_position_" .. why
    elseif kind == enum(api, "SuperTrackingType", "MapPin") then
        local flag = N.Read(api.C_SuperTrack, "IsSuperTrackingMapPin")
        if flag[1] ~= true then return nil, unavailable(flag, "map_pin_tracking") end
        local row = N.Read(api.C_SuperTrack, "GetSuperTrackedMapPin")
        if N.Number(row[1]) and row[1] == enum(api, "SuperTrackingMapPinType", "AreaPOI")
            and N.ID(row[2]) then
            return { kind = "poi", trackingType = kind, mapPinType = row[1], id = row[2], key = "poi:" .. row[2] }
        end
        if row.status ~= "ok" then return nil, unavailable(row, "map_pin") end
        if not N.Number(row[1]) then return nil, "map_pin_type_invalid" end
        if enum(api, "SuperTrackingMapPinType", "AreaPOI") == nil then return nil, "map_pin_enum_missing" end
        if row[1] ~= enum(api, "SuperTrackingMapPinType", "AreaPOI") then return nil, "unsupported_map_pin_type" end
        return nil, "map_pin_id_invalid"
    end
    if enum(api, "SuperTrackingType", "Quest") == nil or enum(api, "SuperTrackingType", "UserWaypoint") == nil
        or enum(api, "SuperTrackingType", "MapPin") == nil then return nil, "tracking_enum_missing" end
    return nil, "unsupported_tracking_type"
end

local function position(mapID, row, first)
    first = first or 1
    if row.status == "ok" and N.ID(mapID) and N.Point(row[first], row[first + 1]) then
        return { mapID = mapID, x = row[first], y = row[first + 1] }
    end
end

local function empty(row)
    return row.status == "ok" and row[1] == nil and row[2] == nil and (row[3] == nil or row[3] == "")
end

local function questPOI(api, mapID, questID, namespace)
    local result = N.Read(namespace or api.C_QuestLog, "GetQuestsOnMap", mapID)
    if result.status ~= "ok" then return nil, unavailable(result, "quest_poi") end
    if result[1] == nil then return nil, "quest_poi_missing" end
    if not N.Table(result[1]) then return nil, "quest_poi_invalid" end
    local rows = result[1]
    local why = "quest_poi_no_match"
    for i = 1, math.min(#rows, 512) do
        local row = rows[i]
        if N.Table(row) and N.ID(row.questID) and row.questID == questID
            and N.ID(row.mapID) and row.mapID == mapID and N.Point(row.x, row.y) then
            return { mapID = mapID, x = row.x, y = row.y }
        end
        if secret(row) or (N.Table(row) and secret(row.questID)) then
            why = "quest_poi_restricted"
        elseif N.Table(row) and row.questID == questID then
            if secret(row.mapID) or secret(row.x) or secret(row.y) then why = "quest_poi_restricted"
            elseif row.mapID ~= mapID then why = "quest_poi_map_mismatch"
            else why = "quest_poi_coordinates_invalid" end
        end
    end
    return nil, #rows > 512 and "quest_poi_scan_limit" or why
end

local function taskZonePosition(api, questID)
    local zone = N.Read(api.C_TaskQuest, "GetQuestZoneID", questID)
    if not N.ID(zone[1]) then return nil, unavailable(zone, "task_zone") end
    local location = N.Read(api.C_TaskQuest, "GetQuestLocation", questID, zone[1])
    local point = position(zone[1], location)
    if point then return point end
    -- Alternate map POI getters are independent sources, never portal substitutes.
    point = questPOI(api, zone[1], questID, api.C_TaskQuest)
    if point then return point end
    point = questPOI(api, zone[1], questID)
    if point then return point end
    return nil, unavailable(location, "task_zone_location")
end

local function eventPOIPosition(api, target, model)
    local active, why = N.Identity(api)
    if not active or active.kind ~= "poi" or active.id ~= target.id then
        model.eventIdentity = why or "changed"
        return nil, "event_poi_tracking_unverified"
    end
    local map = N.Read(api.C_EventScheduler, "GetEventUiMapID", target.id)
    model.eventMapStatus, model.eventMap = map.status, map[1]
    if map.status ~= "ok" or not N.ID(map[1]) then return nil, unavailable(map, "event_poi_map") end
    local result = N.Read(api.C_AreaPoiInfo, "GetAreaPOIInfo", map[1], target.id)
    model.eventPOIStatus = result.status
    local info = result[1]
    if result.status ~= "ok" or not N.Table(info) then return nil, unavailable(result, "event_poi") end
    model.returnedPOIID = N.Scalar(info.areaPoiID)
    if secret(info.areaPoiID) then return nil, "event_poi_id_restricted" end
    if not N.ID(info.areaPoiID) then return nil, "event_poi_id_invalid" end
    if info.areaPoiID ~= target.id then return nil, "event_poi_identity_mismatch" end
    local x, y, positionWhy = xy(info.position)
    if x == nil then return nil, "event_poi_position_" .. positionWhy end
    -- Re-read both active selection and reported map after the payload lookup.
    -- A POI refresh can move its projection without changing its stable identity.
    local current, currentWhy = N.Identity(api)
    if not current or not N.SameDestination(active, current) then
        model.eventIdentity = currentWhy or "changed"
        return nil, "event_poi_tracking_changed"
    end
    model.eventIdentity = "matched"
    local verifiedMap = N.Read(api.C_EventScheduler, "GetEventUiMapID", target.id)
    if verifiedMap.status ~= "ok" then return nil, unavailable(verifiedMap, "event_poi_map_recheck") end
    if verifiedMap[1] ~= map[1] then return nil, "event_poi_map_changed" end
    model.eventMapValidation = "matched"
    return { mapID = map[1], x = x, y = y }
end

-- Map x grows east, map y grows south; WoW facing is zero north, positive west.
-- An upright texture rotates counterclockwise; east is therefore -pi/2.
local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local function bearing(east, north, facing)
    local distance = math.sqrt(east * east + north * north)
    if not N.Number(distance) then return nil, nil, "distance_invalid" end
    if distance < 0.01 then return nil, distance, "coincident_coordinates" end
    return (atan2(-east, north) - facing + math.pi) % (2 * math.pi) - math.pi, distance
end

function N.Direction(playerMap, px, py, target, width, height, facing)
    if not N.ID(playerMap) then return nil, nil, "player_map_invalid" end
    if not N.Table(target) or not N.ID(target.mapID) then return nil, nil, "target_map_invalid" end
    if playerMap ~= target.mapID then return nil, nil, "map_mismatch" end
    if not N.Point(px, py) then return nil, nil, "player_position_invalid" end
    if not N.Point(target.x, target.y) then return nil, nil, "target_coordinates_invalid" end
    if not N.Number(width) or width <= 0 or not N.Number(height) or height <= 0 then
        return nil, nil, "map_dimensions_invalid"
    end
    if not N.Number(facing) then return nil, nil, "facing_invalid" end
    local east, north = (target.x - px) * width, (py - target.y) * height
    return bearing(east, north, facing)
end

local function worldID(id)
    return N.Number(id) and id >= 0 and id % 1 == 0 -- world/instance zero is valid
end

local function worldXY(vector)
    if secret(vector) then return nil, nil, "restricted" end
    if not N.Table(vector) then return nil, nil, vector == nil and "nil" or "invalid" end
    local ok, x, y = pcall(function() return vector.x, vector.y end)
    if not ok then return nil, nil, "error" end
    if secret(x) or secret(y) then return nil, nil, "restricted" end
    if N.Number(x) and N.Number(y) then return x, y end
    return nil, nil, "invalid"
end

function N.WorldDirection(api, playerMap, px, py, target, facing, diagnostic)
    diagnostic = diagnostic or {}
    diagnostic.coordinateSpace = "world"
    diagnostic.conversionAttempted = true
    if not N.ID(playerMap) or not N.Table(target) or not N.ID(target.mapID)
        or not N.Point(px, py) or not N.Point(target.x, target.y) then
        return nil, nil, "world_input_invalid"
    end
    local playerVector = N.Read(api, "CreateVector2D", px, py)
    local targetVector = N.Read(api, "CreateVector2D", target.x, target.y)
    if playerVector.status ~= "ok" or not N.Table(playerVector[1]) then return nil, nil, unavailable(playerVector, "player_map_vector") end
    if targetVector.status ~= "ok" or not N.Table(targetVector[1]) then return nil, nil, unavailable(targetVector, "target_map_vector") end
    local player = N.Read(api.C_Map, "GetWorldPosFromMapPos", playerMap, playerVector[1])
    local destination = N.Read(api.C_Map, "GetWorldPosFromMapPos", target.mapID, targetVector[1])
    local unit = N.Read(api, "UnitPosition", "player")
    diagnostic.playerWorldID, diagnostic.targetWorldID, diagnostic.unitWorldID = player[1], destination[1], unit[4]
    if player.status ~= "ok" then return nil, nil, unavailable(player, "player_world_conversion") end
    if destination.status ~= "ok" then return nil, nil, unavailable(destination, "target_world_conversion") end
    if unit.status ~= "ok" then return nil, nil, unavailable(unit, "player_world_position") end
    if not worldID(player[1]) or not worldID(destination[1]) or not worldID(unit[4]) then return nil, nil, "world_id_invalid" end
    if player[1] ~= destination[1] or player[1] ~= unit[4] then return nil, nil, "world_instance_mismatch" end
    local pX, pY, pWhy = worldXY(player[2])
    local tX, tY, tWhy = worldXY(destination[2])
    if not pX then return nil, nil, "player_world_vector_" .. pWhy end
    if not tX then return nil, nil, "target_world_vector_" .. tWhy end
    if not N.Number(unit[1]) or not N.Number(unit[2]) then return nil, nil, "player_world_position_invalid" end
    diagnostic.playerWorldX, diagnostic.playerWorldY = pX, pY
    diagnostic.targetWorldX, diagnostic.targetWorldY = tX, tY
    diagnostic.unitWorldX, diagnostic.unitWorldY = unit[1], unit[2]
    -- Matching IDs alone are insufficient if the map projection and player use
    -- different origins/phases. Require the converted player point to agree in XY.
    if math.abs(unit[1] - pX) > 1 or math.abs(unit[2] - pY) > 1 then return nil, nil, "player_world_position_mismatch" end
    if not N.Number(facing) then return nil, nil, "facing_invalid" end
    -- WoW world X grows north and world Y grows west; units are yards.
    return bearing(pY - tY, tX - pX, facing)
end

function N.Capture(api, target)
    local mapRow = N.Read(api.C_Map, "GetBestMapForUnit", "player")
    local mapID = mapRow[1]
    local model = { key = target.key, destination = N.Text(N.Read(api.C_SuperTrack, "GetSuperTrackedItemName")[1]) }
    model.playerMap = mapID
    model.conversionAttempted = false
    if not model.destination or model.destination == "" then
        model.destination = target.kind == "quest" and "Quest " .. target.id or "Tracked destination"
    end
    local text
    if target.kind == "quest" then
        text = N.Read(api.C_QuestLog, "GetNextWaypointText", target.id)
        model.instruction = N.Text(text[1])
        if model.instruction == "" then model.instruction = nil end
    end
    if not N.ID(mapID) then model.hideReason = unavailable(mapRow, "player_map"); return model end
    local nav = N.Read(api.C_Navigation, "GetNextWaypointForMap", mapID)
    model.instruction = model.instruction or N.Text(nav[3])
    local point
    model.hideReason = "target_coordinates_missing"
    if target.kind == "pin" then
        point = { mapID = target.mapID, x = target.x, y = target.y }
        model.source = "pin"
    elseif target.kind == "quest" then
        local onMap = N.Read(api.C_QuestLog, "GetNextWaypointForMap", target.id, mapID)
        local step = N.Read(api.C_QuestLog, "GetNextWaypoint", target.id)
        -- A quest-specific current-map step is authoritative. Otherwise a known remote
        -- step blocks generic navigation and final-objective fallback.
        local remoteStep = N.ID(step[1]) and step[1] ~= mapID
        point = position(mapID, onMap)
        if not point and not remoteStep then
            point = position(step[1], step, 2) or position(mapID, nav)
        end
        if point then
            model.source = "travel"
        elseif not remoteStep and empty(nav) and empty(onMap) and empty(step)
            and text.status == "ok" and (text[1] == nil or text[1] == "")
            and (model.instruction == nil or model.instruction == "") then
            point, model.hideReason = questPOI(api, mapID, target.id)
            model.source = point and "objective" or nil
            if not point then
                local taskPoint, taskWhy = taskZonePosition(api, target.id)
                if taskPoint then point, model.source = taskPoint, "task_zone"
                elseif taskWhy ~= "task_zone_missing" and taskWhy ~= "task_zone_nil" then model.hideReason = taskWhy end
            end
        elseif remoteStep then
            model.hideReason = "travel_step_other_map"
        elseif nav.status ~= "ok" then model.hideReason = unavailable(nav, "native_travel")
        elseif onMap.status ~= "ok" then model.hideReason = unavailable(onMap, "quest_map_travel")
        elseif step.status ~= "ok" then model.hideReason = unavailable(step, "quest_travel")
        elseif text.status ~= "ok" then model.hideReason = unavailable(text, "quest_instruction")
        elseif model.instruction and model.instruction ~= "" then model.hideReason = "travel_instruction_without_coordinates"
        else model.hideReason = "travel_coordinates_invalid"
        end
    elseif target.kind == "poi" then
        model.poiID = target.id
        point = position(mapID, nav)
        if not point and empty(nav) and (model.instruction == nil or model.instruction == "") then
            local result = N.Read(api.C_AreaPoiInfo, "GetAreaPOIInfo", mapID, target.id)
            model.localPOIStatus = result.status
            local info = result.status == "ok" and result[1]
            if N.Table(info) then
                -- Preserve existing local lookup behavior when payload identity is absent,
                -- but reject an explicitly restricted, malformed, or different ID.
                if secret(info.areaPoiID) then model.hideReason = "area_poi_id_restricted"
                elseif info.areaPoiID ~= nil and info.areaPoiID ~= target.id then model.hideReason = "area_poi_identity_mismatch"
                else
                    local x, y, why = xy(info.position)
                    if x then point = { mapID = mapID, x = x, y = y } end
                    if not point then model.hideReason = "area_poi_position_" .. why end
                end
            else
                model.hideReason = unavailable(result, "area_poi")
            end
            model.localPOIReason = point and "usable" or model.hideReason
            if not point then
                point, model.hideReason = eventPOIPosition(api, target, model)
                if point then model.source = "event_poi" end
            end
        elseif not point then
            model.hideReason = nav.status ~= "ok" and unavailable(nav, "native_travel") or "travel_step_without_coordinates"
        end
        model.source = point and (model.source or "poi") or nil
    end
    if point then
        model.targetMap = point.mapID
        model.targetX, model.targetY = point.x, point.y
        local player = N.Read(api.C_Map, "GetPlayerMapPosition", mapID, "player")
        local px, py, playerWhy = xy(player[1])
        local size = { status = "unused" }
        local facing = N.Read(api, "GetPlayerFacing")
        if point.mapID ~= mapID and (model.source == "task_zone" or model.source == "event_poi") then
            model.coordinateSpace = "world"
            if px == nil then model.hideReason = "player_position_invalid"
            else model.rotation, model.distance, model.hideReason = N.WorldDirection(api, mapID, px, py, point, facing[1], model) end
        else
            size = N.Read(api.C_Map, "GetMapWorldSize", mapID)
            model.coordinateSpace = "map"
            model.rotation, model.distance, model.hideReason = N.Direction(mapID, px, py, point, size[1], size[2], facing[1])
        end
        if model.hideReason == "player_position_invalid" then
            model.hideReason = player.status ~= "ok" and unavailable(player, "player_position") or "player_position_" .. playerWhy
        elseif model.hideReason == "map_dimensions_invalid" and size.status ~= "ok" then
            model.hideReason = unavailable(size, "map_dimensions")
        elseif model.hideReason == "facing_invalid" and facing.status ~= "ok" then
            model.hideReason = unavailable(facing, "facing")
        end
        if model.conversionAttempted then model.conversionResult = model.hideReason or "ok" end
    end
    -- No native distance is reused: its target identity/readiness cannot be verified.
    return model
end
