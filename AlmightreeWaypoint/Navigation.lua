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

function N.Point(x, y)
    return N.Number(x) and N.Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- Keep missing/error/restricted distinct from a successful getter returning nil.
function N.Read(namespace, method, ...)
    if not N.Table(namespace) or type(namespace[method]) ~= "function" then
        return { status = "missing" }
    end
    local ok, a, b, c = pcall(namespace[method], ...)
    if not ok then return { status = "error" } end
    local row = { status = "ok" }
    for i, v in pairs({ a, b, c }) do
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
        if N.ID(id) then return { kind = "quest", id = id, key = "quest:" .. id } end
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
            return { kind = "pin", mapID = pin.uiMapID, x = x, y = y,
                key = table.concat({ "pin", pin.uiMapID, x, y }, ":") }
        end
        return nil, "pin_position_" .. why
    elseif kind == enum(api, "SuperTrackingType", "MapPin") then
        local flag = N.Read(api.C_SuperTrack, "IsSuperTrackingMapPin")
        if flag[1] ~= true then return nil, unavailable(flag, "map_pin_tracking") end
        local row = N.Read(api.C_SuperTrack, "GetSuperTrackedMapPin")
        if N.Number(row[1]) and row[1] == enum(api, "SuperTrackingMapPinType", "AreaPOI")
            and N.ID(row[2]) then
            return { kind = "poi", id = row[2], key = "poi:" .. row[2] }
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

local function questPOI(api, mapID, questID)
    local result = N.Read(api.C_QuestLog, "GetQuestsOnMap", mapID)
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
    local distance = math.sqrt(east * east + north * north)
    if not N.Number(distance) then return nil, nil, "distance_invalid" end
    -- Coincident points have a distance but no defined bearing, and imply no arrival state.
    if distance < 0.01 then return nil, distance, "coincident_coordinates" end
    local rotation = (atan2(-east, north) - facing + math.pi) % (2 * math.pi) - math.pi
    return rotation, distance
end

function N.Capture(api, target)
    local mapRow = N.Read(api.C_Map, "GetBestMapForUnit", "player")
    local mapID = mapRow[1]
    local model = { key = target.key, destination = N.Text(N.Read(api.C_SuperTrack, "GetSuperTrackedItemName")[1]) }
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
        point = position(mapID, nav)
        if not point and empty(nav) and (model.instruction == nil or model.instruction == "") then
            local result = N.Read(api.C_AreaPoiInfo, "GetAreaPOIInfo", mapID, target.id)
            local info = result.status == "ok" and result[1]
            if N.Table(info) then
                local x, y, why = xy(info.position)
                if x then point = { mapID = mapID, x = x, y = y } end
                if not point then model.hideReason = "area_poi_position_" .. why end
            else
                model.hideReason = unavailable(result, "area_poi")
            end
        elseif not point then
            model.hideReason = nav.status ~= "ok" and unavailable(nav, "native_travel") or "travel_step_without_coordinates"
        end
        model.source = point and "poi" or nil
    end
    if point then
        local player = N.Read(api.C_Map, "GetPlayerMapPosition", mapID, "player")
        local px, py, playerWhy = xy(player[1])
        local size = N.Read(api.C_Map, "GetMapWorldSize", mapID)
        local facing = N.Read(api, "GetPlayerFacing")
        model.rotation, model.distance, model.hideReason = N.Direction(mapID, px, py, point, size[1], size[2], facing[1])
        if model.hideReason == "player_position_invalid" then
            model.hideReason = player.status ~= "ok" and unavailable(player, "player_position") or "player_position_" .. playerWhy
        elseif model.hideReason == "map_dimensions_invalid" and size.status ~= "ok" then
            model.hideReason = unavailable(size, "map_dimensions")
        elseif model.hideReason == "facing_invalid" and facing.status ~= "ok" then
            model.hideReason = unavailable(facing, "facing")
        end
    end
    -- No native distance is reused: its target identity/readiness cannot be verified.
    return model
end
