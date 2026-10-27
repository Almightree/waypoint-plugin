-- Run from the repository root: lua tests/Navigation.test.lua
local A = {}
local function load(name) assert(loadfile("AlmightreeWaypoint/" .. name .. ".lua"))("AlmightreeWaypoint", A) end
local secret = {}
function issecretvalue(v) return rawequal(v, secret) end
load("Navigation")
load("Controller")
load("Options")
local N = A.Navigation
local function near(a, b) assert(a and math.abs(a - b) < 0.000001, tostring(a) .. " ~= " .. tostring(b)) end
local function direction(x, y, facing, width, height)
    return N.Direction(1, .5, .5, { mapID = 1, x = x, y = y }, width or 100, height or 100, facing or 0)
end
near(direction(.5, .4), 0) -- north
near(direction(.6, .5), -math.pi / 2) -- east/right
near(direction(.4, .5), math.pi / 2) -- west/left
near(direction(.5, .6), -math.pi) -- behind
near(direction(.4, .5, math.pi / 2), 0) -- facing west
near(direction(.6, .5, 2 * math.pi), -math.pi / 2)
local rotation, yards = direction(.6, .4, 0, 200, 100)
near(yards, math.sqrt(500)); near(rotation, -math.atan(2)) -- rectangular map
rotation, yards = direction(.5, .5)
assert(rotation == nil and yards == 0) -- Not arrival and no arbitrary bearing.
assert(N.Direction(1, .5, .5, { mapID = 2, x = .6, y = .5 }, 100, 100, 0) == nil)
for _, bad in ipairs({ secret, "bad", -1, 0, math.huge, 0/0 }) do
    assert(N.Direction(1, .5, .5, { mapID = 1, x = .6, y = .5 }, bad, 100, 0) == nil)
end
assert(direction(1.1, .5) == nil)
assert(direction(secret, .5) == nil)
assert(direction(.6, .5, secret) == nil)
assert(N.Read(nil, "Missing").status == "missing")
assert(N.Read({ Fail = function() error("failed") end }, "Fail").status == "error")
assert(N.Read({ Hidden = function() return secret end }, "Hidden").status == "restricted")
local _, _, why = N.Direction(1, .5, .5, { mapID = 2, x = .6, y = .5 }, 100, 100, 0)
assert(why == "map_mismatch")
_, _, why = direction(.5, .5); assert(why == "coincident_coordinates")

local state = { tracking = true, kind = 0, questID = 88994, map = 2413, combat = false,
    pin = { uiMapID = 2413, position = { x = .6, y = .5 } }, facing = 0 }
