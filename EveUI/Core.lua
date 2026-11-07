-- EveUI core: palette, pixel-perfect root frame, drawing helpers, secret-value
-- helpers, saved settings, movable frames, Blizzard frame hiding, slash commands.
local ADDON, ns = ...
_G.EveUI = ns

local C = {
  bg       = { 0.02, 0.03, 0.04, 0.78 },
  panel    = { 0.03, 0.04, 0.05, 0.92 },
  header   = { 0.08, 0.10, 0.12, 0.95 },
  border   = { 0.30, 0.38, 0.42, 0.75 },
  line     = { 0.30, 0.38, 0.42, 0.35 },
  accent   = { 0.36, 0.78, 0.86, 1 },
  text     = { 0.86, 0.89, 0.91, 1 },
  title    = { 0.93, 0.95, 0.96, 1 },
  dim      = { 0.50, 0.56, 0.59, 1 },
  hostile  = { 0.92, 0.27, 0.22, 1 },
  neutral  = { 0.96, 0.72, 0.22, 1 },
  friendly = { 0.33, 0.63, 0.98, 1 },
  heal     = { 0.35, 0.90, 0.45, 1 },
  shield   = { 0.50, 0.76, 0.96, 1 },
  hull     = { 0.88, 0.91, 0.92, 1 },
  cap      = { 0.97, 0.86, 0.52, 1 },
  health   = { 0.90, 0.14, 0.12, 1 },
  mana     = { 0.18, 0.46, 1.00, 1 },
  cast     = { 0.96, 0.72, 0.22, 1 },
  off      = { 1, 1, 1, 0.09 },
  black    = { 0, 0, 0, 1 },
}
ns.C = C
-- One face for all game text. The client reads these globals for world text
-- (names above heads, damage numbers, nameplates) when it loads, so they are
-- set here in the main chunk. Font objects are swapped in RestyleFonts.
--
-- The face is Barlow Semi Condensed Medium (SIL OFL, media/OFL.txt): narrow,
-- clean and technical, close to EVE's own UI type. A font file added while
-- the client is running may not be found until the next client start, so it
-- is test-loaded first and Arial Narrow is the fallback.
ns.FONT_FALLBACK = "Fonts\\ARIALN.TTF"
ns.FONT_EVE = "Interface\\AddOns\\" .. ADDON .. "\\media\\BarlowSemiCondensed-Medium.ttf"
ns.FONT_EVE_BOLD = "Interface\\AddOns\\" .. ADDON .. "\\media\\BarlowSemiCondensed-SemiBold.ttf"
do
  local probe = CreateFont("EveUIFontProbe")
  local function Loads(path)
    local ok, res = pcall(probe.SetFont, probe, path, 12, "")
    if not ok or res == false then return false end
    local file = probe:GetFont()
    return file ~= nil and file:lower():find("barlow", 1, true) ~= nil
  end
  ns.fontLoaded = Loads(ns.FONT_EVE)
  ns.FONT = ns.fontLoaded and ns.FONT_EVE or ns.FONT_FALLBACK
  ns.FONT_BOLD = (ns.fontLoaded and Loads(ns.FONT_EVE_BOLD)) and ns.FONT_EVE_BOLD or ns.FONT
end
DAMAGE_TEXT_FONT = ns.FONT
UNIT_NAME_FONT = ns.FONT
NAMEPLATE_FONT = ns.FONT
NAMEPLATE_SPELLCAST_FONT = ns.FONT
STANDARD_TEXT_FONT = ns.FONT
ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
ns.BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local defaults = { pos = {}, scale = 1, opacity = 1, hideBlizzard = true, neocom = true, off = {} }

