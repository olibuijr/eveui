-- Segmented arcs: a ring of small rotated bars, like EVE's HUD gauges.
-- Each segment has a dim "off" bar and a coloured "on" bar. For secret values
-- the game evaluates a per-segment step curve (UnitHealthPercent(unit, false,
-- curve) etc.) and the result drives the "on" bar's alpha, so addon code
-- never compares secret numbers. Angles: degrees, 0 = top, clockwise.
local ADDON, ns = ...
local sin, cos, rad, floor, pi = math.sin, math.cos, math.rad, math.floor, math.pi

local Arc = {}
Arc.__index = Arc

local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step

-- Curve that is 0 below t and 1 from t up.
local function StepCurve(t)
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
  local c = C_CurveUtil.CreateCurve()
  if stepType and c.SetType then pcall(c.SetType, c, stepType) end
  c:AddPoint(0, 0)
  c:AddPoint(math.max(t - 1e-4, 0), 0)
  c:AddPoint(t, 1)
  c:AddPoint(1, 1)
  return c
end

-- o: radius, thickness, from, to, segments, gap, color, x, y, off, bars
-- Each segment is a dim groove with a lit bar on top. The lit bar is shaded
-- across its thickness (a touch darker inside, brighter outside); depth comes
-- from the plate underneath (ns.Orb).
--
-- bars = true (health and power): each lit segment is a tiny StatusBar fed
-- the 0-100 percent straight from the game. Health and power are secret in
-- this client, and a StatusBar is how the game's own frames show secret
-- values: it fills or empties the segment itself, addon code never compares
-- the number. Other arcs (casts, speed) use plain numbers and alpha.
function ns.CreateArc(parent, o)
  local self = setmetatable({ on = {}, offs = {}, sbs = {}, th = {}, curves = {}, n = o.segments, bars = o.bars }, Arc)
  local span = o.to - o.from
  local len = (2 * pi * o.radius * math.abs(span) / 360) / o.segments - (o.gap or 2)
  len = math.max(floor(len + 0.5), 1)
  local off = o.off or ns.C.off
  for i = 1, o.segments do
    local a = rad(o.from + (i - 0.5) * span / o.segments)
    local x = floor(sin(a) * o.radius + (o.x or 0) + 0.5)
    local y = floor(cos(a) * o.radius + (o.y or 0) + 0.5)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetTexture(ns.WHITE)
    t:SetSize(len, o.thickness)
    t:SetPoint("CENTER", parent, "CENTER", x, y)
    t:SetRotation(-a)
    t:SetVertexColor(off[1], off[2], off[3], off[4])
    self.offs[i] = t
    self.th[i] = (i - 0.5) / o.segments
    if o.bars then
      local sb = CreateFrame("StatusBar", nil, parent)
      sb:SetSize(len, o.thickness)
      sb:SetPoint("CENTER", parent, "CENTER", x, y)
      sb:SetStatusBarTexture(ns.WHITE)
      -- Lit from this segment's threshold up: a 0.01-wide range, so the
      -- segment is either empty or full.
      local hi = self.th[i] * 100
      sb:SetMinMaxValues(hi - 0.01, hi)
      sb:SetValue(0)
      local fill = sb:GetStatusBarTexture()
      pcall(fill.SetRotation, fill, -a)
      self.sbs[i] = sb
      self.on[i] = fill
    else
      local on = parent:CreateTexture(nil, "ARTWORK")
      on:SetTexture(ns.WHITE)
      on:SetSize(len, o.thickness)
      on:SetPoint("CENTER", parent, "CENTER", x, y)
      on:SetRotation(-a)
      on:SetAlpha(0)
      self.on[i] = on
      self.curves[i] = StepCurve(self.th[i])
    end
  end
  self:SetColor(o.color or ns.C.hull)
  return self
end

function Arc:SetLit(i, v) self.on[i]:SetAlpha(v) end

