-- D-Scan: a round radar (fleet, nameplate units, autopilot target) and an EVE
-- directional scanner window that sweeps a cone and lists what it saw.
--
-- Where blips come from:
--  * Group members: UnitPosition (world yards). The game returns nothing in
--    instances, so they drop off the radar there.
--  * Nameplate units: addons get no world position for them (UnitPosition is
--    group only), so a blip uses the distance band from ns.Range and the
--    bearing of its nameplate on screen: the horizontal offset from the screen
--    centre turned into an angle with the camera field of view. That is the
--    bearing relative to the camera, taken as the way the character faces.
--    Approximate; units with no plate (off screen) have no blip. In combat
--    ns.Range can't range attackable units, so they sit on the rim, faded.
--  * Autopilot target: ns.pilot.Current() and ns.pilot.Delta().
-- Display only: nothing here targets, moves or clicks for the player.
local ADDON, ns = ...
local C = ns.C
local sin, cos, atan, sqrt, abs, pi, floor, min, max = math.sin, math.cos, math.atan, math.sqrt, math.abs, math.pi,
  math.floor, math.min, math.max
local atan2 = math.atan2 or atan2
local Plain, issecret = ns.Plain, ns.issecret

local R = 96                 -- scope radius in pixels
local SCALE = 45             -- yards at the scope rim
local K = R / SCALE
local RINGS = { 10, 20, 40 }
local BAND_YD = { [1] = 6, [2] = 19, [3] = 36 } -- ns.Range bands as yards
local ANGLES = { 5, 15, 45, 90, 180, 360 }
local RANGES = { 10, 20, 40, 0 }                 -- 0 = no limit
local MAX_PLATES = 40

local function Norm(a) return (a + pi) % (2 * pi) - pi end
local function Facing() return Plain(ns.Call(GetPlayerFacing)) end

local function Kind(unit)
  if Plain(UnitIsDead(unit)) then return "Wreck" end
  local lvl = Plain(UnitLevel(unit))
  local s = (lvl and lvl > 0) and ("Lv" .. lvl) or "Lv??"
  local class = Plain(UnitClassification(unit))
  if class == "elite" or class == "rareelite" or class == "worldboss" then s = s .. "+" end
  local kind
  if Plain(UnitIsPlayer(unit)) then kind = Plain(UnitClass(unit)) else kind = Plain(UnitCreatureType(unit)) end
  return kind and (s .. " " .. kind) or s
end

local function Standing(col)
  if col == C.hostile then return "Hostile" elseif col == C.neutral then return "Neutral" end
  return "Friendly"
end