ns.modules, ns.movers, ns.layoutHooks = {}, {}, {}
-- key: optional name for the settings window's module toggles
-- (EveUIDB.off[key] = true skips the module at load).
function ns.RegisterModule(fn, key) ns.modules[#ns.modules + 1] = { fn = fn, key = key } end
function ns.ModuleOn(key) return not (EveUIDB and EveUIDB.off and EveUIDB.off[key]) end
function ns.OnLayout(fn) ns.layoutHooks[#ns.layoutHooks + 1] = fn end

function ns.Print(msg) print("|cff5bc7dbEveUI|r " .. msg) end

-- Secret values ----------------------------------------------------------------
-- WoW Forever hides combat numbers from addon code ("secret values"). Widgets
-- can still display them; addon code must not do maths or comparisons on them.

ns.issecret = issecretvalue or function() return false end
function ns.Plain(v)
  if ns.issecret(v) then return nil end
  return v
end

local function after(ok, ...)
  if ok then return ... end
end
function ns.Call(fn, ...)
  if not fn then return nil end
  return after(pcall(fn, ...))
end

function ns.HealthPct(unit)
  if UnitHealthPercent then return UnitHealthPercent(unit) end
  return UnitHealth(unit) / math.max(UnitHealthMax(unit), 1)
end

function ns.PowerPct(unit)
  if UnitPowerPercent then return UnitPowerPercent(unit) end
  local m = UnitPowerMax(unit)
  return m > 0 and UnitPower(unit) / m or 0
end

-- Names ------------------------------------------------------------------------
-- WoW Forever characters have a first and a last name: UnitName returns them
-- as two values (the second used to be the realm). Shown as "First Last" like
-- Blizzard's own frames; your own surname follows the game's setting. Names
-- can be secret for units outside your group, so they go through
-- SetFormattedText, which can display secrets, instead of being joined here.
local function ShowSurname(unit)
  if unit ~= "player" and ns.Plain(UnitIsUnit(unit, "player")) ~= true then return true end
  if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() and C_PlayerInfo
    and C_PlayerInfo.ShouldDisplaySurname then
    return C_PlayerInfo.ShouldDisplaySurname() ~= false
  end
  return true
end

function ns.SetUnitName(fs, unit)
  local first, last = UnitName(unit)
  if ns.issecret(last) then
    if ShowSurname(unit) and pcall(fs.SetFormattedText, fs, "%s %s", first, last) then return end
  elseif last and last ~= "" and ShowSurname(unit) then
    if pcall(fs.SetFormattedText, fs, "%s %s", first, last) then return end
  end
  fs:SetText(first)
end

-- Plain "First Last" (nil when secret), for code that needs a string.
function ns.UnitFullName(unit)
  local first, last = UnitName(unit)
  first, last = ns.Plain(first), ns.Plain(last)
  if not first then return nil end
  if last and last ~= "" and ShowSurname(unit) then return first .. " " .. last end
  return first
end

-- 0-100 percent for StatusBars, secret or plain (same call as the % text).
function ns.HealthPct100(unit)
  if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
    local ok, p = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
    if ok and p ~= nil then return p end
  end
  local h, m = ns.Plain(UnitHealth(unit)), ns.Plain(UnitHealthMax(unit))
  return (h and m and m > 0) and h / m * 100 or 0
end

function ns.PowerPct100(unit)
  if ns.PowerCurve and CurveConstants and CurveConstants.ScaleTo100 then
    local ok, p = pcall(ns.PowerCurve, unit, CurveConstants.ScaleTo100)
    if ok and p ~= nil then return p end
  end
  local c, m = ns.Plain(UnitPower(unit)), ns.Plain(UnitPowerMax(unit))
  return (c and m and m > 0) and c / m * 100 or 0
end

-- "87%" text for any unit, secret or not.
function ns.SetHealthText(fs, unit, fmt)
  fmt = fmt or "%.0f%%"
  if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
    if pcall(fs.SetFormattedText, fs, fmt, UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)) then return end
  end
  local h, m = ns.Plain(UnitHealth(unit)), ns.Plain(UnitHealthMax(unit))
  if h and m and m > 0 then fs:SetFormattedText(fmt, h / m * 100) else fs:SetText("") end
end

-- Errors -------------------------------------------------------------------------
-- Wrapped functions print each distinct error once in chat and keep it in
-- EveUIDB.errors (written to SavedVariables on /reload or logout).

local seen = {}
function ns.Safe(name, fn)
  return function(...)
    local ok, err = xpcall(fn, function(e)
      return tostring(e) .. "\n" .. (debugstack and debugstack(2, 5, 0) or "")
    end, ...)
    if not ok and not seen[name .. err] then
      seen[name .. err] = true
      ns.Print("|cffff5544error in " .. name .. ":|r " .. err:match("^[^\n]*"))
      if EveUIDB then
        EveUIDB.errors = EveUIDB.errors or {}
        if #EveUIDB.errors < 40 then table.insert(EveUIDB.errors, name .. ": " .. err) end
      end
    end
  end
end

function ns.Every(seconds, name, fn)
  local safe = ns.Safe(name, fn)
  safe()
  C_Timer.NewTicker(seconds, safe)
end

-- Pixel-perfect root -----------------------------------------------------------
-- Everything EveUI draws lives under EveUIRoot, scaled so 1 unit = 1 screen
-- pixel. Blizzard frames we restyle use ns.Px(frame) to get their pixel size.

local root = CreateFrame("Frame", "EveUIRoot", UIParent)
root:SetAllPoints(UIParent)
ns.root = root
ns.pxScale = 768 / 1080

function ns.UpdateScale()
  if InCombatLockdown() then ns.pendingScale = true return end
  local _, h = GetPhysicalScreenSize()
  ns.pxScale = 768 / (h and h > 0 and h or 1080)
  root:SetScale(ns.pxScale / UIParent:GetEffectiveScale() * ((EveUIDB and EveUIDB.scale) or 1))
end

-- Size of one physical pixel in a frame's own units.
function ns.Px(frame)
  return ns.pxScale / (frame or UIParent):GetEffectiveScale()
end

-- Drawing helpers --------------------------------------------------------------

function ns.SetFont(fs, size, flags, frame)
  if not fs or not fs.SetFont then return end
  local px = frame and ns.Px(frame) or 1
  fs:SetFont(ns.FONT, size * px, flags or "")
  if not flags or flags == "" then
    fs:SetShadowOffset(px, -px)
    fs:SetShadowColor(0, 0, 0, 0.95)
  else
    fs:SetShadowOffset(0, 0)
  end
end

function ns.Text(parent, size, color, justify, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  ns.SetFont(fs, size, flags)
  fs:SetTextColor(unpack(color or C.text))
  fs:SetJustifyH(justify or "CENTER")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

-- Panel opacity (settings window): every box background is scaled by it.
ns.boxBgs = setmetatable({}, { __mode = "k" })
function ns.Opacity() return (EveUIDB and EveUIDB.opacity) or 1 end
function ns.ApplyOpacity()
  local o = ns.Opacity()
  for tex, c in pairs(ns.boxBgs) do tex:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * o) end
end

-- A filled box with a 1 px border, made of the frame's own textures so it sits
-- under the frame's text without frame-level games. px = border thickness.
function ns.Box(f, bg, border, px)
  px = px or 1
  local t = f.eveBox
  if not t then
    t = {}
    t.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
      t[side] = f:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    f.eveBox = t
  end
  t.bg:ClearAllPoints()
  t.bg:SetAllPoints()
  if bg == false then
    t.bg:Hide(); ns.boxBgs[t.bg] = nil
  else
    local c = bg or C.bg
    ns.boxBgs[t.bg] = c
    t.bg:Show(); t.bg:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * ns.Opacity())
  end
  local b = border or C.border
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do
    local s = t[side]
    s:ClearAllPoints()
    if border == false then s:Hide() else s:Show(); s:SetColorTexture(unpack(b)) end
  end
  t.top:SetPoint("TOPLEFT"); t.top:SetPoint("TOPRIGHT"); t.top:SetHeight(px)
  t.bottom:SetPoint("BOTTOMLEFT"); t.bottom:SetPoint("BOTTOMRIGHT"); t.bottom:SetHeight(px)
  t.left:SetPoint("TOPLEFT", 0, -px); t.left:SetPoint("BOTTOMLEFT", 0, px); t.left:SetWidth(px)
  t.right:SetPoint("TOPRIGHT", 0, -px); t.right:SetPoint("BOTTOMRIGHT", 0, px); t.right:SetWidth(px)
  return t
