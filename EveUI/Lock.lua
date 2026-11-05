-- Locked-target style unit frames for target, focus, target-of-target and pet:
-- round portrait, health and power arcs, name, type, range, cast bar, auras.
-- Each is a secure unit button (left-click targets, right-click opens the
-- unit menu) shown and hidden by the game through RegisterUnitWatch.
local ADDON, ns = ...
local C = ns.C

local ICON, GAP, PER_ROW = 24, 3, 8

-- Aura icons -------------------------------------------------------------------

local timerFont = CreateFont("EveUIAuraTimer")
timerFont:SetFont(ns.FONT, 10, "OUTLINE")
timerFont:SetTextColor(1, 1, 1)

local function CreateIcons(parent, count)
  local icons = {}
  for i = 1, count do
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(ICON, ICON)
    ns.Box(b, { 0, 0, 0, 0.7 })
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.tex)
    b.cd:SetDrawEdge(false)
    b.cd:SetReverse(true)
    b.cd:SetHideCountdownNumbers(false)
    if b.cd.SetCountdownFont then b.cd:SetCountdownFont("EveUIAuraTimer") end
    b.count = ns.Text(b, 11, C.title, "RIGHT", "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", 1, 1)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
      if not self.unit or not self.index then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
      GameTooltip:SetUnitAura(self.unit, self.index, self.filter)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    icons[i] = b
  end
  return icons
end

-- In combat the game may lock aura data for other units; then try just your
-- own auras ("|PLAYER"), and hide the row if those are locked too.
local function GetAura(unit, i, filter)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
  local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
  if ok then return a end
  ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter .. "|PLAYER")
  if ok then return a end
end

local function FillIcons(icons, unit, filter, border)
  for i, b in ipairs(icons) do
    local a = GetAura(unit, i, filter)
    if a then
      b.unit, b.index, b.filter = unit, i, filter
      b.tex:SetTexture(a.icon)
      ns.SetBoxBorder(b, border)
      local id = a.auraInstanceID
      local dur = id and C_UnitAuras.GetAuraDuration and ns.Call(C_UnitAuras.GetAuraDuration, unit, id)
      if dur and b.cd.SetCooldownFromDurationObject then
        pcall(b.cd.SetCooldownFromDurationObject, b.cd, dur)
      else
        local d, e = ns.Plain(a.duration), ns.Plain(a.expirationTime)
        if d and e and d > 0 then b.cd:SetCooldown(e - d, d) else b.cd:Clear() end
      end
      local n = ns.Plain(a.applications)
      if n then
        b.count:SetText(n > 1 and n or "")
      elseif C_UnitAuras.GetAuraApplicationDisplayCount and id then
        pcall(function() b.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, id, 2, 99)) end)
      else
        b.count:SetText("")
      end
      b:Show()
    else
      b:Hide()
    end
  end
end

-- Lock frame -------------------------------------------------------------------

local function Describe(unit)
  local lvl = ns.Plain(UnitLevel(unit))
  local s = (lvl and lvl > 0) and ("Lv " .. lvl) or "Lv ??"
  local class = ns.Plain(UnitClassification(unit))
  if class == "worldboss" then s = s .. " Boss"
  elseif class == "rareelite" then s = s .. " Rare Elite"
  elseif class == "elite" then s = s .. " Elite"
  elseif class == "rare" then s = s .. " Rare" end
  local kind
  if ns.Plain(UnitIsPlayer(unit)) then kind = ns.Plain(UnitClass(unit)) else kind = ns.Plain(UnitCreatureType(unit)) end
  return kind and (s .. "  " .. kind) or s
end

