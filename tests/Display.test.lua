-- UI contract checks with owned-frame mocks; this does not render the WoW UI.
local A = {}
local secret = {}
function issecretvalue(v) return rawequal(v, secret) end
local combat = false
function InCombatLockdown() return combat end
local now = 10
function GetTime() return now end
STANDARD_TEXT_FONT = "fallback-font"
SlashCmdList = {}
local created = {}
local F = {}
F.__index = F
local function object(kind, parent)
    local obj = setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, fonts = {}, textures = {} }, F)
    created[#created + 1] = obj
    return obj
end
UIParent = object("UIParent")
UIParent.cx, UIParent.cy = 960, 540
function CreateFrame(kind, name, parent, template)
    assert(name == nil) -- All rendering frames are addon-owned and unnamed.
    local f = object(kind, parent); f.template = template; return f
end
function F:SetScript(k, fn) self.scripts[k] = fn end
function F:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function F:UnregisterAllEvents() self.events = {} end
function F:SetFrameStrata(v) self.strata = v end
function F:SetClampedToScreen(v) self.clamped = v end
function F:SetMovable(v) self.movable = v end
function F:RegisterForDrag(v) self.dragButton = v end
function F:SetAllPoints() self.allPoints = true end
function F:SetBackdrop(v) self.backdrop = v end
function F:SetBackdropColor(...) self.bg = {...} end
function F:SetBackdropBorderColor(...) self.border = {...} end
function F:Hide()
    if self.shown then self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
end
function F:Show() self.shown = true end
function F:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function F:SetShown(v) if v then self:Show() else self:Hide() end end
function F:SetSize(w,h) self.w,self.h = w,h end
function F:SetPoint(...) self.point = {...} end
function F:ClearAllPoints() self.point = nil end
function F:GetFrameLevel() return self.level or 0 end
function F:SetFrameLevel(v) self.level = v end
function F:CreateTexture()
    local t = object("Texture", self); self.textures[#self.textures + 1] = t; return t
end
function F:CreateFontString()
    local fs = object("FontString", self); self.fonts[#self.fonts + 1] = fs; return fs
end
function F:SetFont(...) self.font = {...} end
function F:SetJustifyH(v) self.justify = v end
function F:SetTextColor(...) self.color = {...} end
function F:SetVertexColor(...) self.color = {...} end
function F:SetTexture(v) self.texture = v end
function F:SetScale(v) self.scale = v end
function F:SetAlpha(v) self.alpha = v end
function F:EnableMouse(v) self.mouse = v end
function F:StartMoving() self.moving = true end
function F:StopMovingOrSizing() self.moving = false end
function F:GetCenter() return self.cx, self.cy end
function F:SetText(v) self.text = v end
function F:SetRotation(v) self.rotation = v end
local function load(name) assert(loadfile("AlmightreeWaypoint/" .. name .. ".lua"))("AlmightreeWaypoint", A) end
load("Navigation"); load("Controller"); load("Display"); load("Options")
local db = A.Settings({ scale = secret, opacity = math.huge, x = 0/0 })
assert(db.scale == 1 and db.opacity == 1 and db.x == 0)
local V = A.NewDisplay(db)
assert(not V.frame.shown and not V.frame.mouse and V.frame.clamped)
local arrow, destination, distance, instruction
for _, f in ipairs(created) do
    if f.kind == "Texture" then arrow = f end
    if f.kind == "FontString" then
        if not destination then destination = f elseif not distance then distance = f else instruction = f end
    end
end
V:Render({ destination = "Quest |link", instruction = "Take |portal", rotation = -.5, distance = 25 })
assert(V.frame.shown and arrow.shown and arrow.rotation == -.5)
assert(destination.text == "Quest ||link" and instruction.text == "Take ||portal")
assert(distance.text == "Straight-line: ~25 yd")
local visible, why, panel = V:GetArrowState()
assert(visible and why == "visible" and panel)
assert(V:GetUpdatedAt() == 10)
UIParent:Hide()
visible, why, panel = V:GetArrowState()
assert(not visible and why == "texture_or_parent_hidden" and not panel)
UIParent:Show()
V:Render({ destination = "Quest", instruction = "Take portal" })
assert(not arrow.shown and instruction.text == "Take portal" and distance.text == "Direction unavailable")
visible, why, panel = V:GetArrowState()
assert(not visible and why == "bearing_unavailable" and panel)
V:Render({ destination = "Quest", hideReason = "player_position_missing", key = "quest:88994", source = "objective" })
visible, why, panel = V:GetArrowState()
assert(not visible and why == "player_position_missing" and panel)
local key, source = V:GetTarget(); assert(key == "quest:88994" and source == "objective")
now = 11
V:Render(nil, "disabled")
visible, why, panel = V:GetArrowState(); assert(not visible and why == "disabled" and not panel)
assert(V:GetUpdatedAt() == 11 and V:GetTarget() == nil)
V:Render(nil)
assert(not V.frame.shown and not arrow.shown and destination.text == "" and instruction.text == "" and distance.text == "")
db.locked = false; V:SetLocked(false); V:Render({ preview = true })
V.frame.scripts.OnDragStart(); assert(V.frame.moving and V.frame.mouse)
V.frame.cx, V.frame.cy = 1060, 740
V.frame.scripts.OnDragStop(); assert(db.x == 100 and db.y == 200 and not V.frame.moving)
combat = true; V.frame.scripts.OnDragStart(); assert(not V.frame.moving); combat = false
V:ResetPosition(); assert(db.x == 0 and db.y == 180)

local skinEnabled = true
local S = {
    IsEnabled = function() return skinEnabled end,
    GetFont = function() return "eui-font", "OUTLINE" end,
    GetAccentColor = function() return .1, .2, .3 end,
    Shell = function() error("Navigation overlay must stay transparent") end,
    Font = function(fs) assert(fs.kind == "FontString") end,
}
local looks
S.OnLooksChanged = function(fn) looks = fn end
local spec, registeredSkin
local eui = {
    RegisterSkin = function(id, callback) assert(id == "AlmightreeWaypoint"); registeredSkin = true; callback(S) end,
    RegisterPlugin = function(id, value) assert(id == "AlmightreeWaypoint"); spec = value end,
}
V:RegisterSkin(eui)
assert(registeredSkin and destination.font[1] == "eui-font" and arrow.color[1] == .1)
for _, f in ipairs(created) do assert(not f.backdrop) end
-- EUI primitives resolve the style; our frames/position/settings survive appearance changes.
looks(); assert(db.y == 180)
skinEnabled = false; looks()
assert(destination.font[1] == "fallback-font")
skinEnabled = true; looks(); assert(destination.font[1] == "eui-font")

local calls = {}
local C = { preview = false }
function C:SetEnabled(v) calls.enabled = v end
function C:SetPreview(v) calls.preview = v end
function C:SetLocked(v) calls.locked = v end
A.RegisterOptions(eui, C, V, db)
assert(spec.modules[1].key == "General")
local widgets = {}
eui.Widgets = {}
for _, method in ipairs({ "SectionHeader", "Toggle", "Button", "Slider" }) do
    eui.Widgets[method] = function(_, parent, text, y, ...)
        widgets[text] = { method = method, args = {...} }; return {}, 30
    end
end
local before = #created
assert(spec.modules[1].buildPage("Display", {}, -10) > 0)
assert(#created == before and next(calls) == nil) -- Search prebuild has no live side effects.
widgets["Enable navigation arrow"].args[2](false); assert(calls.enabled == false)
widgets["Unlock for dragging"].args[2](true); assert(calls.locked == false)
widgets["Preview"].args[2](true); assert(calls.preview == true)
widgets["Scale"].args[5](1.5); assert(db.scale == 1.5 and V.frame.w == 450)
A.RegisterCommands(eui, C, V)
SlashCmdList.ALMIGHTREEWAYPOINT("disable"); assert(calls.enabled == false)
SlashCmdList.ALMIGHTREEWAYPOINT("enable"); assert(calls.enabled == true)
combat = true; calls.enabled = true
SlashCmdList.ALMIGHTREEWAYPOINT("disable"); assert(calls.enabled == false)
combat = false
-- Exercise the TOC entrypoint with EUI absent; it should initialize and stop at idle.
load("Main")
local loader = created[#created]
assert(loader.events.PLAYER_LOGIN)
loader.scripts.OnEvent()
local driver = created[#created]
assert(AlmightreeWaypointDB.enabled and driver.scripts.OnUpdate)
driver.scripts.OnUpdate(driver, .5)
assert(driver.scripts.OnUpdate == nil) -- No selected target in this mock runtime.
visible, why, panel = AlmightreeWaypointDiagnostics.GetArrowState()
assert(not visible and why == "tracking_missing" and not panel)
assert(AlmightreeWaypointDiagnostics.GetUpdatedAt() == 11 and driver.scripts.OnUpdate == nil)
io.write("Display and public EUI contract tests passed\n")