end

function ns.SetBoxBorder(f, color)
  local t = f.eveBox
  if not t then return end
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do t[side]:SetColorTexture(unpack(color)) end
end

-- EVE window: dark body, 1 px border, title bar with an accent mark.
ns.HEADER = 22
function ns.CreatePanel(name, parent, title, w, h, template)
  local f = CreateFrame("Frame", name, parent or root, template)
  f:SetSize(w, h)
  ns.Box(f, C.panel)
  if title then
    local hb = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    hb:SetColorTexture(unpack(C.header))
    hb:SetPoint("TOPLEFT", 1, -1)
    hb:SetPoint("TOPRIGHT", -1, -1)
    hb:SetHeight(ns.HEADER - 1)
    local mark = f:CreateTexture(nil, "ARTWORK")
    mark:SetColorTexture(unpack(C.accent))
    mark:SetPoint("TOPLEFT", 1, -1)
    mark:SetSize(2, ns.HEADER - 1)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(C.line))
    line:SetPoint("TOPLEFT", 1, -ns.HEADER)
    line:SetPoint("TOPRIGHT", -1, -ns.HEADER)
    line:SetHeight(1)
    f.title = ns.Text(f, 12, C.title, "LEFT")
    f.title:SetFont(ns.FONT_BOLD, 12, "")
    f.title:SetPoint("TOPLEFT", 10, -5)
    f.title:SetText(title:upper())
  end
  return f
end

-- 2.5D shading ------------------------------------------------------------------
-- WoW has no lighting for UI art, so depth is faked: vertex gradients (light
-- from above), a soft drop shadow, a bevel rim and a glassy highlight.

local function Clamp(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function Mul(c, k, a) return Clamp(c[1] * k), Clamp(c[2] * k), Clamp(c[3] * k), a or c[4] or 1 end
ns.Mul = Mul

-- Vertical gradient from `bottom` to `top` (each {r, g, b, a}). Falls back to
-- the old 8-number form, then to a flat colour.
function ns.Gradient(tex, bottom, top, orient)
  orient = orient or "VERTICAL"
  if CreateColor and pcall(tex.SetGradient, tex, orient, CreateColor(unpack(bottom)), CreateColor(unpack(top))) then
    return
  end
  if pcall(tex.SetGradientAlpha, tex, orient, bottom[1], bottom[2], bottom[3], bottom[4] or 1,
    top[1], top[2], top[3], top[4] or 1) then return end
  tex:SetVertexColor(top[1], top[2], top[3], top[4] or 1)
end

-- A colour lit from above: dark at the bottom, bright at the top.
function ns.Lit(tex, c, low, high, orient)
  ns.Gradient(tex, { Mul(c, low or 0.45) }, { Mul(c, high or 1.2) }, orient)
end

-- Make a StatusBar look like a lit glass tube: shaded fill, gloss on the top
-- half, a dark lip underneath and a drop shadow. Use ns.SetBarColor to colour it.
function ns.Bar3D(bar)
  local h = bar:GetHeight()
  local sh = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
  sh:SetTexture(ns.WHITE)
  sh:SetPoint("TOPLEFT", 1, -2)
  sh:SetPoint("BOTTOMRIGHT", 2, -2)
  sh:SetVertexColor(0, 0, 0, 0.6)
  local gloss = bar:CreateTexture(nil, "OVERLAY", nil, 1)
  gloss:SetTexture(ns.WHITE)
  gloss:SetPoint("TOPLEFT"); gloss:SetPoint("TOPRIGHT")
  gloss:SetHeight(math.max(h * 0.5, 1))
  gloss:SetBlendMode("ADD")
  ns.Gradient(gloss, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.32 })
  local lip = bar:CreateTexture(nil, "OVERLAY", nil, 2)
  lip:SetTexture(ns.WHITE)
  lip:SetPoint("BOTTOMLEFT"); lip:SetPoint("BOTTOMRIGHT")
  lip:SetHeight(1)
  lip:SetVertexColor(0, 0, 0, 0.45)
  bar.eve3d = true