local readCount, poiCount, nativeDistanceCalls = 0, 0, 0
local api = {
    Enum = { SuperTrackingType = { Quest = 0, UserWaypoint = 1, MapPin = 6 }, SuperTrackingMapPinType = { AreaPOI = 0 } },
    InCombatLockdown = function() return state.combat end,
    GetPlayerFacing = function() return state.facing end,
    C_SuperTrack = {
        IsSuperTrackingAnything = function() readCount = readCount + 1; return state.tracking end,
        GetHighestPrioritySuperTrackingType = function() return state.kind end,
        IsSuperTrackingQuest = function() return state.questTracked ~= false end,
        IsSuperTrackingUserWaypoint = function() return state.pinTracked ~= false end,
        GetSuperTrackedQuestID = function() return state.questID end,
        GetSuperTrackedItemName = function() return "Target " .. tostring(state.questID) end,
        IsSuperTrackingMapPin = function() return true end,
        GetSuperTrackedMapPin = function() return 0, 123 end,
    },
    C_Map = {
        GetBestMapForUnit = function(unit) assert(unit == "player"); return state.map end,
        GetUserWaypoint = function() return state.pin end,
        GetPlayerMapPosition = function(map, unit) assert(map == state.map and unit == "player"); return { x = .5, y = .5 } end,
        GetMapWorldSize = function(map) assert(map == state.map); return 1000, 500 end,
    },
    C_Navigation = {
        GetNextWaypointForMap = function(map) assert(map == state.map); return state.navX, state.navY, state.navText end,
        GetDistance = function() nativeDistanceCalls = nativeDistanceCalls + 1; return 99999 end,
    },
    C_QuestLog = {
        GetNextWaypointForMap = function(id, map) assert(id == state.questID and map == state.map); return state.stepX, state.stepY end,
        GetNextWaypoint = function(id) assert(id == state.questID); return state.stepMap, state.globalX, state.globalY end,
        GetNextWaypointText = function(id) assert(id == state.questID); return state.text end,
        GetQuestsOnMap = function(map)
            poiCount = poiCount + 1
            return {
                { questID = 777, mapID = map, x = .01, y = .01 },
                { questID = 88994, mapID = map, x = .5418, y = .5313 },
                { questID = 88996, mapID = map, x = .6465, y = .3863 },
            }
        end,
    },
    C_AreaPoiInfo = { GetAreaPOIInfo = function(map, id) assert(map == state.map and id == 123); return { position = { x = .7, y = .4 } } end },
}
local function capture() local t = N.Identity(api); assert(t); return N.Capture(api, t) end
assert(N.Identity(api).key == "quest:88994")
local model = capture()
assert(model.source == "objective" and model.rotation and model.distance > 0)
local firstDistance = model.distance
state.questID = 88996
model = capture(); assert(model.source == "objective" and model.distance ~= firstDistance)
state.questID = 88994
state.map, state.stepX, state.stepY = 2393, .3, .2
state.navX, state.navY = .3, .2
state.text = "Take the portal from Silvermoon to Harandar."
local beforePOI = poiCount
model = capture()
assert(model.source == "travel" and model.instruction == state.text and model.rotation)
assert(poiCount == beforePOI) -- Never bypass a portal with an objective coordinate.
state.stepX, state.stepY, state.navX, state.navY = nil, nil, nil, nil
model = capture(); assert(not model.rotation and model.instruction == state.text and poiCount == beforePOI)
assert(model.hideReason == "travel_instruction_without_coordinates")
state.map = secret
model = capture(); assert(not model.rotation and model.instruction == state.text)
assert(model.hideReason == "player_map_restricted")
state.map = 2393
state.text, state.stepMap, state.globalX, state.globalY = nil, 2393, .3, .2
state.map = 2413
model = capture(); assert(not model.rotation and poiCount == beforePOI) -- Known step on another map.
assert(model.hideReason == "travel_step_other_map")
state.stepX, state.stepY = .3, .2
assert(capture().source == "travel") -- A quest-specific current-map step remains usable.
state.stepX, state.stepY = nil, nil
state.stepMap, state.globalX, state.globalY = nil, nil, nil
model = capture(); assert(model.source == "objective" and model.rotation) -- After portal.
state.navX, state.navY, state.navText = .2, .3, "Travel step"
model = capture(); assert(model.source == "travel" and model.instruction == "Travel step")
state.navX, state.navY, state.navText = secret, secret, "Keep instruction"
model = capture(); assert(not model.rotation and model.instruction == "Keep instruction")
assert(model.hideReason == "native_travel_restricted")
state.navX, state.navY, state.navText = nil, nil, nil
local original = api.C_QuestLog.GetNextWaypoint
api.C_QuestLog.GetNextWaypoint = nil
model = capture(); assert(not model.rotation and model.source == nil) -- Unknown routing blocks fallback.
assert(model.hideReason == "quest_travel_missing")
api.C_QuestLog.GetNextWaypoint = function() error("unavailable") end
assert(not capture().rotation)
api.C_QuestLog.GetNextWaypoint = original
local originalPOI = api.C_QuestLog.GetQuestsOnMap
api.C_QuestLog.GetQuestsOnMap = function() return { secret, { questID = secret }, { questID = 88994, mapID = 9, x = .1, y = .2 } } end
assert(not capture().rotation)
api.C_QuestLog.GetQuestsOnMap = function() return secret end
assert(not capture().rotation)
api.C_QuestLog.GetQuestsOnMap = originalPOI