-- Which path drove each gauge, for /eve check and EveUIDB.arcTrace.
ns.arcTrace = {}
local function Trace(key, secret, err)
  if not key then return end
  local t = ns.arcTrace[key] or { calls = 0, secret = 0 }
  ns.arcTrace[key] = t
  t.calls = t.calls + 1
  if secret then t.secret = t.secret + 1 end
  if err and not t.err then t.err = tostring(err):sub(1, 200) end
  if EveUIDB then EveUIDB.arcTrace = ns.arcTrace end
end

-- Percent 0-100, secret or plain (bars mode).
function Arc:SetPct(p, key)
  local err
  for _, sb in ipairs(self.sbs) do
    local ok, e = pcall(sb.SetValue, sb, p)
    if not ok then err = e end
  end
  Trace(key, ns.issecret(p), err)
end

-- Plain 0..1 value.
function Arc:SetValue(v)
  v = ns.Plain(v) or 0
  if self.bars then return self:SetPct(v * 100) end
  for i in ipairs(self.on) do self:SetLit(i, v >= self.th[i] and 1 or 0) end
end

local SCALE100 = CurveConstants and CurveConstants.ScaleTo100

-- Secret value: fn(curve) returns the game's evaluation of the curve.
function Arc:SetFrom(fn)
  if self.bars then
    if SCALE100 then
      local ok, p = pcall(fn, SCALE100)
      if ok and p ~= nil then self:SetPct(p) end
    end
    return
  end
  if not self.curves[1] then return end
  for i in ipairs(self.on) do
    pcall(function() self:SetLit(i, fn(self.curves[i])) end)
  end
end

function Arc:SetHealth(unit)
  local key = unit .. " health"
  -- Same call as the working "87%" text.
  if UnitHealthPercent and SCALE100 then
    local ok, p = pcall(UnitHealthPercent, unit, true, SCALE100)
    if ok and p ~= nil then return self:SetPct(p, key) end
    Trace(key, nil, p)
  end
  local h, m = ns.Plain(UnitHealth(unit)), ns.Plain(UnitHealthMax(unit))
  if h and m then self:SetPct(m > 0 and h / m * 100 or 0, key) end
end

-- UnitPowerPercent's argument order is not documented for this client; find
-- the form that takes a curve the first time it's used.
local powerForm
local FORMS = {
  function(u, c) return UnitPowerPercent(u, nil, false, c) end,
  function(u, c) return UnitPowerPercent(u, ns.Plain(UnitPowerType(u)), false, c) end,
  function(u, c) return UnitPowerPercent(u, c) end,
}
function ns.PowerCurve(unit, curve)
  if powerForm then return powerForm(unit, curve) end
  for _, fn in ipairs(FORMS) do
    local ok, v = pcall(fn, unit, curve)
    if ok and type(v) == "number" then powerForm = fn; return v end
  end
  return nil
end

function Arc:SetPower(unit)
  local key = unit .. " power"
  if SCALE100 then
    local ok, p = pcall(ns.PowerCurve, unit, SCALE100)
    if ok and p ~= nil then return self:SetPct(p, key) end
    Trace(key, nil, p)
  end
  local c, m = ns.Plain(UnitPower(unit)), ns.Plain(UnitPowerMax(unit))
  if c and m then self:SetPct(m > 0 and c / m * 100 or 0, key) end
end

-- Colour one lit segment.
function Arc:PaintSegment(i, c)
  ns.Lit(self.on[i], c, 0.72, 1.12)
end

function Arc:SetColor(c)
  if c == self.color then return end
  self.color = c
  for i in ipairs(self.on) do self:PaintSegment(i, c) end
end

function Arc:SetShown(shown)
  for i, t in ipairs(self.on) do
    t:SetShown(shown)
    self.offs[i]:SetShown(shown)
    if self.sbs[i] then self.sbs[i]:SetShown(shown) end
  end
end