end

function ns.SetBarColor(bar, c)
  if bar.eveColor == c then return end
  bar.eveColor = c
  local t = bar:GetStatusBarTexture()
  if t then ns.Lit(t, c, 0.5, 1.15) else bar:SetStatusBarColor(c[1], c[2], c[3]) end
end

-- A raised glass orb: drop shadow, bevel rim (light below, dark above), a
-- body lit from above and a soft specular highlight near the top. `size` is
-- the body diameter; alpha scales the body darkness like ns.Disk's.
function ns.Orb(parent, size, alpha, layer, sub, tint)
  layer, sub, alpha = layer or "BACKGROUND", sub or 0, alpha or 0.6
  tint = tint or { 0.07, 0.10, 0.13 }
  local o = {}
  local function Circle(d, l, s)
    local t = parent:CreateTexture(nil, l or layer, nil, math.max(math.min(s, 7), -8))
    t:SetTexture(ns.CIRCLE)
    t:SetSize(d, d)
    return t
  end
  o.shadow = Circle(size + 10, nil, sub - 1)
  o.shadow:SetVertexColor(0, 0, 0, 0.45 * alpha + 0.15)
  o.rim = Circle(size + 4, nil, sub)
  ns.Gradient(o.rim, { 0.42, 0.52, 0.58, 0.9 * alpha + 0.1 }, { 0.02, 0.03, 0.04, 0.9 * alpha + 0.1 })
  o.body = Circle(size, nil, sub + 1)
  ns.Gradient(o.body, { 0, 0, 0, alpha }, { tint[1] * 2, tint[2] * 2, tint[3] * 2, alpha })
  o.spec = parent:CreateTexture(nil, layer, nil, math.min(sub + 2, 7))
  o.spec:SetTexture(ns.CIRCLE)
  o.spec:SetSize(size * 0.62, size * 0.34)
  o.spec:SetBlendMode("ADD")
  ns.Gradient(o.spec, { 1, 1, 1, 0 }, { 1, 1, 1, 0.10 + 0.08 * alpha })
  function o:SetPoint(point, rel, rp, x, y)
    rel = rel or parent; rp = rp or point; x = x or 0; y = y or 0
    self.shadow:SetPoint(point, rel, rp, x + 2, y - 4)
    self.rim:SetPoint(point, rel, rp, x, y)
    self.body:SetPoint(point, rel, rp, x, y)
    self.spec:SetPoint("TOP", self.body, "TOP", 0, -size * 0.05)
  end
  return o
end

-- Glass over a round portrait: a top highlight and a dark inner bottom edge.
function ns.Lens(parent, target)
  local w = target:GetWidth()
  local spec = parent:CreateTexture(nil, "OVERLAY", nil, 1)
  spec:SetTexture(ns.CIRCLE)
  spec:SetSize(w * 0.7, w * 0.4)
  spec:SetPoint("TOP", target, "TOP", 0, -w * 0.04)
  spec:SetBlendMode("ADD")
  ns.Gradient(spec, { 1, 1, 1, 0 }, { 1, 1, 1, 0.22 })
  local shade = parent:CreateTexture(nil, "OVERLAY", nil, 0)
  shade:SetTexture(ns.CIRCLE)
  shade:SetAllPoints(target)
  ns.Gradient(shade, { 0, 0, 0, 0.55 }, { 0, 0, 0, 0 })
  return spec, shade
end

function ns.Disk(parent, size, alpha, layer, sub)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  t:SetTexture(ns.CIRCLE)
  t:SetVertexColor(0, 0, 0, alpha or 0.6)
  t:SetSize(size, size)
  return t
end

-- Unit colours -------------------------------------------------------------------

function ns.ReactionColor(unit)
  local isPlayer = ns.Plain(UnitIsPlayer(unit))
  if isPlayer then
    if ns.Plain(UnitIsEnemy("player", unit)) then return C.hostile end
    return ns.Plain(UnitCanAttack("player", unit)) and C.neutral or C.friendly
  end
  local r = ns.Plain(UnitReaction(unit, "player"))
  if not r then return C.neutral end
  if r <= 3 then return C.hostile elseif r == 4 then return C.neutral end
  return C.friendly