local function CreateLock(o)
  local size, R = o.size, o.size / 2
  local w = math.max(size + 60, o.auras and (PER_ROW * (ICON + GAP) - GAP) or 0)
  local small = size < 90
  local h = 16 + size + 6 + (small and 14 or 16) + (o.info and 30 or 0) + (o.cast and 26 or 0)
    + (o.auras and 2 * (ICON + GAP) + 4 or 0)

  local f = CreateFrame("Frame", o.name, ns.root)
  f:SetSize(w, h)
  ns.Movable(f, o.key, unpack(o.pos))

  local b = CreateFrame("Button", o.name .. "Button", f, "SecureUnitButtonTemplate")
  b:SetAllPoints()
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("unit", o.unit)
  b:SetAttribute("type1", "target")
  b:SetAttribute("type2", "togglemenu")
  RegisterUnitWatch(b)

  local label = ns.Text(b, small and 10 or 11, C.accent)
  label:SetPoint("TOP", 0, 0)
  label:SetText(o.label)

  local ring = CreateFrame("Frame", nil, b)
  ring:SetSize(size, size)
  ring:SetPoint("TOP", 0, -16)
  -- Dial plate under the arcs, then the raised core the portrait sits in.
  local plate = ns.Orb(ring, math.floor(size * 1.06), 0.35, "BACKGROUND", -5)
  plate:SetPoint("CENTER")
  local disk = ns.Orb(ring, math.floor(size * 0.68), 0.65, "BACKGROUND", 0)
  disk:SetPoint("CENTER")

  local portrait = ring:CreateTexture(nil, "ARTWORK")
  local ps = math.floor(size * 0.56)
  portrait:SetSize(ps, ps)
  portrait:SetPoint("CENTER")
  local mask = ring:CreateMaskTexture()
  mask:SetTexture(ns.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(portrait)
  portrait:AddMaskTexture(mask)
  ns.Lens(ring, portrait)

  local hp = ns.CreateArc(ring, { radius = math.floor(R * 0.78), thickness = small and 4 or 6,
    from = -140, to = 140, segments = small and 22 or 36, color = C.health, bars = true })
  local pw = ns.CreateArc(ring, { radius = math.floor(R * 0.93), thickness = small and 2 or 3,
    from = -140, to = 140, segments = small and 26 or 44, bars = true })

  local pct = ns.Text(ring, small and 10 or 12, C.title)
  pct:SetPoint("CENTER", ring, "CENTER", 0, -math.floor(R * 0.80))

  local name = ns.Text(b, small and 12 or 14, C.title)
  name:SetPoint("TOP", ring, "BOTTOM", 0, -4)
  name:SetWidth(w)

  local info, range
  if o.info then
    info = ns.Text(b, 11, C.dim)
    info:SetPoint("TOP", name, "BOTTOM", 0, -3)
    range = ns.Text(b, 11, C.accent)
    range:SetPoint("TOP", info, "BOTTOM", 0, -2)
  end

  -- Cast cycle ring just outside the power arc; name and time under the info.
  local cast
  if o.cast then
    cast = ns.CreateCast(ring, o.unit, { radius = math.floor(R) + 3, thickness = small and 2 or 3,
      from = -150, to = 150, segments = small and 36 or 56, textSize = small and 10 or 11, barWidth = w - 30 })
    cast.text:SetPoint("TOP", range or name, "BOTTOM", 0, -6)
    cast.text:SetWidth(w)
    if o.unit == "target" then ns.targetCast = cast end
  end

  local debuffs, buffs
  if o.auras then
    local anchor = CreateFrame("Frame", nil, b)
    anchor:SetSize(w, 1)
    anchor:SetPoint("BOTTOM", 0, 2 * (ICON + GAP))
    debuffs = CreateIcons(b, PER_ROW)
    buffs = CreateIcons(b, PER_ROW)
    for i = 1, PER_ROW do
      debuffs[i]:SetPoint("TOPLEFT", anchor, "TOPLEFT", (i - 1) * (ICON + GAP), 0)
      buffs[i]:SetPoint("TOPLEFT", anchor, "TOPLEFT", (i - 1) * (ICON + GAP), -(ICON + GAP))
    end
  end

  local function Portrait() SetPortraitTexture(portrait, o.unit) end
  b:RegisterEvent("UNIT_PORTRAIT_UPDATE")
  for _, e in ipairs(o.events or {}) do b:RegisterEvent(e) end
  b:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_PORTRAIT_UPDATE" or unit == o.unit then Portrait() end
  end)
  b:HookScript("OnShow", Portrait)

  local function Update()
    if not UnitExists(o.unit) then return end
    hp:SetHealth(o.unit)
    -- No power bar for units without one (most beasts).
    local pmax = ns.Plain(UnitPowerMax(o.unit))
    pw:SetShown(pmax == nil or pmax > 0)
    pw:SetColor(ns.PowerColor(o.unit))
    pw:SetPower(o.unit)

    local color = ns.Plain(UnitIsPlayer(o.unit)) and ns.ClassColor(o.unit) or ns.ReactionColor(o.unit)
    label:SetTextColor(unpack(ns.ReactionColor(o.unit)))
    name:SetText(UnitName(o.unit))
    name:SetTextColor(unpack(color))

    if ns.Plain(UnitIsDeadOrGhost(o.unit)) then
      pct:SetText("WRECK")
    elseif ns.Plain(UnitIsConnected(o.unit)) == false then
      pct:SetText("OFFLINE")
    else
      ns.SetHealthText(pct, o.unit)
    end
    if info then
      info:SetText(Describe(o.unit))
      local _, r = ns.Range(o.unit)
      range:SetText(r)
    end
    if o.tick then Portrait() end
    if debuffs then
      FillIcons(debuffs, o.unit, "HARMFUL", C.hostile)
      FillIcons(buffs, o.unit, "HELPFUL", C.border)
    end
  end

  ns.Every(0.1, o.key, Update)
  return f
