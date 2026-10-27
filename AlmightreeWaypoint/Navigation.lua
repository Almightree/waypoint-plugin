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
    if not N.Table(object) then return end
    local ok, x, y = pcall(function() return object.x, object.y end)
    if ok and N.Point(x, y) then return x, y end
end

local function enum(api, group, key)
    local enums = api.Enum
    if N.Table(enums) and N.Table(enums[group]) then
        local value = enums[group][key]
        if N.Number(value) then return value end
    end
end

function N.Identity(api)
    if N.Read(api.C_SuperTrack, "IsSuperTrackingAnything")[1] ~= true then return end
    local kind = N.Read(api.C_SuperTrack, "GetHighestPrioritySuperTrackingType")[1]
    if not N.Number(kind) then return end
    if kind == enum(api, "SuperTrackingType", "Quest") then
        if N.Read(api.C_SuperTrack, "IsSuperTrackingQuest")[1] ~= true then return end
        local id = N.Read(api.C_SuperTrack, "GetSuperTrackedQuestID")[1]
        if N.ID(id) then return { kind = "quest", id = id, key = "quest:" .. id } end
    elseif kind == enum(api, "SuperTrackingType", "UserWaypoint") then
        if N.Read(api.C_SuperTrack, "IsSuperTrackingUserWaypoint")[1] ~= true then return end
        local pin = N.Read(api.C_Map, "GetUserWaypoint")[1]
        if not N.Table(pin) or not N.ID(pin.uiMapID) then return end
        local x, y = xy(pin.position)
        if x then
            return { kind = "pin", mapID = pin.uiMapID, x = x, y = y,
                key = table.concat({ "pin", pin.uiMapID, x, y }, ":") }
        end
    elseif kind == enum(api, "SuperTrackingType", "MapPin") then
        if N.Read(api.C_SuperTrack, "IsSuperTrackingMapPin")[1] ~= true then return end
        local row = N.Read(api.C_SuperTrack, "GetSuperTrackedMapPin")
        if N.Number(row[1]) and row[1] == enum(api, "SuperTrackingMapPinType", "AreaPOI")
            and N.ID(row[2]) then
            return { kind = "poi", id = row[2], key = "poi:" .. row[2] }
        end
    end
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
    if result.status ~= "ok" or not N.Table(result[1]) then return end
    local rows = result[1]
    for i = 1, math.min(#rows, 512) do
        local row = rows[i]
        if N.Table(row) and N.ID(row.questID) and row.questID == questID
            and N.ID(row.mapID) and row.mapID == mapID and N.Point(row.x, row.y) then
            return { mapID = mapID, x = row.x, y = row.y }
        end
    end
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
    if not N.ID(playerMap) or not N.Table(target) or not N.ID(target.mapID)
        or playerMap ~= target.mapID or not N.Point(px, py) or not N.Point(target.x, target.y)
        or not N.Number(width) or width <= 0 or not N.Number(height) or height <= 0
        or not N.Number(facing) then return end
    local east, north = (target.x - px) * width, (py - target.y) * height
    local distance = math.sqrt(east * east + north * north)
    if not N.Number(distance) then return end
    -- Coincident points have a distance but no defined bearing, and imply no arrival state.
    if distance < 0.01 then return nil, distance end
    local rotation = (atan2(-east, north) - facing + math.pi) % (2 * math.pi) - math.pi
    return rotation, distance
end

function N.Capture(api, target)
    local mapID = N.Read(api.C_Map, "GetBestMapForUnit", "player")[1]
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
    if not N.ID(mapID) then return model end
    local nav = N.Read(api.C_Navigation, "GetNextWaypointForMap", mapID)
    model.instruction = model.instruction or N.Text(nav[3])
    local point
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
            point = questPOI(api, mapID, target.id)
            model.source = point and "objective" or nil
        end
    elseif target.kind == "poi" then
        point = position(mapID, nav)
        if not point and empty(nav) and (model.instruction == nil or model.instruction == "") then
            local result = N.Read(api.C_AreaPoiInfo, "GetAreaPOIInfo", mapID, target.id)
            local info = result.status == "ok" and result[1]
            if N.Table(info) then
                local x, y = xy(info.position)
                if x then point = { mapID = mapID, x = x, y = y } end
            end
        end
        model.source = point and "poi" or nil
    end
    if point then
        local player = N.Read(api.C_Map, "GetPlayerMapPosition", mapID, "player")[1]
        local px, py = xy(player)
        local size = N.Read(api.C_Map, "GetMapWorldSize", mapID)
        local facing = N.Read(api, "GetPlayerFacing")[1]
        model.rotation, model.distance = N.Direction(mapID, px, py, point, size[1], size[2], facing)
    end
    -- No native distance is reused: its target identity/readiness cannot be verified.
    return model
end