end

function ns.ClassColor(unit)
  local _, class = UnitClass(unit)
  class = ns.Plain(class)
  local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
  if c then return { c.r, c.g, c.b, 1 } end
  return C.text
end

local powerCache = {}
function ns.PowerColor(unit)
  local idx, tok = UnitPowerType(unit)
  tok = ns.Plain(tok) or ns.Plain(idx) or "MANA"
  if tok == "MANA" or tok == 0 then return C.mana end
  if not powerCache[tok] then
    local c = PowerBarColor and PowerBarColor[tok]
    powerCache[tok] = c and { c.r, c.g, c.b, 1 } or C.cap
  end
  return powerCache[tok]
end

-- Rough range bracket from the fixed interact distances WoW exposes.
function ns.Range(unit)
  if ns.Plain(UnitIsUnit(unit, "player")) then return 0, "0 yd" end
  if InCombatLockdown() and ns.Plain(UnitCanAttack("player", unit)) ~= false then return 9, "-" end
  local near = ns.Plain(ns.Call(CheckInteractDistance, unit, 3))
  if near then return 1, "<10 yd" end
  local mid = ns.Plain(ns.Call(CheckInteractDistance, unit, 4))
  if mid then return 2, "<28 yd" end
  if near == false or mid == false then return 3, "28+ yd" end
  return 9, "-"
end

-- Movable frames ---------------------------------------------------------------
-- Every movable element registers here. Positions are saved per character in
-- EveUIDB.chars[<name-realm>].pos as { point, relPoint, x, y } against
-- UIParent; until moved, an element sits at its default anchor (which may be
-- another EveUI frame, e.g. the racks hang off the HUD). Unlocking shows a
-- labelled cyan outline on each one. Unlocking is refused in combat, and the
-- layout locks itself the moment combat starts (PLAYER_REGEN_DISABLED fires
-- before the lockdown), so no frame is ever moved from addon code in combat.

-- Per-character layout table (set up at PLAYER_LOGIN, before the modules).
function ns.Layout()
  if ns.layout then return ns.layout end
  EveUIDB.chars = EveUIDB.chars or {}
  local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
  local l = EveUIDB.chars[key]
  if not l then
    l = { pos = {} }
    -- Carry over positions saved before layouts were per character.
    for k, v in pairs(EveUIDB.pos or {}) do l.pos[k] = v end
    EveUIDB.chars[key] = l
  end
  l.pos = l.pos or {}
  ns.layout = l
  return l
end

local function SavePos(f)
  local p, _, rp, x, y = f:GetPoint()
  if not p then return end
  ns.Layout().pos[f.eveKey] = { p, rp or p, math.floor(x + 0.5), math.floor(y + 0.5) }
end
ns.SavePos = SavePos

function ns.ApplyPos(f)
  if f.eveApply then return f.eveApply(f) end
  local p = ns.Layout().pos[f.eveKey]
  f:ClearAllPoints()
  if p then
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    if f.eveDefaultFn then
      local dp, rel, rp, x, y = f.eveDefaultFn()
      f:SetPoint(dp, rel or UIParent, rp or dp, x or 0, y or 0)
    else
      local d = f.eveDefault
      local x = d[3]
      -- Right-edge defaults step aside when the Neocom is on the right.
      if not d.rel and d[2]:find("RIGHT") and ns.NeocomSide and ns.NeocomSide() == "right"
        and EveUIDB.neocom and f.eveKey ~= "neocom" then
        x = x - 44
      end
      f:SetPoint(d[1], d.rel or UIParent, d[2], x, d[4])
    end
  end
end