state.kind = 1 -- The active type wins over a retained quest ID and true quest flag.
assert(N.Identity(api).kind == "pin")
model = capture(); assert(model.source == "pin" and model.rotation)
state.pin.uiMapID = 999
assert(not capture().rotation) -- No subtraction across maps.
assert(capture().hideReason == "map_mismatch")
state.pin.uiMapID = 2413
local originalPlayer = api.C_Map.GetPlayerMapPosition
api.C_Map.GetPlayerMapPosition = function() return secret end
assert(not capture().rotation)
assert(capture().hideReason == "player_position_restricted")
api.C_Map.GetPlayerMapPosition = nil
assert(not capture().rotation)
assert(capture().hideReason == "player_position_missing")
api.C_Map.GetPlayerMapPosition = originalPlayer
state.pinTracked = false; assert(N.Identity(api) == nil); state.pinTracked = true
state.pin.position = secret; assert(N.Identity(api) == nil); state.pin.position = { x = .6, y = .5 }
state.kind = 6; assert(N.Identity(api).kind == "poi"); assert(capture().rotation)
state.kind = 99; assert(N.Identity(api) == nil)
state.kind = secret; assert(N.Identity(api) == nil)
state.kind = 0; state.questID = secret; assert(N.Identity(api) == nil); state.questID = 88994
state.tracking = false; assert(N.Identity(api) == nil); state.tracking = true
state.tracking = false; local _, identityReason = N.Identity(api); assert(identityReason == "no_tracking"); state.tracking = true
assert(nativeDistanceCalls == 0)

-- Lifecycle: pending work contains no cached target/model and cannot revive obsolete data.
local driver = { scripts = {}, events = {} }
function driver:SetScript(k, fn) self.scripts[k] = fn end
function driver:RegisterEvent(k) self.events[k] = true end
function driver:UnregisterAllEvents() self.events = {} end
local view = {}
function view:Render(m, reason) self.model, self.reason = m, reason end
function view:SetLocked(locked) self.locked = locked end
local db = A.Settings({})
local C = A.NewController(api, driver, view, db)
local function tick(dt) if driver.scripts.OnUpdate then driver.scripts.OnUpdate(driver, dt or .5) end end
local function event(name) driver.scripts.OnEvent(driver, name) end
local function settle() tick(); tick() end
C:SetEnabled(true); assert(driver.scripts.OnUpdate and view.reason == "refresh_pending"); settle()
assert(view.model and view.model.key == "quest:88994")
state.questID = 88996; event("SUPER_TRACKING_CHANGED")
assert(view.model == nil and C.model == nil)
tick(.1); assert(view.model == nil)
settle(); assert(view.model.key == "quest:88996")
state.questID = 88994; tick() -- Even a missed event invalidates when identity changes.
assert(view.model == nil); settle(); assert(view.model.key == "quest:88994")
state.tracking = false; event("SUPER_TRACKING_CHANGED")
assert(view.model == nil); settle(); assert(driver.scripts.OnUpdate == nil)
assert(view.reason == "no_tracking")
state.tracking = true; event("SUPER_TRACKING_CHANGED"); settle(); assert(view.model)
event("SUPER_TRACKING_PATH_UPDATED"); assert(view.model == nil)
C:SetEnabled(false); local stoppedReads = readCount
tick(2); event("SUPER_TRACKING_CHANGED")
assert(readCount == stoppedReads and view.model == nil and next(driver.events) == nil)
assert(view.reason == "disabled")
C:SetEnabled(true); settle(); assert(view.model)
state.combat = true; event("PLAYER_REGEN_DISABLED"); stoppedReads = readCount
tick(2); assert(readCount == stoppedReads and view.model == nil and driver.scripts.OnUpdate == nil)
assert(view.reason == "combat_suppressed")
state.combat = false; event("PLAYER_REGEN_ENABLED"); settle(); assert(view.model)
event("PLAYER_LEAVING_WORLD"); stoppedReads = readCount; tick(2)
assert(readCount == stoppedReads and view.model == nil)
assert(view.reason == "loading_screen")
event("PLAYER_ENTERING_WORLD"); settle(); assert(view.model)
C:SetPreview(true); assert(view.model.preview and driver.scripts.OnUpdate == nil)
C:SetPreview(false); settle(); assert(view.model.key == "quest:88994")
C:SetLocked(false); assert(view.model.preview and driver.scripts.OnUpdate == nil)
C:SetLocked(true); settle(); assert(view.model.key == "quest:88994")
-- Disable reentrantly while a getter is running: its result must never be published.
api.C_QuestLog.GetQuestsOnMap = function() C:SetEnabled(false); return originalPOI(state.map) end
tick(); assert(not C.enabled and not view.model and driver.scripts.OnUpdate == nil)
assert(nativeDistanceCalls == 0)
io.write("Navigation and controller tests passed\n")
