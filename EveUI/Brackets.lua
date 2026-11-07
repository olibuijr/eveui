-- Brackets: EVE-style overlay on Blizzard nameplates. A small glyph shaped by
-- unit kind and coloured by reaction, a compact name, a distance figure, a thin
-- health line, corner brackets with a lock-up animation on your target, a red
-- pulse ring on units that are on you, and a cyan badge for fleet tags
-- (ns.fleetTags[guid], filled by Broadcasts.lua).
--
-- Our widgets live on our own frame, one per plate, created once and reused.
-- Blizzard's health bar, name, level and classification art are only faded to
-- alpha 0 (never reparented); the cast bar is left alone so Skins.lua keeps it.
-- Forbidden plates (friendly plates in instances) are skipped. Health, names
-- and reaction can be secret in combat; they go to widgets that accept secrets
-- or through ns.Plain, and anything that needs a plain value just keeps its
-- last state until it is plain again.
local ADDON, ns = ...
local C = ns.C
local Plain = ns.Plain

local LOCK_TIME = 0.55
local TAG_TTL = 120
local TICKS = 8

local byPlate = setmetatable({}, { __mode = "k" })
local active = {} -- unit token -> bracket

local function Opts()
  EveUIDB.brackets = EveUIDB.brackets or {}
  local o = EveUIDB.brackets
  if o.enabled == nil then o.enabled = true end
  if o.showName == nil then o.showName = true end
  if o.showDistance == nil then o.showDistance = true end
  return o
end

local function Forbidden(f)
  return f and f.IsForbidden and f:IsForbidden()
end

-- Blizzard art --------------------------------------------------------------------

local function Fade(uf, a)
  for _, r in ipairs({ uf.HealthBarsContainer, uf.name, uf.ClassificationFrame, uf.PlayerLevelDiffFrame, uf.LevelFrame }) do
    if r and r.SetAlpha then r:SetAlpha(a) end
  end
  -- The aggro flare's alpha is animated by Blizzard; its vertex alpha is not.
  for _, t in ipairs({ uf.aggroHighlightBase, uf.aggroHighlightAdditive }) do
    if t and t.SetVertexColor then pcall(t.SetVertexColor, t, 1, 1, 1, a) end
  end
end

-- Line shapes -----------------------------------------------------------------------