-- o: key, label, point, rel, relPoint, x, y (or default = fn returning
-- point, rel, relPoint, x, y), onUnlock(unlocked), apply(f) for custom
-- placement, drag = { start(f), stop(f) }, resize = true, target (the frame
-- that moves; defaults to f), overlay = frame the outline covers.
function ns.Mover(f, o)
  f.eveKey, f.eveLabel, f.eveOnUnlock, f.eveApply = o.key, o.label or o.key, o.onUnlock, o.apply
  f.eveMoverOpts = o
  f.eveDefaultFn = o.default
  f.eveDefault = { o.point, o.relPoint or o.point, o.x or 0, o.y or 0, rel = o.rel }
  if f.SetMovable then f:SetMovable(true) end
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  ns.movers[#ns.movers + 1] = f
  if not o.noApply then ns.ApplyPos(f) end
  return f
end

-- Old signature, used by the modules: frame, key, point, relPoint, x, y, onUnlock.
function ns.Movable(f, key, point, relPoint, x, y, onUnlock)
  return ns.Mover(f, { key = key, label = ns.MOVER_LABELS[key], point = point, relPoint = relPoint,
    x = x, y = y, onUnlock = onUnlock })
end

ns.MOVER_LABELS = {
  hud = "Ship HUD", fleet = "Fleet", overview = "Overview", boss = "Hostiles", location = "Location",
  target = "Locked target", focus = "Focus", targettarget = "Target's target", pet = "Drone",
}

local moving

local function MoverOverlay(f)
  if f.eveMover then return f.eveMover end
  local o = f.eveMoverOpts or {}
  local target = o.target or f
  local m = CreateFrame("Frame", nil, o.overlayParent or f)
  local cover = o.overlay or f
  m:SetPoint("TOPLEFT", cover, "TOPLEFT", o.inset and o.inset[1] or 0, o.inset and o.inset[2] or 0)
  m:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", o.inset and o.inset[3] or 0, o.inset and o.inset[4] or 0)
  m:SetFrameStrata("DIALOG")
  m:SetFrameLevel(50)
  local px = ns.Px(m)
  ns.Box(m, { 0.36, 0.78, 0.86, 0.10 }, C.accent, px)
  -- Label tab in the top-left corner.
  local tag = CreateFrame("Frame", nil, m)
  tag:SetPoint("TOPLEFT", px, -px)
  local t = tag:CreateFontString(nil, "OVERLAY")
  ns.SetFont(t, 11, "", m)
  t:SetTextColor(unpack(C.accent))
  t:SetPoint("LEFT", 6 * px, 0)
  t:SetText(string.upper(f.eveLabel or f.eveKey))
  tag:SetSize(t:GetStringWidth() + 12 * px, 16 * px)
  local tb = tag:CreateTexture(nil, "BACKGROUND")
  tb:SetAllPoints()
  tb:SetColorTexture(0.02, 0.05, 0.06, 0.9)
  m.label = t
  m:EnableMouse(true)
  m:RegisterForDrag("LeftButton")
  m:SetScript("OnDragStart", function()
    if InCombatLockdown() then return end
    moving = target
    if o.drag and o.drag.start then o.drag.start(f) else target:StartMoving() end
  end)
  m:SetScript("OnDragStop", function()
    moving = nil
    if o.drag and o.drag.stop then o.drag.stop(f); return end
    target:StopMovingOrSizing()
    if o.save then o.save(f) else SavePos(f) end
    ns.RunLayout()
  end)
  -- Resize grip (chat).
  if o.resize then
    local g = CreateFrame("Button", nil, m)
    g:SetSize(16 * px, 16 * px)
    g:SetPoint("BOTTOMRIGHT", -px, px)
    for i = 1, 3 do
      local l = g:CreateTexture(nil, "OVERLAY")
      l:SetColorTexture(unpack(C.accent))
      l:SetSize(px, (4 * i) * px)
      l:SetPoint("BOTTOMRIGHT", -(4 * (i - 1) + 2) * px, 2 * px)
      local h = g:CreateTexture(nil, "OVERLAY")
      h:SetColorTexture(unpack(C.accent))
      h:SetSize((4 * i) * px, px)
      h:SetPoint("BOTTOMRIGHT", -2 * px, (4 * (i - 1) + 2) * px)
    end
    g:SetScript("OnMouseDown", function()
      if InCombatLockdown() then return end
      moving = target
      if target.SetResizable then target:SetResizable(true) end
      target:StartSizing("BOTTOMRIGHT")
    end)
    g:SetScript("OnMouseUp", function()
      moving = nil
      target:StopMovingOrSizing()
      if o.save then o.save(f) else SavePos(f) end
    end)
  end
  f.eveMover = m
  return m
end

function ns.SetLocked(locked, quiet)
  if not locked and InCombatLockdown() then return ns.Print("can't unlock the layout in combat.") end
  if moving then moving:StopMovingOrSizing(); moving = nil end
  ns.unlocked = not locked
  for _, f in ipairs(ns.movers) do
    if f.eveOnUnlock then ns.Safe("unlock " .. f.eveKey, f.eveOnUnlock)(ns.unlocked) end
    if ns.unlocked or f.eveMover then MoverOverlay(f):SetShown(ns.unlocked) end
  end
  if ns.OnLockChanged then ns.OnLockChanged() end
  if not quiet then
    ns.Print(ns.unlocked and "layout unlocked: drag the outlined elements, then Lock in /eveui."
      or "layout locked.")
  end
end

function ns.ResetLayout()
  if InCombatLockdown() then return ns.Print("can't reset the layout in combat.") end
  local l = ns.Layout()
  l.pos, l.chat, l.neocom = {}, nil, nil
  for _, f in ipairs(ns.movers) do ns.Safe("reset " .. f.eveKey, ns.ApplyPos)(f) end
  if ns.PlaceChatDefault then ns.Safe("chat reset", ns.PlaceChatDefault)() end
  ns.RunLayout()
  ns.Print("layout reset.")
end

-- Combat: lock first (this runs just before the lockdown starts).
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function()
  if ns.unlocked then
    ns.SetLocked(true, true)
    ns.Print("layout locked for combat.")
  end
end)

-- Blizzard frames ---------------------------------------------------------------

ns.hider = CreateFrame("Frame", "EveUIHider")
ns.hider:Hide()