end

ns.RegisterModule(function()
  if ns.Classic() then return end
  ns.target = CreateLock({ name = "EveUITarget", key = "target", unit = "target", size = 132,
    label = "LOCKED TARGET", info = true, cast = true, auras = true,
    pos = { "TOP", "TOP", 0, -34 }, events = { "PLAYER_TARGET_CHANGED" } })
  CreateLock({ name = "EveUIFocus", key = "focus", unit = "focus", size = 84,
    label = "FOCUS", info = true, cast = true,
    pos = { "TOP", "TOP", -300, -34 }, events = { "PLAYER_FOCUS_CHANGED" } })
  CreateLock({ name = "EveUITargetTarget", key = "targettarget", unit = "targettarget", size = 64,
    label = "TARGET'S TARGET", tick = true,
    pos = { "TOP", "TOP", 250, -34 }, events = { "PLAYER_TARGET_CHANGED" } })
  CreateLock({ name = "EveUIPet", key = "pet", unit = "pet", size = 72,
    label = "DRONE", cast = true,
    pos = { "BOTTOM", "BOTTOM", -250, 300 }, events = { "UNIT_PET" } })
end, "locks")

-- Traditional unit frames ----------------------------------------------------------
-- The default style (EveUIDB.frameStyle ~= "eve"): rectangular frames with a
-- portrait, name and level, a red health bar and a power bar with numbers,
-- and horizontal cast bars with icon, spell name and time. Same palette and
-- glass bars as the rest of EveUI. /eve style eve brings back the rings.

function ns.Classic() return not (EveUIDB and EveUIDB.frameStyle == "eve") end

local STEEL = { 0.62, 0.70, 0.76, 1 }
local GOOD = { 0.45, 0.95, 0.55, 1 }

local function Groove(bar)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(ns.WHITE)
  ns.Gradient(bg, { 0, 0, 0, 0.75 }, { 0.12, 0.15, 0.17, 0.75 })
end

local function NewBar(parent, h)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetHeight(h)
  bar:SetStatusBarTexture(ns.WHITE)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(100)
  Groove(bar)
  ns.Bar3D(bar)
  return bar
end

-- Cast bar ------------------------------------------------------------------------