local function Line(frame, pool)
  local l = frame:CreateLine(nil, "OVERLAY")
  l:SetColorTexture(1, 1, 1, 1)
  pool[#pool + 1] = l
  return l
end

-- Draws a closed polygon of points (in px units) into frame's line pool.
local function Poly(frame, pool, start, pts, px, c, scale)
  local n = #pts
  for i = 1, n do
    local a, b = pts[i], pts[i % n + 1]
    local l = pool[start + i] or Line(frame, pool)
    l:ClearAllPoints()
    l:SetStartPoint("CENTER", frame, a[1] * px * scale, a[2] * px * scale)
    l:SetEndPoint("CENTER", frame, b[1] * px * scale, b[2] * px * scale)
    l:SetThickness(px * 1.4)
    l:SetVertexColor(c[1], c[2], c[3], 1)
    l:Show()
  end
  return start + n
end

local SHAPES = {
  player = { { 0, 6 }, { 6, 0 }, { 0, -6 }, { -6, 0 } },
  hostile = { { -6, 4 }, { 6, 4 }, { 0, -6 } },
  neutral = { { -5, 5 }, { 5, 5 }, { 5, -5 }, { -5, -5 } },
}
do
  local circ = {}
  for i = 0, 9 do
    local a = i / 10 * math.pi * 2
    circ[#circ + 1] = { math.cos(a) * 5.5, math.sin(a) * 5.5 }
  end
  SHAPES.friendly = circ
  local ring = {}
  for i = 0, 15 do
    local a = i / 16 * math.pi * 2
    ring[#ring + 1] = { math.cos(a) * 11, math.sin(a) * 11 }
  end
  SHAPES.ring = ring
end

-- Unit classification -------------------------------------------------------------------

local function Kind(unit)
  local c = ns.ReactionColor(unit)
  local shape
  if Plain(UnitIsPlayer(unit)) then shape = "player"
  elseif c == C.hostile then shape = "hostile"
  elseif c == C.friendly then shape = "friendly"
  else shape = "neutral" end
  local class = Plain(ns.Call(UnitClassification, unit))
  local boss = Plain(ns.Call(UnitIsBossMob, unit)) == true or class == "worldboss"
  return shape, c, class, boss
end

-- Widgets ----------------------------------------------------------------------------------

local function Corner(f, px, h, v)
  local a = f:CreateTexture(nil, "OVERLAY")
  local b = f:CreateTexture(nil, "OVERLAY")
  a:SetTexture(ns.WHITE); b:SetTexture(ns.WHITE)
  a:SetSize(px * 6, px); b:SetSize(px, px * 6)
  local p = v .. h
  a:SetPoint(p); b:SetPoint(p)
  return a, b
end

local function Build(plate, uf)
  local px = ns.Px(plate)
  local b = CreateFrame("Frame", nil, plate)
  b.plate, b.uf, b.px = plate, uf, px
  b:SetFrameLevel(uf:GetFrameLevel() + 5)
  local hc = uf.HealthBarsContainer
  b:SetPoint("BOTTOMLEFT", hc, "BOTTOMLEFT", 0, 0)
  b:SetPoint("BOTTOMRIGHT", hc, "BOTTOMRIGHT", 0, 0)
  b:SetHeight(px * 16)

  -- Type glyph left of the bracket.
  local g = CreateFrame("Frame", nil, b)
  g:SetSize(px * 14, px * 14)
  g:SetPoint("RIGHT", b, "LEFT", -px * 4, px * 4)
  g.lines = {}
  b.glyph = g
  b.pips = {}
  for i = 1, 2 do
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ns.WHITE)
    t:SetSize(px * 3, px * 3)
    t:SetRotation(math.pi / 4)
    t:SetPoint("BOTTOMLEFT", g, "TOPRIGHT", -px * (2 + (i - 1) * 4), -px * 2)
    t:Hide()
    b.pips[i] = t
  end

  -- Red pulse ring around the glyph.
  local ring = CreateFrame("Frame", nil, b)
  ring:SetAllPoints(g)
  ring.lines = {}
  Poly(ring, ring.lines, 0, SHAPES.ring, px, C.hostile, 1)
  local ag = ring:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local al = ag:CreateAnimation("Alpha")
  al:SetFromAlpha(1); al:SetToAlpha(0.15); al:SetDuration(0.55)
  ring.anim = ag
  ring:Hide()
  b.ring = ring

  -- Name and distance on one line, health line under them.
  local name = ns.Text(b, 10, C.text, "LEFT", "OUTLINE")
  ns.SetFont(name, 10, "OUTLINE", plate)
  name:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  name:SetPoint("TOPRIGHT", b, "TOPRIGHT", -px * 34, 0)
  b.name = name
  local dist = ns.Text(b, 9, C.dim, "RIGHT", "OUTLINE")
  ns.SetFont(dist, 9, "OUTLINE", plate)
  dist:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
  b.dist = dist

  local hp = CreateFrame("StatusBar", nil, b)
  hp:SetStatusBarTexture(ns.WHITE)
  hp:SetMinMaxValues(0, 100)
  hp:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, px * 2)
  hp:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, px * 2)
  hp:SetHeight(px * 2)
  local bg = hp:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(ns.WHITE)
  bg:SetAllPoints()
  bg:SetVertexColor(0, 0, 0, 0.55)
  b.hp = hp

  -- Fleet tag badge right of the bracket.
  local tag = CreateFrame("Frame", nil, b)
  tag:SetPoint("LEFT", b, "RIGHT", px * 6, px * 4)
  tag:SetSize(px * 30, px * 12)
  ns.Box(tag, { 0.02, 0.10, 0.12, 0.85 }, C.accent, px)
  local tt = ns.Text(tag, 8, C.accent, "CENTER", "OUTLINE")
  ns.SetFont(tt, 8, "OUTLINE", plate)
  tt:SetPoint("CENTER", 0, 0)
  tag.text = tt
  tag:Hide()
  b.tag = tag

  -- Target corners and lock ticks.
  local k = CreateFrame("Frame", nil, b)
  k.parts = {}
  for _, hv in ipairs({ { "LEFT", "TOP" }, { "RIGHT", "TOP" }, { "LEFT", "BOTTOM" }, { "RIGHT", "BOTTOM" } }) do
    local a1, a2 = Corner(k, px, hv[1], hv[2])
    k.parts[#k.parts + 1] = a1; k.parts[#k.parts + 1] = a2
  end
  k.ticks = {}
  for i = 1, TICKS do
    local t = k:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ns.WHITE)
    t:SetSize(px * 2, px * 3)
    k.ticks[i] = t
  end
  k:Hide()
  b.corners = k

  -- Keep the corners around the cast bar while it is up.
  local cb = uf.CastBarsContainer and uf.CastBarsContainer.castBar
  if cb and not Forbidden(cb) then
    b.cast = cb
    cb:HookScript("OnShow", function() if b.corners:IsShown() then b:AnchorCorners(b.lockOff or 0) end end)
    cb:HookScript("OnHide", function() if b.corners:IsShown() then b:AnchorCorners(b.lockOff or 0) end end)
  end

  function b:AnchorCorners(off)
    local p = self.px
    local o = (3 + off) * p
    k:ClearAllPoints()
    k:SetPoint("TOPLEFT", self.glyph, "TOPLEFT", -o, o)
    local bottom = (self.cast and self.cast:IsShown()) and self.cast or self.hp
    k:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", o, -o)
    local w = k:GetWidth()
    if w and w > 0 then
      for i, t in ipairs(k.ticks) do
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", k, "TOPLEFT", (i - 0.5) / TICKS * w, p * 2)
      end
    end
  end

  b:SetScript("OnUpdate", function(self, el)
    if not self.lockStart then return end
    local t = (GetTime() - self.lockStart) / LOCK_TIME
    local cl = C.title
    if t >= 1.6 then
      self.lockStart, self.lockOff = nil, 0
      self:AnchorCorners(0)
      for _, tk in ipairs(k.ticks) do tk:Hide() end
      return
    end
    local p = math.min(t, 1)
    self.lockOff = 10 * (1 - p) * (1 - p)
    self:AnchorCorners(self.lockOff)
    local lit = math.floor(p * TICKS + 0.001)
    local fade = t > 1 and (1.6 - t) / 0.6 or 1
    for i, tk in ipairs(k.ticks) do
      local c = i <= lit and C.accent or C.dim
      tk:SetVertexColor(c[1], c[2], c[3], (i <= lit and 1 or 0.35) * fade)
      tk:Show()
    end
    for _, part in ipairs(k.parts) do part:SetVertexColor(cl[1], cl[2], cl[3], 0.5 + 0.5 * p) end
  end)

  return b