function ns.Hide(f)
  if f and not (f.IsForbidden and f:IsForbidden()) then f:SetParent(ns.hider) end
end

-- Hide a frame Blizzard's layout code manages (micro menu, bags bar, status
-- bars) without reparenting it: SetParent fires OnHide, Blizzard's layout then
-- runs inside addon code and its fields stay tainted, which later blocks
-- action bar moves in combat. Alpha and mouse changes fire no scripts.
function ns.Ghost(f, depth)
  depth = depth or 0
  if not f or depth > 4 or (f.IsForbidden and f:IsForbidden()) then return end
  if depth == 0 then f:SetAlpha(0) end
  -- Mouse changes on protected frames are blocked in combat.
  if InCombatLockdown() and f.IsProtected and f:IsProtected() then return end
  if f.EnableMouse then f:EnableMouse(false) end
  if f.EnableMouseWheel then f:EnableMouseWheel(false) end
  for _, c in ipairs({ f:GetChildren() }) do ns.Ghost(c, depth + 1) end
end

-- Move a Blizzard frame. Edit Mode frames override ClearAllPoints/SetPoint
-- with snapping code that writes Lua fields; run from addon code those fields
-- become tainted and Edit Mode's later action bar layout is blocked in
-- combat. The *Base methods are the plain C calls.
function ns.Move(f, ...)
  if not f then return end
  local clear = f.ClearAllPointsBase or f.ClearAllPoints
  local set = f.SetPointBase or f.SetPoint
  clear(f)
  set(f, ...)
end

function ns.Kill(f)
  if not f then return end
  if f.UnregisterAllEvents then f:UnregisterAllEvents() end
  ns.Ghost(f)
end

local function HideBlizzard()
  ns.Kill(PlayerFrame)
  ns.Kill(TargetFrame)
  ns.Kill(FocusFrame)
  ns.Kill(PetFrame)
  ns.Kill(PartyFrame)
  ns.Kill(PlayerCastingBarFrame)
  ns.Kill(PetCastingBarFrame)
end

-- Font restyle: every Blizzard font object switches to the EVE face, and the
-- gold "normal" colour becomes EVE white.
-- Swap the face of every named font object, keeping its size and outline.
-- Runs at load and again after each load-on-demand addon (they bring their
-- own font objects). The gold "normal" colour becomes EVE white.
local function RestyleFont(obj)
  local file, size, flags = obj:GetFont()
  if size and size > 0 and file ~= ns.FONT then obj:SetFont(ns.FONT, size, flags or "") end
  local r, g, b = obj:GetTextColor()
  if r and r > 0.95 and g > 0.75 and g < 0.9 and b < 0.15 then
    obj:SetTextColor(C.title[1], C.title[2], C.title[3])
  end
end

local function RestyleFonts()
  for name, obj in pairs(_G) do
    if type(name) == "string" and type(obj) == "table" then
      local ok, kind = pcall(function() return obj.GetObjectType and obj:GetObjectType() end)
      if ok and kind == "Font" then pcall(RestyleFont, obj) end
    end
  end
  ns.StyleChatFonts()
end

-- Chat: no outline, a light drop shadow, and at least 12 pt. Each window
-- keeps the size picked in its tab menu.
local function ChatFace(obj, size)
  obj:SetFont(ns.FONT, size, "")
  if obj.SetShadowOffset then obj:SetShadowOffset(1, -1) end
  if obj.SetShadowColor then obj:SetShadowColor(0, 0, 0, 0.7) end
end
function ns.StyleChatFonts()
  for _, n in ipairs({ "ChatFontNormal", "ChatFontSmall", "ChatFontLarge", "ChatFontExtraLarge" }) do
    local obj = _G[n]
    if obj and obj.GetFont then
      local _, size = obj:GetFont()
      if size and size > 0 then pcall(ChatFace, obj, size) end
    end
  end
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local cf = _G["ChatFrame" .. i]
    if cf and cf.GetFont then
      local file, size, flags = cf:GetFont()
      if size and (file ~= ns.FONT or (flags and flags ~= "") or size < 12) then
        pcall(ChatFace, cf, math.max(size, 12))
      end
    end
  end
end
ns.RestyleFonts = RestyleFonts

local fontPass
local function QueueFonts()
  if fontPass then return end
  fontPass = true
  C_Timer.After(0.1, function() fontPass = nil; ns.Safe("fonts", RestyleFonts)() end)
end
ns.QueueFonts = QueueFonts

function ns.RunLayout()
  if InCombatLockdown() then ns.pendingLayout = true return end
  for i, fn in ipairs(ns.layoutHooks) do ns.Safe("layout " .. i, fn)() end
end

