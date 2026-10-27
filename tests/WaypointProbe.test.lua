-- Run from the repository root: lua tests/WaypointProbe.test.lua
local frame = { scripts = {} }
function frame:SetScript(name, fn) self.scripts[name] = fn end
function frame:RegisterEvent() end
function frame:UnregisterAllEvents() end
function CreateFrame() return frame end
local combat, tracked, questID, mapID = false, true, 101, 42
function InCombatLockdown() return combat end
local secret = {}
function issecretvalue(value) return value == secret end
function GetTime() return 1 end
function GetBuildInfo() return "test", "123", "date" end
SlashCmdList = {}
local output = {}
function print(message) output[#output + 1] = message end
C_SuperTrack = {
    IsSuperTrackingQuest = function() return tracked end,
    GetSuperTrackedQuestID = function() return questID end,
}
C_Map = { GetBestMapForUnit = function() return mapID end }
C_Navigation = { GetNextWaypointForMap = function(id) assert(id == mapID); return .1, .2 end }
local calls = 0
local function getters()
    return {
        GetNextWaypoint = function(id)
            assert(id == questID); calls = calls + 1; return 77, .3, .4
        end,
        GetNextWaypointForMap = function(id, map)
            assert(id == questID and map == mapID); calls = calls + 1; return .5, .6
        end,
        GetNextWaypointText = function(id)
            assert(id == questID); calls = calls + 1; return "Take |portal"
        end,
    }
end
C_QuestLog = getters()
dofile("WaypointProbe/WaypointProbe.lua")
local function command(cmd) SlashCmdList.WAYPOINTPROBE(cmd) end
local function last() local s = WaypointProbeDB.samples; return s[#s] end
local function count() return #WaypointProbeDB.samples end
local function event(name) frame.scripts.OnEvent(frame, name) end
local function tick(delta) if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, delta) end end

command("sample")
assert(calls == 3)
assert(last().questNextWaypoint[1] == 77 and last().questNextWaypoint[3] == .4)
assert(last().questNextWaypointForMap[1] == .5)
assert(last().questNextWaypointText[1] == "Take |portal")
command("dump")
assert(table.concat(output, "\n"):find("questNextWaypointText: ok Take ||portal", 1, true))

command("start")
event("SUPER_TRACKING_CHANGED")
assert(last().reason == "SUPER_TRACKING_CHANGED")
local before = count()
tick(.1); assert(count() == before)
questID = 202
event("SUPER_TRACKING_CHANGED")
tick(.2); assert(last().reason == "SUPER_TRACKING_CHANGED")
tick(.06)
assert(last().reason == "SUPER_TRACKING_CHANGED:settled" and last().questID[1] == 202)
event("SUPER_TRACKING_PATH_UPDATED")
tracked = false -- A stale quest ID can remain after switching to a pin or clearing.
before = calls
tick(.25)
assert(last().reason == "SUPER_TRACKING_PATH_UPDATED:settled")
assert(last().questNextWaypoint == nil and calls == before)
command("sample"); assert(last().questNextWaypointText == nil)
tracked = true
for _, id in ipairs({ 0, secret, "bad" }) do
    questID = id; command("sample"); assert(last().questNextWaypoint == nil)
end
questID = 303
tracked = secret; command("sample"); assert(last().questNextWaypoint == nil)
tracked = true
mapID = secret; before = calls; command("sample")
assert(calls == before + 2 and last().questNextWaypointForMap == nil)
mapID = 42

C_QuestLog = nil; command("sample")
assert(last().questNextWaypoint.status == "missing")
assert(last().questNextWaypointForMap.status == "missing")
assert(last().questNextWaypointText.status == "missing")
C_QuestLog = {
    GetNextWaypoint = function() error("unavailable") end,
    GetNextWaypointForMap = function() return secret, nil end,
    GetNextWaypointText = function() return secret end,
}
command("sample")
assert(last().questNextWaypoint.status == "error")
assert(last().questNextWaypointForMap[1] == "<restricted>")
assert(last().questNextWaypointForMap[2] == "<nil>")
assert(last().questNextWaypointText[1] == "<restricted>")
C_QuestLog = getters()

-- Objective/POI coordinates remain separate from intermediate portal waypoints.
command("sample")
assert(last().questPOIPosition.status == "missing")
assert(last().taskQuestLocation.status == "missing")
assert(last().taskQuestZone.status == "missing")
local objectiveX = .81
C_QuestLog.GetQuestsOnMap = function(map)
    assert(map == mapID or map == 88)
    return {
        { questID = 999, mapID = map, x = .01, y = .02 },
        { questID = questID, mapID = map, x = objectiveX, y = .82 },
        { questID = questID, mapID = map, x = .91, y = .92 },
    }
end
C_TaskQuest = {
    GetQuestZoneID = function(id) assert(id == questID); return 88 end,
    GetQuestLocation = function(id, map)
        assert(id == questID and (map == mapID or map == 88)); return .71, .72
    end,
    GetQuestsOnMap = function(map)
        return { { questID = questID, mapID = map, x = .61, y = .62 } }
    end,
}
command("sample")
assert(last().questPOIPosition[1] == 42 and last().questPOIPosition[2] == .81)
assert(last().taskQuestPOIPosition[2] == .61)
assert(last().taskQuestLocation[1] == .71)
assert(last().taskQuestZone[1] == 88 and last().taskQuestZoneLocation[2] == .72)
assert(last().questPOIPositionInTaskZone[1] == 88)
assert(last().taskQuestPOIPositionInTaskZone[1] == 88)
assert(last().questNextWaypoint[1] == 77) -- Preserved intermediate route.
command("dump")
assert(table.concat(output, "\n"):find("questPOIPosition: ok 42", 1, true))
questID, objectiveX = 404, .41
event("SUPER_TRACKING_CHANGED"); tick(.25)
assert(last().questPOIPosition[2] == .41)
tracked = false
event("SUPER_TRACKING_CHANGED"); tick(.25)
assert(last().questPOIPosition == nil and last().taskQuestZone == nil)
tracked = true
C_QuestLog.GetQuestsOnMap = function() return {} end
command("sample"); assert(last().questPOIPosition[1] == "<nil>")
C_QuestLog.GetQuestsOnMap = function() return secret end
command("sample"); assert(last().questPOIPosition[1] == "<restricted>")
C_QuestLog.GetQuestsOnMap = function()
    return { secret, { questID = secret }, { questID = 999 } }
end
command("sample"); assert(last().questPOIPosition[1] == "<restricted>")
C_QuestLog.GetQuestsOnMap = function()
    return { { questID = questID, mapID = secret, x = secret } }
end
command("sample")
assert(last().questPOIPosition[1] == "<restricted>" and last().questPOIPosition[2] == "<restricted>")
C_QuestLog.GetQuestsOnMap = function() error("not available") end
C_TaskQuest.GetQuestZoneID = function() return secret end
C_TaskQuest.GetQuestLocation = function() return secret, nil end
command("sample")
assert(last().questPOIPosition.status == "error")
assert(last().taskQuestZoneLocation == nil and last().taskQuestLocation[1] == "<restricted>")
C_QuestLog.GetQuestsOnMap = function()
    local rows = {}; for i = 1, 513 do rows[i] = { questID = 999 } end; return rows
end
command("sample"); assert(last().questPOIPosition[1] == "<scan-limit>")

-- Map-pin POIs must work with no supertracked quest (the captured type-6 case).
local pinTracked, pinType, pinID = true, 0, 123
Enum = { SuperTrackingMapPinType = { AreaPOI = 0 } }
C_SuperTrack.IsSuperTrackingMapPin = function() return pinTracked end
C_SuperTrack.GetSuperTrackedMapPin = function() return pinType, pinID end
local poiCalls, poiX = 0, .21
C_AreaPoiInfo = { GetAreaPOIInfo = function(map, id)
    assert(map == mapID and id == pinID); poiCalls = poiCalls + 1
    return { position = { x = poiX, y = .22 }, linkedUiMapID = 900 }
end }
tracked = false
command("sample")
assert(last().areaPOIPosition[1] == .21 and last().areaPOIPosition[2] == .22)
assert(last().questPOIPosition == nil and last().trackedMapPin[2] == 123)
pinID, poiX = 456, .31
event("SUPER_TRACKING_CHANGED"); tick(.25); assert(last().areaPOIPosition[1] == .31)
pinTracked = false; before = poiCalls
event("SUPER_TRACKING_CHANGED"); tick(.25)
assert(last().areaPOIPosition == nil and poiCalls == before)
pinTracked = true
for _, value in ipairs({ secret, 1 }) do
    pinType = value; command("sample"); assert(last().areaPOIPosition == nil)
end
pinType = 0; pinID = secret
command("sample"); assert(last().areaPOIPosition == nil)
pinID = 456; mapID = secret
command("sample"); assert(last().areaPOIPosition == nil)
mapID = 42; Enum = nil
command("sample"); assert(last().areaPOIPosition == nil)
Enum = { SuperTrackingMapPinType = { AreaPOI = 0 } }
C_AreaPoiInfo = nil
command("sample"); assert(last().areaPOIPosition.status == "missing")
C_AreaPoiInfo = { GetAreaPOIInfo = function() return { position = secret } end }
command("sample"); assert(last().areaPOIPosition[1] == "<restricted>")
C_AreaPoiInfo.GetAreaPOIInfo = function() return secret end
command("sample"); assert(last().areaPOIPosition[1] == "<restricted>")
C_AreaPoiInfo.GetAreaPOIInfo = function() return { position = { x = secret, y = .1 } } end
command("sample"); assert(last().areaPOIPosition[1] == "<restricted>" and last().areaPOIPosition[2] == .1)
C_AreaPoiInfo.GetAreaPOIInfo = function() return nil end
command("sample"); assert(last().areaPOIPosition[1] == "<nil>")
C_AreaPoiInfo.GetAreaPOIInfo = function() error("not available") end
command("sample"); assert(last().areaPOIPosition.status == "error")
command("clear") -- Leave room for the existing timing/count assertions below.

event("SUPER_TRACKING_CHANGED")
command("stop"); before = count(); tick(1)
assert(count() == before and frame.scripts.OnUpdate == nil)
command("start"); before = count(); tick(.3)
assert(count() == before) -- The previous session's pending capture was discarded.
event("SUPER_TRACKING_PATH_UPDATED")
command("start"); before = count(); tick(.3); assert(count() == before)
event("SUPER_TRACKING_CHANGED")
combat = true; before = count(); local printed = #output
tick(.25); event("SUPER_TRACKING_PATH_UPDATED"); command("dump"); tick(2)
assert(count() == before and #output == printed)
combat = false
tick(.3); assert(count() == before) -- Combat-suppressed follow-ups do not leak later.
tick(2); assert(last().reason == "poll")
for i = 1, 45 do event("SUPER_TRACKING_CHANGED"); tick(.25) end
assert(count() == 40)
command("stop"); command("clear"); assert(count() == 0)
io.write("WaypointProbe tests passed\n")