end

-- Updates ----------------------------------------------------------------------------------

local function UpdateGlyph(b, unit)
  local shape, c, class, boss = Kind(unit)
  local key = shape .. tostring(class) .. tostring(boss) .. c[1] .. c[2] .. c[3]
  if key == b.kindKey then return end
  b.kindKey = key
  local g = b.glyph
  local n = Poly(g, g.lines, 0, SHAPES[shape], b.px, c, 1)
  if boss then n = Poly(g, g.lines, n, SHAPES[shape], b.px, c, 1.6) end
  for i = n + 1, #g.lines do g.lines[i]:Hide() end
  local elite = class == "elite" or class == "rareelite" or class == "worldboss"
  local rare = class == "rare" or class == "rareelite"
  local p1, p2 = b.pips[1], b.pips[2]
  local gold, silver = C.cap, C.hull
  if elite then p1:SetVertexColor(gold[1], gold[2], gold[3], 1) elseif rare then p1:SetVertexColor(silver[1], silver[2], silver[3], 1) end
  p1:SetShown(elite or rare)
  p2:SetVertexColor(silver[1], silver[2], silver[3], 1)
  p2:SetShown(elite and rare)
  b.hp:SetStatusBarColor(c[1], c[2], c[3], 0.95)
  b.name:SetTextColor(c[1], c[2], c[3], 1)
end

local function UpdateHealth(b, unit)
  b.hp:SetValue(ns.HealthPct100(unit))
  local dead = Plain(UnitIsDead(unit))
  if dead ~= nil then b:SetAlpha(dead and 0.45 or 1) end
end

local function UpdateName(b, unit)
  local o = Opts()
  b.name:SetShown(o.showName)
  if o.showName then ns.SetUnitName(b.name, unit) end
end

local function IsTarget(b, unit)
  local np = C_NamePlate.GetNamePlateForUnit("target")
  if np then return np == b.plate end
  return Plain(UnitIsUnit(unit, "target")) == true
end

local function UpdateTarget(b, unit, animate)
  local on = IsTarget(b, unit)
  if on == b.isTarget then return end
  b.isTarget = on
  local k = b.corners
  if on then
    local cl = C.title
    for _, part in ipairs(k.parts) do part:SetVertexColor(cl[1], cl[2], cl[3], 1) end
    k:Show()
    if animate then
      b.lockStart = GetTime()
    else
      b.lockStart, b.lockOff = nil, 0
      for _, tk in ipairs(k.ticks) do tk:Hide() end
    end
    b:AnchorCorners(animate and 10 or 0)
  else
    b.lockStart = nil
    k:Hide()
  end
end