-- Startup ------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
-- Record blocked protected calls so taint can be traced (written on /reload).
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blocked:SetScript("OnEvent", function(_, event, addon, func)
  if addon ~= ADDON then return end
  ns.blockedCount = (ns.blockedCount or 0) + 1
  ns.Print("|cffff5544blocked:|r " .. tostring(func))
  EveUIDB.errors = EveUIDB.errors or {}
  if #EveUIDB.errors < 40 then
    table.insert(EveUIDB.errors, event .. ": " .. tostring(func) .. "\n" .. (debugstack(3, 12, 0) or ""))
  end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
ev:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg ~= ADDON then QueueFonts() end
  if event == "ADDON_LOADED" and arg == ADDON then
    EveUIDB = EveUIDB or {}
    for k, v in pairs(defaults) do
      if EveUIDB[k] == nil then EveUIDB[k] = type(v) == "table" and {} or v end
    end
    EveUIDB.errors = {}
  elseif event == "PLAYER_LOGIN" then
    ns.UpdateScale()
    ns.Safe("fonts", RestyleFonts)()
    if FCF_SetChatWindowFontSize then hooksecurefunc("FCF_SetChatWindowFontSize", QueueFonts) end
    if EveUIDB.hideBlizzard then ns.Safe("hide blizzard", HideBlizzard)() end
    ns.Layout()
    for i, m in ipairs(ns.modules) do
      if not m.key or ns.ModuleOn(m.key) then ns.Safe("module " .. (m.key or i), m.fn)() end
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(0.2, ns.RunLayout)
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    ns.UpdateScale()
    ns.RunLayout()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if ns.pendingScale then ns.pendingScale = nil; ns.UpdateScale() end
    if ns.pendingLayout then ns.pendingLayout = nil; ns.RunLayout() end
  end
end)

if EditModeManagerFrame then
  hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() C_Timer.After(0, ns.RunLayout) end)
end

SLASH_EVEUI1, SLASH_EVEUI2 = "/eveui", "/eve"
SlashCmdList.EVEUI = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "config" or cmd == "settings" or cmd == "options" then
    if ns.ToggleSettings then ns.ToggleSettings() end
  elseif cmd == "unlock" then
    ns.SetLocked(false)
  elseif cmd == "lock" then
    ns.SetLocked(true)
  elseif (cmd == "reset" or cmd == "scale") and InCombatLockdown() then
    ns.Print("not in combat.")
  elseif cmd == "reset" then
    ns.ResetLayout()
  elseif cmd == "scale" and tonumber(arg) then
    EveUIDB.scale = math.min(math.max(tonumber(arg), 0.5), 2)
    ns.UpdateScale()
  elseif cmd == "blizz" then
    EveUIDB.hideBlizzard = not EveUIDB.hideBlizzard
    ReloadUI()
  elseif cmd == "neocom" then
    EveUIDB.neocom = not EveUIDB.neocom
    ReloadUI()
  elseif cmd == "test" and ns.TestSCT then
    ns.TestSCT()
  elseif cmd == "cast" and ns.playerCast then
    -- /eve cast [cast|channel|locked|interrupt]: preview the cycle rings.
    local kind = (arg and arg ~= "") and arg or "cast"
    ns.playerCast.Test(kind)
    if ns.targetCast and UnitExists("target") then ns.targetCast.Test(kind) end
  elseif cmd == "show" and ns.DevShow then
    ns.DevShow(msg:match("^%S+%s+(.+)$"))
  elseif cmd == "preview" and ns.Preview then
    ns.Preview(arg)
  elseif cmd == "clicks" then
    EveUIDB.debugClicks = not EveUIDB.debugClicks
    ns.Print("click debug " .. (EveUIDB.debugClicks and "on" or "off"))
  elseif cmd == "dev" and ns.ToggleDev then
    ns.ToggleDev()
  elseif cmd == "art" and ns.ArtScan then
    -- /eve art: list the Blizzard textures still on screen.
    local out = ns.ArtScan()
    ns.Print(#out .. " Blizzard textures visible (full list in EveUIDB.artScan after /reload):")
    for i = 1, math.min(#out, 15) do ns.Print("  " .. out[i]) end
  elseif cmd == "check" and ns.Check then
    ns.Check()
  elseif cmd == "cvars" then
    for _, k in ipairs({ "autoInteract", "taintLog", "ActionButtonUseKeyDown" }) do ns.Print(k .. " = " .. tostring(GetCVar(k))) end
  elseif cmd == "plates" then
    for i = 1, 40 do
      local u = "nameplate" .. i
      if UnitExists(u) then ns.Print(u .. " " .. tostring(ns.Plain(UnitName(u)))) end
    end
  elseif cmd == "style" then
    -- /eve style eve | classic: ring HUD and lock frames, or traditional bars.
    if arg == "eve" or arg == "classic" then
      EveUIDB.frameStyle = arg == "eve" and "eve" or nil
      ReloadUI()
    else
      ns.Print("frame style: " .. (EveUIDB.frameStyle == "eve" and "eve" or "classic") .. "  (/eve style eve | classic)")
    end
  elseif cmd == "pilot" and ns.pilot then
    ns.pilot.Command(arg)
  elseif cmd == "debug" and ns.DebugDump then
    ns.DebugDump()
  else
    ns.Print("/eveui opens the settings window. Commands: unlock | lock | reset | scale <0.5-2> | blizz | neocom | test | cast [channel|locked|interrupt] | check | pilot | style")
  end
end