local CAST_EVENTS = {
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
  "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- o: unit, w, h, parent, point = { ... } or key/pos for a movable bar.
function ns.CreateCastBar(o)
  local unit = o.unit
  local f = CreateFrame("Frame", o.name, o.parent or ns.root)
  f:SetSize(o.w, o.h)
  if o.key then ns.Movable(f, o.key, unpack(o.pos)) else f:SetPoint(unpack(o.point)) end
  local d = CreateFrame("Frame", nil, f)
  d:SetAllPoints()
  d:Hide()
  ns.Box(d, C.panel, C.border)

  local icon = d:CreateTexture(nil, "ARTWORK")
  icon:SetSize(o.h - 2, o.h - 2)
  icon:SetPoint("LEFT", 1, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local bar = NewBar(d, o.h - 6)
  bar:SetPoint("LEFT", icon, "RIGHT", 3, 0)
  bar:SetPoint("RIGHT", -3, 0)
  bar:SetMinMaxValues(0, 1)
  local spark = bar:CreateTexture(nil, "OVERLAY", nil, 3)
  spark:SetTexture(ns.WHITE)
  spark:SetBlendMode("ADD")
  spark:SetVertexColor(1, 1, 1, 0.8)
  spark:SetSize(2, o.h - 4)
  spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
  local name = ns.Text(bar, math.min(o.h - 6, 13), C.title, "LEFT", "OUTLINE")
  name:SetPoint("LEFT", 5, 0)
  name:SetPoint("RIGHT", -44, 0)
  local time = ns.Text(bar, math.min(o.h - 6, 12), C.title, "RIGHT", "OUTLINE")
  time:SetPoint("RIGHT", -5, 0)

  local fade = d:CreateAnimationGroup()
  local fa = fade:CreateAnimation("Alpha")
  fa:SetFromAlpha(1); fa:SetToAlpha(0); fa:SetDuration(0.35)
  fade:SetScript("OnFinished", function() d:Hide(); d:SetAlpha(1) end)

  local st = {}
  local function Color()
    if st.locked then return STEEL end
    return st.channel and C.accent or C.cast
  end
  local function Remaining()
    if st.manual then return math.max(st.e - GetTime(), 0) end
    if st.dur then
      local ok, r = pcall(st.dur.GetRemainingDuration, st.dur)
      if ok and type(r) == "number" and not ns.issecret(r) then return r end
    end
  end
  local function OnUpdate()
    if st.manual then
      local p = math.min(math.max((GetTime() - st.s) / (st.e - st.s), 0), 1)
      bar:SetValue(st.channel and (1 - p) or p)
    end
    local r = Remaining()
    if r then time:SetFormattedText("%.1f", r) else time:SetText("") end
  end
  local function Start(channel)
    local n, tex, s, e, castID, locked, _
    if channel then
      n, _, tex, s, e, _, locked = UnitChannelInfo(unit)
    else
      n, _, tex, s, e, _, castID, locked = UnitCastingInfo(unit)
    end
    if not ns.issecret(n) and n == nil then st.active = nil; d:Hide(); return end
    fade:Stop(); d:SetAlpha(1)
    st.active, st.channel, st.castID = true, channel, ns.Plain(castID)
    st.locked = ns.Plain(locked) == true
    st.dur = ns.Call(channel and UnitChannelDuration or UnitCastingDuration, unit)
    pcall(icon.SetTexture, icon, tex)
    pcall(name.SetText, name, n)
    name:SetTextColor(unpack(C.title))
    ns.SetBarColor(bar, Color())
    s, e = ns.Plain(s), ns.Plain(e)
    st.manual = (s and e and e > s) and true or nil
    if st.manual then
      st.s, st.e = s / 1000, e / 1000
      bar:SetMinMaxValues(0, 1)
    elseif not ns.SetTimer(bar, st.dur, channel) then
      bar:SetMinMaxValues(0, 1); bar:SetValue(channel and 1 or 0)
    end
    d:SetScript("OnUpdate", OnUpdate)
    OnUpdate()
    d:Show()
  end
  local function Finish(ok, text)
    if not st.active then return end
    st.active = nil
    d:SetScript("OnUpdate", nil)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.eveColor = nil
    ns.SetBarColor(bar, ok and GOOD or C.hostile)
    time:SetText("")
    if not ok then name:SetText(text or "INTERRUPTED"); name:SetTextColor(unpack(C.hostile)) end
    fa:SetStartDelay(ok and 0.1 or 0.5)
    fade:Stop(); fade:Play()
  end
  local function Refresh()
    st.active = nil
    d:SetScript("OnUpdate", nil)
    fade:Stop(); d:Hide()
    if ns.issecret(UnitCastingInfo(unit)) or UnitCastingInfo(unit) ~= nil then return Start(false) end
    if ns.issecret(UnitChannelInfo(unit)) or UnitChannelInfo(unit) ~= nil then return Start(true) end
  end
  local function Same(castID)
    castID = ns.Plain(castID)
    return st.castID == nil or castID == nil or castID == st.castID
  end

  local ev = CreateFrame("Frame")
  for _, e in ipairs(CAST_EVENTS) do ev:RegisterUnitEvent(e, unit) end
  if unit == "target" then ev:RegisterEvent("PLAYER_TARGET_CHANGED") end
  if unit == "focus" then ev:RegisterEvent("PLAYER_FOCUS_CHANGED") end
  if unit == "pet" then ev:RegisterEvent("UNIT_PET") end
  ev:SetScript("OnEvent", ns.Safe("castbar " .. unit, function(_, event, _, castID)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then Start(false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then Start(true)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      if st.active and not st.channel and Same(castID) then Finish(true) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
      if st.active and Same(castID) then Finish(false, "INTERRUPTED") end
    elseif event == "UNIT_SPELLCAST_FAILED" then
      if st.active and not st.channel and Same(castID) then Finish(false, "FAILED") end
    elseif event == "UNIT_SPELLCAST_STOP" then
      if st.active and not st.channel then Finish(false, "CANCELLED") end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
      if st.active and st.channel then
        local r = Remaining()
        Finish(r == nil or r < 0.3, "STOPPED")
      end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
      if st.active then st.locked = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"; bar.eveColor = nil; ns.SetBarColor(bar, Color()) end
    else
      Refresh()
    end
  end))

  -- /eve cast [cast|channel|locked|interrupt]: preview.
  local obj = { frame = f }
  function obj.Test(kind)
    fade:Stop(); d:SetAlpha(1)
    st.active, st.channel, st.locked, st.castID = true, kind == "channel", kind == "locked", nil
    st.manual, st.s, st.e, st.dur = true, GetTime(), GetTime() + 2.5, nil
    icon:SetTexture("Interface\\Icons\\Spell_Nature_StarFall")
    name:SetText(kind == "channel" and "Tranquility" or "Wrath")
    name:SetTextColor(unpack(C.title))
    bar.eveColor = nil
    ns.SetBarColor(bar, Color())
    d:SetScript("OnUpdate", OnUpdate)
    d:Show()
    if kind == "interrupt" then C_Timer.After(1.2, function() Finish(false, "INTERRUPTED") end)
    else C_Timer.After(2.5, function() Finish(true) end) end
  end
  obj.Refresh = Refresh
  return obj
end

-- Unit frame ----------------------------------------------------------------------

-- o: name, key, unit, w, h, portrait ("left"/"right"/nil), power, numbers,
--    cast (cast bar width or nil), auras, pos, events, tick
local function CreateUnitFrame(o)
  local f = CreateFrame("Frame", o.name, ns.root)
  f:SetSize(o.w, o.h)
  ns.Movable(f, o.key, unpack(o.pos))

  local b = CreateFrame("Button", o.name .. "Button", f, "SecureUnitButtonTemplate")
  b:SetAllPoints()
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("unit", o.unit)
  b:SetAttribute("type1", "target")
  b:SetAttribute("type2", "togglemenu")
  RegisterUnitWatch(b)
  ns.Box(b, C.panel, C.border)
  -- Soft drop shadow under the frame.
  local sh = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  sh:SetTexture(ns.WHITE)
  sh:SetPoint("TOPLEFT", 3, -4)
  sh:SetPoint("BOTTOMRIGHT", 4, -5)
  sh:SetVertexColor(0, 0, 0, 0.45)

  local pad = 4
  local left, right = pad, -pad
  local portrait, pbox
  if o.portrait then
    local ps = o.h - 2 * pad
    pbox = CreateFrame("Frame", nil, b)
    pbox:SetSize(ps, ps)
    if o.portrait == "left" then pbox:SetPoint("LEFT", pad, 0); left = pad + ps + 5
    else pbox:SetPoint("RIGHT", -pad, 0); right = -(pad + ps + 5) end
    ns.Box(pbox, { 0, 0, 0, 0.8 }, C.border)
    portrait = pbox:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", 1, -1)
    portrait:SetPoint("BOTTOMRIGHT", -1, 1)
    portrait:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    local gloss = pbox:CreateTexture(nil, "OVERLAY")
    gloss:SetTexture(ns.WHITE)
    gloss:SetPoint("TOPLEFT", 1, -1); gloss:SetPoint("TOPRIGHT", -1, -1)
    gloss:SetHeight(ps * 0.45)
    gloss:SetBlendMode("ADD")
    ns.Gradient(gloss, { 1, 1, 1, 0 }, { 1, 1, 1, 0.14 })
  end

  local big = o.h >= 50
  local name = ns.Text(b, big and 14 or 12, C.title, "LEFT")
  name:SetPoint("TOPLEFT", left, -pad)
  name:SetPoint("RIGHT", b, "RIGHT", right - 70, 0)
  local info = ns.Text(b, big and 11 or 10, C.dim, "RIGHT")
  info:SetPoint("TOPRIGHT", right, -pad - 1)

  local powH = o.power and (big and 9 or 5) or 0
  local hpH = o.h - 2 * pad - (big and 18 or 15) - (o.power and (powH + 2) or 0)
  local hp = NewBar(b, hpH)
  hp:SetPoint("TOPLEFT", left, -(pad + (big and 18 or 15)))
  hp:SetPoint("RIGHT", b, "RIGHT", right, 0)
  ns.SetBarColor(hp, C.health)
  local hpText = ns.Text(hp, big and 12 or 10, C.title, "LEFT", "OUTLINE")
  hpText:SetPoint("LEFT", 5, 0)
  local pctText = ns.Text(hp, big and 12 or 10, C.title, "RIGHT", "OUTLINE")
  pctText:SetPoint("RIGHT", -5, 0)
  if not o.numbers then hpText:Hide(); pctText:ClearAllPoints(); pctText:SetPoint("CENTER") end

  local pw, pwText
  if o.power then
    pw = NewBar(b, powH)
    pw:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -2)
    pw:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -2)
    if big then
      pwText = ns.Text(pw, 9, C.title, "CENTER", "OUTLINE")
      pwText:SetPoint("CENTER", 0, 0)
    end
  end

  local cast
  if o.cast then
    cast = ns.CreateCastBar({ unit = o.unit, w = o.cast, h = 18, parent = f,
      point = { o.castPoint or "BOTTOM", f, o.castRel or "TOP", 0, 4 } })
  end

  local debuffs, buffs
  if o.auras then
    debuffs = CreateIcons(b, PER_ROW)
    buffs = CreateIcons(b, PER_ROW)
    for i = 1, PER_ROW do
      -- Above the frame and its cast bar: debuffs first, buffs on top.
      local y0 = 4 + (o.cast and 22 or 0)
      debuffs[i]:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (ICON + GAP), y0)
      buffs[i]:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (ICON + GAP), y0 + ICON + GAP)
    end
  end

  local function Portrait() if portrait then SetPortraitTexture(portrait, o.unit) end end
  b:RegisterEvent("UNIT_PORTRAIT_UPDATE")
  for _, e in ipairs(o.events or {}) do b:RegisterEvent(e) end
  b:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_PORTRAIT_UPDATE" or unit == o.unit then Portrait() end
  end)
  b:HookScript("OnShow", Portrait)

  local function Update()
    local u = o.unit
    if not UnitExists(u) then return end
    local isPlayer = ns.Plain(UnitIsPlayer(u))
    name:SetText(UnitName(u))
    name:SetTextColor(unpack(isPlayer and ns.ClassColor(u) or ns.ReactionColor(u)))

    local lvl = ns.Plain(UnitLevel(u))
    local class = ns.Plain(UnitClassification(u))
    local tag = (class == "worldboss" and " Boss") or (class == "rareelite" and " Rare+") or
      (class == "elite" and "+") or (class == "rare" and " Rare") or ""
    local extra = ""
    if u == "player" then
      if UnitAffectingCombat("player") then extra = "|cffeb4538COMBAT|r  "
      elseif IsResting() then extra = "|cff808c93RESTING|r  " end
    end
    info:SetText(extra .. ((lvl and lvl > 0) and lvl or "??") .. tag)
    if pbox then
      ns.SetBoxBorder(pbox, (class == "elite" or class == "worldboss" or class == "rareelite") and C.neutral
        or (class == "rare" and STEEL) or C.border)
    end

    pcall(hp.SetValue, hp, ns.HealthPct100(u))
    local dead = ns.Plain(UnitIsDeadOrGhost(u))
    local offline = ns.Plain(UnitIsConnected(u)) == false
    if dead or offline then
      pctText:SetText(dead and "DEAD" or "OFFLINE")
      hpText:SetText("")
    else
      ns.SetHealthText(pctText, u)
      if o.numbers then
        pcall(hpText.SetFormattedText, hpText, "%s / %s", AbbreviateNumbers(UnitHealth(u)), AbbreviateNumbers(UnitHealthMax(u)))
      end
    end

    if pw then
      local pmax = ns.Plain(UnitPowerMax(u))
      local has = pmax == nil or pmax > 0
      pw:SetAlpha(has and 1 or 0.25)
      ns.SetBarColor(pw, ns.PowerColor(u))
      pcall(pw.SetValue, pw, has and ns.PowerPct100(u) or 0)
      if pwText then
        if has then pcall(pwText.SetFormattedText, pwText, "%s / %s", AbbreviateNumbers(UnitPower(u)), AbbreviateNumbers(UnitPowerMax(u)))
        else pwText:SetText("") end
      end
    end
    if o.tick then Portrait() end
    if debuffs then
      FillIcons(debuffs, u, "HARMFUL", C.hostile)
      FillIcons(buffs, u, "HELPFUL", C.border)
    end
  end
  ns.Every(0.1, o.key, Update)
  return f, cast