-- On you: the unit is targeting you or you are on its threat table.
local function UpdateThreat(b, unit)
  local st = ns.Call(UnitThreatSituation, "player", unit)
  local known = not ns.issecret(st)
  local on = known and st ~= nil
  if not on then
    local t = ns.Call(UnitIsUnit, unit .. "target", "player")
    if ns.issecret(t) then
      if not known then return end -- nothing plain: keep the last state
    elseif t == true then
      on = true
    end
  end
  on = on and Plain(UnitCanAttack("player", unit)) ~= false or false
  if on == b.onYou then return end
  b.onYou = on
  b.ring:SetShown(on)
  if on then b.ring.anim:Play() else b.ring.anim:Stop() end
end

local KIND_LABEL = { target = "TGT", heal = "HEAL", focus = "FOC", assist = "AST", cc = "CC" }

local function UpdateTag(b, unit)
  local guid = Plain(UnitGUID(unit))
  if guid then b.guid = guid end
  local tags = ns.fleetTags
  local e = type(tags) == "table" and b.guid and tags[b.guid]
  if type(e) == "table" and (type(e.time) ~= "number" or GetTime() - e.time < TAG_TTL) then
    local kind = type(e.kind) == "string" and e.kind or "tag"
    b.tag.text:SetText(KIND_LABEL[kind:lower()] or kind:upper():sub(1, 4))
    b.tag:Show()
  else
    b.tag:Hide()
  end
end

local function UpdateDistance(b, unit)
  local o = Opts()
  b.dist:SetShown(o.showDistance)
  if o.showDistance then
    local _, txt = ns.Range(unit)
    b.dist:SetText(txt or "-")
  end
end

local function Full(b, unit)
  UpdateGlyph(b, unit)
  UpdateName(b, unit)
  UpdateHealth(b, unit)
  UpdateDistance(b, unit)
  UpdateThreat(b, unit)
  UpdateTag(b, unit)
  UpdateTarget(b, unit, false)
end

-- Plates -----------------------------------------------------------------------------------

local function Attach(unit)
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or Forbidden(plate) then return end
  local uf = plate.UnitFrame
  if not uf or Forbidden(uf) or not uf.HealthBarsContainer then return end
  local b = byPlate[plate]
  if not b then
    b = Build(plate, uf)
    byPlate[plate] = b
  end
  for u, other in pairs(active) do if other == b then active[u] = nil end end
  b.unit, b.kindKey, b.isTarget, b.onYou, b.guid = unit, nil, nil, nil, nil
  b.ring:Hide(); b.ring.anim:Stop()
  if not Opts().enabled or Plain(UnitIsUnit(unit, "player")) == true then
    Fade(uf, 1)
    b:Hide()
    return
  end
  active[unit] = b
  Fade(uf, 0)
  b:Show()
  Full(b, unit)
end

local function Detach(unit)
  local b = active[unit]
  if not b then return end
  active[unit] = nil
  b.unit, b.lockStart = nil, nil
  b.ring.anim:Stop()
  b:Hide()
end

function ns.BracketsRefresh()
  if not ns.bracketsLoaded then return end
  for _, b in pairs(byPlate) do
    if b.unit then active[b.unit] = nil end
    b:Hide()
    if not Forbidden(b.uf) then Fade(b.uf, 1) end
  end
  for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
    if u and not Forbidden(p) then Attach(u) end
  end
end

ns.RegisterModule(function()
  Opts()
  ns.bracketsLoaded = true
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_TARGET", "PLAYER_REGEN_ENABLED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", ns.Safe("brackets", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then return Attach(unit) end
    if event == "NAME_PLATE_UNIT_REMOVED" then return Detach(unit) end
    if event == "PLAYER_TARGET_CHANGED" then
      for u, b in pairs(active) do UpdateTarget(b, u, true) end
      return
    end
    if event == "PLAYER_REGEN_ENABLED" then
      -- Values that were secret in combat are plain again.
      for u, b in pairs(active) do b.kindKey = nil; Full(b, u) end
      return
    end
    local b = unit and active[unit]
    if not b then
      if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        for u, bb in pairs(active) do UpdateThreat(bb, u) end
      end
      return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then UpdateHealth(b, unit)
    elseif event == "UNIT_NAME_UPDATE" then UpdateName(b, unit)
    elseif event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" then UpdateGlyph(b, unit)
    else UpdateThreat(b, unit) end
  end))
  -- Distance, threat and fleet tags have no reliable events.
  C_Timer.NewTicker(0.4, ns.Safe("brackets tick", function()
    for u, b in pairs(active) do
      UpdateDistance(b, u)
      UpdateThreat(b, u)
      UpdateTag(b, u)
    end
  end))
  ns.BracketsRefresh()
end, "brackets")