ns.RegisterModule(function()
  EveUIDB.dscan = EveUIDB.dscan or {}
  local cfg = EveUIDB.dscan
  cfg.angle = cfg.angle or 6
  cfg.range = cfg.range or 4

  -- Contacts ------------------------------------------------------------------------
  -- Each contact: unit, dist (yards, nil = unknown), bearing (radians CCW from
  -- north; nameplates use facing or 0), exact (world position), label.

  local active, ranges, tick = {}, {}, 0
  local pool, n = {}, 0
  local function Add(unit, dist, bearing, exact, label)
    n = n + 1
    local c = pool[n] or {}
    pool[n] = c
    c.unit, c.dist, c.bearing, c.exact, c.label = unit, dist, bearing, exact, label
    return c
  end

  local function Pos(unit)
    local x, y, _, map = ns.Call(UnitPosition, unit)
    x, y, map = Plain(x), Plain(y), Plain(map)
    if type(x) == "number" and type(y) == "number" then return x, y, map end
  end

  local tanHalf = 1
  local function UpdateFov()
    local fov = tonumber(ns.Call(GetCVar, "cameraFov") or "") or 90
    tanHalf = math.tan(math.rad(min(max(fov, 30), 150)) / 2)
  end
  UpdateFov()

  -- Bearing of a nameplate relative to the camera (radians CCW, 0 = ahead).
  local function PlateAngle(token)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local plate = ns.Call(C_NamePlate.GetNamePlateForUnit, token)
    if not plate then return end
    local px = Plain((ns.Call(plate.GetCenter, plate)))
    local ps = Plain(plate:GetEffectiveScale())
    local wx = Plain((WorldFrame:GetCenter()))
    local ws = WorldFrame:GetEffectiveScale()
    local half = WorldFrame:GetWidth() * ws / 2
    if not (px and ps and wx) or half <= 0 then return end
    local f = (px * ps - wx * ws) / half
    f = min(max(f, -1.5), 1.5)
    return -atan(f * tanHalf)
  end

  local function RangeOf(token)
    local r = ranges[token]
    if not r or tick % 5 == 0 then
      local band, label = ns.Range(token)
      r = r or {}
      r[1], r[2] = band, label
      ranges[token] = r
    end
    return r[1], r[2]
  end

  local pilotCur, pilotAt = nil, 0
  local function Pilot()
    local P = ns.pilot
    if not (P and P.Current and P.Delta) or EveUIDB.pilotMode == "off" then return end
    local now = GetTime()
    if now - pilotAt > 2 then
      pilotAt = now
      pilotCur = ns.Call(P.Current)
    end
    local cur = pilotCur
    if not (cur and cur.x) then return end
    local d, bearing = ns.Call(P.Delta, cur.map, cur.x, cur.y)
    if type(d) ~= "number" or type(bearing) ~= "number" then return end
    return d, bearing, cur
  end

  local groupUnits = {}
  local function Gather()
    n = 0
    tick = tick + 1
    local facing = Facing()
    local px, py, pmap = Pos("player")
    -- Group members by world position.
    wipe(groupUnits)
    if px and IsInGroup() then
      local raid = IsInRaid()
      local count = raid and 40 or 4
      for i = 1, count do
        local u = (raid and "raid" or "party") .. i
        if UnitExists(u) and not Plain(UnitIsUnit(u, "player")) then
          local ux, uy, umap = Pos(u)
          if ux and umap == pmap then
            local dx, dy = ux - px, uy - py
            local d = sqrt(dx * dx + dy * dy)
            Add(u, d, atan2(dy, dx), true, ("%d yd"):format(d))
            groupUnits[#groupUnits + 1] = u
          end
        end
      end
    end
    -- Nameplate units by range band and on-screen bearing.
    for token in pairs(active) do
      if UnitExists(token) and not Plain(UnitIsUnit(token, "player")) then
        -- Group members already placed by world position.
        local dup = #groupUnits > 0 and (Plain(UnitInParty(token)) or Plain(UnitInRaid(token)))
        if not dup then
          local rel = PlateAngle(token)
          if rel then
            local band, label = RangeOf(token)
            Add(token, BAND_YD[band], (facing or 0) + rel, false, label)
          end
        end
      end
    end
    return facing
  end

  -- Radar panel -----------------------------------------------------------------------

  local W, H = 2 * R + 24, ns.HEADER + 2 * R + 34
  local f = ns.CreatePanel("EveUIDScanRadar", ns.root, "D-Scan", W, H)
  ns.Mover(f, { key = "dscan", label = "D-Scan", point = "BOTTOMRIGHT", x = -366, y = 16 })

  local function TextButton(parent, size, w, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, ns.HEADER - 5)
    ns.Box(b, C.header, C.border)
    b.text = ns.Text(b, size, C.text)
    b.text:SetAllPoints()
    b.text:SetText(text)
    b:SetScript("OnEnter", function(s) s.text:SetTextColor(unpack(C.accent)) end)
    b:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(s.on and C.accent or C.text)) end)
    function b:Select(on)
      self.on = on
      ns.SetBoxBorder(self, on and C.accent or C.border)
      self.text:SetTextColor(unpack(on and C.accent or C.text))
    end
    return b
  end

  local scanB = TextButton(f, 10, 40, "SCAN")
  scanB:SetPoint("TOPRIGHT", -4, -3)
  local modeB = TextButton(f, 10, 40, "")
  modeB:SetPoint("RIGHT", scanB, "LEFT", -4, 0)
  local function ModeText() modeB.text:SetText(cfg.facingUp and "HDG" or "N-UP") end
  ModeText()
  modeB:SetScript("OnClick", function() cfg.facingUp = not cfg.facingUp; ModeText() end)
  modeB:SetScript("OnEnter", function(s)
    s.text:SetTextColor(unpack(C.accent))
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText("Radar orientation")
    GameTooltip:AddLine("N-UP: north at the top. HDG: your heading at the top.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  modeB:HookScript("OnLeave", function() GameTooltip:Hide() end)

  local scope = CreateFrame("Frame", nil, f)
  scope:SetSize(2 * R, 2 * R)
  scope:SetPoint("TOP", 0, -(ns.HEADER + 10))
  local orb = ns.Orb(scope, 2 * R, 0.55, "BACKGROUND", 0)
  orb:SetPoint("CENTER")

  local function NewLine(layer, sub, thick, col, a)
    local l = scope:CreateLine(nil, layer, nil, sub)
    l:SetThickness(thick)
    l:SetColorTexture(col[1], col[2], col[3], a or col[4] or 1)
    return l
  end
  local function Seg(l, x1, y1, x2, y2)
    l:SetStartPoint("CENTER", scope, x1, y1)
    l:SetEndPoint("CENTER", scope, x2, y2)
  end

  -- Range rings with labels, and faint crosshairs.
  for _, yd in ipairs(RINGS) do
    local rp, SEG = yd * K, 48
    for i = 0, SEG - 1 do
      local a1, a2 = i / SEG * 2 * pi, (i + 1) / SEG * 2 * pi
      Seg(NewLine("BORDER", 0, 1, C.line, 0.55), sin(a1) * rp, cos(a1) * rp, sin(a2) * rp, cos(a2) * rp)
    end
    local t = ns.Text(scope, 9, C.dim)
    t:SetPoint("CENTER", scope, "CENTER", rp * 0.72 + 6, rp * 0.72 + 2)
    t:SetText(yd)
  end
  Seg(NewLine("BORDER", 0, 1, C.line, 0.3), 0, -R + 2, 0, R - 2)
  Seg(NewLine("BORDER", 0, 1, C.line, 0.3), -R + 2, 0, R - 2, 0)

  local heading = NewLine("ARTWORK", 1, 1, C.accent, 0.5)
  local north = ns.Text(scope, 10, C.accent)
  north:SetText("N")
  local me = scope:CreateTexture(nil, "OVERLAY", nil, 3)
  me:SetTexture(ns.WHITE)
  me:SetSize(5, 5)
  me:SetPoint("CENTER")
  me:SetRotation(pi / 4)
  me:SetVertexColor(unpack(C.title))

  local count = ns.Text(f, 10, C.dim, "LEFT")
  count:SetPoint("BOTTOMLEFT", 8, 6)
  local hdg = ns.Text(f, 10, C.dim, "RIGHT")
  hdg:SetPoint("BOTTOMRIGHT", -8, 6)

  local blips = {}
  local function Blip(i)
    local b = blips[i]
    if not b then
      b = scope:CreateTexture(nil, "OVERLAY", nil, 1)
      b:SetTexture(ns.CIRCLE)
      b:SetSize(7, 7)
      blips[i] = b
    end
    return b
  end

  local wp = scope:CreateTexture(nil, "OVERLAY", nil, 2)
  wp:SetTexture(ns.WHITE)
  wp:SetSize(8, 8)
  wp:SetRotation(pi / 4)
  local wpText = ns.Text(scope, 9, C.accent)

  local function Place(region, a, r)
    region:ClearAllPoints()
    region:SetPoint("CENTER", scope, "CENTER", -sin(a) * r, cos(a) * r)
  end

  -- Radar "up" as a world bearing: north, or the heading when known.
  local function Up(facing) return (cfg.facingUp and facing) or 0 end

  local function DrawRadar()
    if not f:IsVisible() then return end
    local facing = Gather()
    local up = Up(facing)
    -- Heading line and north marker.
    if facing then
      local a = facing - up
      Seg(heading, 0, 0, -sin(a) * (R - 4), cos(a) * (R - 4))
      heading:Show()
      hdg:SetFormattedText("HDG %03d", floor((360 - math.deg(facing)) % 360 + 0.5) % 360)
    else
      heading:Hide()
      hdg:SetText("NO HDG")
    end
    Place(north, -up, R - 9)

    for i = 1, n do
      local c = pool[i]
      local b = Blip(i)
      local col = ns.ReactionColor(c.unit)
      local dead = Plain(UnitIsDead(c.unit))
      local r, alpha = R - 4, 0.45
      if c.dist then
        r = min(c.dist * K, R - 4)
        alpha = c.exact and 1 or 0.85
      end
      if dead then alpha = 0.35 end
      b:SetVertexColor(col[1], col[2], col[3], alpha)
      local sz = Plain(UnitIsUnit(c.unit, "target")) and 10 or 7
      b:SetSize(sz, sz)
      Place(b, c.bearing - up, r)
      b:Show()
    end
    for i = n + 1, #blips do blips[i]:Hide() end
    count:SetText(n == 1 and "1 contact" or (n .. " contacts"))

    local d, bearing = Pilot()
    if d then
      local a = bearing - up
      local r = min(d * K, R - 5)
      Place(wp, a, r)
      wp:SetVertexColor(unpack(C.accent))
      wp:Show()
      if d * K > R - 5 then
        wpText:ClearAllPoints()
        wpText:SetPoint("CENTER", scope, "CENTER", -sin(a) * (R - 18), cos(a) * (R - 18))
        wpText:SetFormattedText("%d", d)
        wpText:Show()
      else
        wpText:Hide()
      end
    else
      wp:Hide(); wpText:Hide()
    end
  end

  -- Scan cone animation ---------------------------------------------------------------

  local spokes = {}
  local anim = CreateFrame("Frame", nil, scope)
  anim:Hide()
  local GROW, HOLD, FADE = 0.45, 0.5, 0.8
  local coneA, coneHalf, coneLen, coneN, el = 0, 0, R, 0, 0

  local function DrawCone(len, alpha)
    for i = 1, coneN do
      local s = spokes[i]
      local a = coneA - coneHalf + (coneN > 1 and (i - 1) / (coneN - 1) * 2 * coneHalf or 0)
      Seg(s, 0, 0, -sin(a) * len, cos(a) * len)
      local edge = coneHalf < pi and (i == 1 or i == coneN)
      s:SetAlpha(edge and min(1, alpha * 3) or alpha)
      s:Show()
    end
  end

  anim:SetScript("OnUpdate", function(self, e)
    el = el + e
    if el < GROW then
      DrawCone(max(coneLen * el / GROW, 1), 0.25)
    elseif el < GROW + HOLD then
      DrawCone(coneLen, 0.25)
    elseif el < GROW + HOLD + FADE then
      DrawCone(coneLen, 0.25 * (1 - (el - GROW - HOLD) / FADE))
    else
      for _, s in ipairs(spokes) do s:Hide() end
      self:Hide()
    end
  end)

  local function Sweep(facing, angleDeg, rangeYd)
    coneA = (facing or 0) - Up(facing)
    coneHalf = math.rad(angleDeg) / 2
    coneLen = rangeYd > 0 and min(rangeYd * K, R - 2) or R - 2
    coneN = max(2, floor(angleDeg / 2) + 1)
    if angleDeg < 4 then coneN = 2 end
    for i = #spokes + 1, coneN do
      local l = NewLine("ARTWORK", 2, 3, C.accent)
      pcall(l.SetBlendMode, l, "ADD")
      spokes[i] = l
    end
    for i = 1, #spokes do
      spokes[i]:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
      spokes[i]:Hide()
    end
    el = 0
    anim:Show()
  end

  -- D-Scan window ----------------------------------------------------------------------

  local ROWS, ROW_H, DW = 12, 18, 410
  local CTRL = ns.HEADER + 4
  local TOP = CTRL + 2 * 22 + 22
  local win = ns.CreatePanel("EveUIDScan", ns.root, "Directional Scanner", DW, TOP + ROWS * ROW_H + 24)
  win:SetFrameStrata("MEDIUM")
  win:EnableMouse(true)
  win:Hide()
  tinsert(UISpecialFrames, "EveUIDScan")

  local close = CreateFrame("Button", nil, win)
  close:SetSize(ns.HEADER - 2, ns.HEADER - 2)
  close:SetPoint("TOPRIGHT", -2, -1)
  close.text = ns.Text(close, 14, C.dim)
  close.text:SetAllPoints()
  close.text:SetText("×")
  close:SetScript("OnEnter", function(s) s.text:SetTextColor(unpack(C.hostile)) end)
  close:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(C.dim)) end)
  close:SetScript("OnClick", function() win:Hide() end)

  local function Group(label, y, values, key, fmt)
    local t = ns.Text(win, 11, C.dim, "LEFT")
    t:SetPoint("TOPLEFT", 10, -(y + 3))
    t:SetText(label)
    local btns = {}
    local function Sync() for i, b in ipairs(btns) do b:Select(i == cfg[key]) end end
    for i, v in ipairs(values) do
      local b = TextButton(win, 10, 40, fmt(v))
      b:SetPoint("TOPLEFT", 64 + (i - 1) * 44, -y)
      b:SetScript("OnClick", function() cfg[key] = i; Sync() end)
      btns[i] = b
    end
    Sync()
  end
  Group("ANGLE", CTRL, ANGLES, "angle", function(v) return v .. "°" end)
  Group("RANGE", CTRL + 22, RANGES, "range", function(v) return v > 0 and (v .. " yd") or "MAX" end)

  local go = TextButton(win, 12, 64, "SCAN")
  go:SetHeight(38)
  go:SetPoint("TOPRIGHT", -10, -CTRL)
  go.text:SetFont(ns.FONT_BOLD, 12, "")
  go:Select(true)
  go:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(C.accent)) end)

  local COLS = { { "NAME", 22 }, { "TYPE", 162 }, { "DIST", 272 }, { "STANDING", 326 } }
  for _, col in ipairs(COLS) do
    local t = ns.Text(win, 11, C.dim, "LEFT")
    t:SetPoint("TOPLEFT", col[2], -(TOP - 17))
    t:SetText(col[1])
  end
  local sep = win:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(unpack(C.line))
  sep:SetPoint("TOPLEFT", 1, -(TOP - 2))
  sep:SetPoint("TOPRIGHT", -1, -(TOP - 2))
  sep:SetHeight(1)

  local rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, win)
    r:SetSize(DW - 2, ROW_H)
    r:SetPoint("TOPLEFT", 1, -(TOP + (i - 1) * ROW_H))
    if i % 2 == 0 then
      local zebra = r:CreateTexture(nil, "BACKGROUND")
      zebra:SetAllPoints()
      zebra:SetColorTexture(1, 1, 1, 0.025)
    end
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexture(ns.WHITE)
    r.icon:SetSize(8, 8)
    r.icon:SetPoint("LEFT", 9, 0)
    r.name = ns.Text(r, 12, C.text, "LEFT")
    r.name:SetPoint("LEFT", 21, 0); r.name:SetWidth(136)
    r.kind = ns.Text(r, 12, C.dim, "LEFT")
    r.kind:SetPoint("LEFT", 161, 0); r.kind:SetWidth(106)
    r.dist = ns.Text(r, 12, C.text, "LEFT")
    r.dist:SetPoint("LEFT", 271, 0); r.dist:SetWidth(52)
    r.stand = ns.Text(r, 12, C.text, "LEFT")
    r.stand:SetPoint("LEFT", 325, 0); r.stand:SetWidth(DW - 330)
    r:Hide()
    rows[i] = r
  end

  local status = ns.Text(win, 11, C.dim, "LEFT")
  status:SetPoint("BOTTOMLEFT", 10, 6)
  status:SetText("Press SCAN.")

  local results, offset = {}, 0
  local function DrawResults()
    offset = max(0, min(offset, #results - ROWS))
    for i, r in ipairs(rows) do
      local e = results[i + offset]
      if e then
        local c = e.color
        r.icon:SetVertexColor(c[1], c[2], c[3], e.dead and 0.4 or 1)
        r.icon:SetRotation(e.diamond and pi / 4 or 0)
        r.name:SetText(e.name)
        r.name:SetTextColor(unpack(e.dead and C.dim or c))
        r.kind:SetText(e.kind)
        r.dist:SetText(e.label)
        r.stand:SetText(e.stand)
        r.stand:SetTextColor(c[1], c[2], c[3])
        r:Show()
      else
        r:Hide()
      end
    end
  end
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; DrawResults() end)

  local function Scan()
    local facing = Gather()
    local angle, range = ANGLES[cfg.angle] or 360, RANGES[cfg.range] or 0
    local half = math.rad(angle) / 2
    wipe(results)
    offset = 0
    local function InCone(bearing, dist)
      if angle < 360 and abs(Norm(bearing - (facing or 0))) > half then return false end
      if range > 0 and dist and dist > range then return false end
      return true
    end
    for i = 1, n do
      local c = pool[i]
      if InCone(c.bearing, c.dist) then
        local u = c.unit
        local name = UnitName(u)
        if not issecret(name) and not name then name = "?" end
        local col = ns.ReactionColor(u)
        local grouped = c.exact and (Plain(UnitInParty(u)) or Plain(UnitInRaid(u)))
        results[#results + 1] = { name = name, kind = Kind(u), label = c.label or "-", color = col,
          stand = grouped and "Fleet" or Standing(col), dead = Plain(UnitIsDead(u)), sort = c.dist or 999,
          diamond = Plain(UnitIsPlayer(u)) }
      end
    end
    local d, bearing, cur = Pilot()
    if d and InCone(bearing, d) then
      results[#results + 1] = { name = cur.text or "Waypoint", kind = cur.kind and cur.kind:upper() or "Waypoint",
        label = ("%d yd"):format(d), color = C.accent, stand = "Autopilot", sort = d, diamond = true }
    end
    table.sort(results, function(a, b) return a.sort < b.sort end)
    DrawResults()
    status:SetFormattedText("%d result%s  ·  %s, %s  ·  %s%s", #results, #results == 1 and "" or "s",
      angle .. "°", range > 0 and (range .. " yd") or "max range", date and date("%H:%M:%S") or "",
      facing and "" or "  ·  no heading, cone points north")
    Sweep(facing, angle, range)
  end
  go:SetScript("OnClick", function() ns.Safe("dscan scan", Scan)() end)

  -- Open the window beside the radar, on the side with more room.
  function ns.ToggleDScan()
    if win:IsShown() then win:Hide() return end
    win:ClearAllPoints()
    local x = f:GetCenter()
    local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    if x and x > sw / 2 then
      win:SetPoint("TOPRIGHT", f, "TOPLEFT", -6, 0)
    else
      win:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
    end
    win:SetClampedToScreen(true)
    win:Show()
  end
  scanB:SetScript("OnClick", function() ns.ToggleDScan() end)

  -- Events -------------------------------------------------------------------------------

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  pcall(ev.RegisterEvent, ev, "CVAR_UPDATE")
  ev:SetScript("OnEvent", function(_, event, unit)
    if event == "CVAR_UPDATE" then UpdateFov() return end
    if type(unit) ~= "string" then return end
    active[unit] = event == "NAME_PLATE_UNIT_ADDED" or nil
    if not active[unit] then ranges[unit] = nil end
  end)
  for i = 1, MAX_PLATES do
    if UnitExists("nameplate" .. i) then active["nameplate" .. i] = true end
  end

  ns.Every(0.1, "dscan radar", DrawRadar)
end, "dscan")