end

ns.MOVER_LABELS.uplayer = "Player"
ns.MOVER_LABELS.utarget = "Target"
ns.MOVER_LABELS.ufocus = "Focus"
ns.MOVER_LABELS.utot = "Target's target"
ns.MOVER_LABELS.upet = "Pet"
ns.MOVER_LABELS.ucast = "Cast bar"

ns.RegisterModule(function()
  if not ns.Classic() then return end
  local _, pcast = CreateUnitFrame({ name = "EveUIPlayerFrame", key = "uplayer", unit = "player", w = 260, h = 62,
    portrait = "left", power = true, numbers = true, pos = { "BOTTOM", "BOTTOM", -170, 250 } })
  local player = ns.CreateCastBar({ name = "EveUIPlayerCast", key = "ucast", unit = "player", w = 240, h = 22,
    -- In the gap between the two action bar racks, where the ring HUD was.
    pos = { "BOTTOM", "BOTTOM", 0, 150 } })
  ns.playerCast = player
  local _, tcast = CreateUnitFrame({ name = "EveUITargetFrame", key = "utarget", unit = "target", w = 260, h = 62,
    portrait = "right", power = true, numbers = true, cast = 260, auras = true,
    pos = { "BOTTOM", "BOTTOM", 170, 250 }, events = { "PLAYER_TARGET_CHANGED" } })
  ns.targetCast = tcast
  CreateUnitFrame({ name = "EveUIFocusFrame", key = "ufocus", unit = "focus", w = 200, h = 46,
    portrait = "left", power = true, numbers = false, cast = 200,
    pos = { "BOTTOM", "BOTTOM", -420, 340 }, events = { "PLAYER_FOCUS_CHANGED" } })
  CreateUnitFrame({ name = "EveUITargetTargetFrame", key = "utot", unit = "targettarget", w = 150, h = 34,
    power = false, numbers = false, tick = true, pos = { "BOTTOM", "BOTTOM", 385, 250 },
    events = { "PLAYER_TARGET_CHANGED" } })
  CreateUnitFrame({ name = "EveUIPetFrame", key = "upet", unit = "pet", w = 150, h = 38,
    power = true, numbers = false, pos = { "BOTTOM", "BOTTOM", -385, 250 }, events = { "UNIT_PET" } })
end, "unitframes")
