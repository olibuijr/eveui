local ADDON, ns = ...
-- Star map: an EVE-style map window of the current continent. Zones are star
-- systems placed at their centre on the continent, coloured by a "security
-- status" from their level range against yours, joined by jump lines where
-- their map rects touch. Shows where you are and the autopilot route (read
-- from ns.pilot). Drag to pan, wheel to zoom, click a system to open the
-- world map there. Only information is shown; nothing acts for the player.
local C = ns.C
local floor, min, max, sin, pi = math.floor, math.min, math.max, math.sin, math.pi

local Plain = ns.Plain
local function Try(fn, ...) if fn then return ns.Call(fn, ...) end end

local W, H, FOOT = 980, 660, 22
local VW, VH = W - 2, H - ns.HEADER - 1 - FOOT - 1
local ZMIN, ZMAX = 0.6, 8

-- EVE's security colours, 0.0 (red) to 1.0 (cyan).
local SEC = {
  [0] = { 0.94, 0.00, 0.00 }, { 0.84, 0.19, 0.00 }, { 0.94, 0.28, 0.00 }, { 0.94, 0.38, 0.00 },
  { 0.84, 0.47, 0.00 }, { 0.94, 0.94, 0.00 }, { 0.56, 0.94, 0.18 }, { 0.00, 0.94, 0.00 },
  { 0.00, 0.94, 0.28 }, { 0.28, 0.94, 0.75 }, { 0.18, 0.94, 0.94 },
}

-- Security 0..1 from the zone's level range: 0.5 at its middle, higher when
-- you out-level it, lower when it out-levels you.
local function Security(lo, hi)
  local lvl = Plain(UnitLevel("player"))
  if not (lvl and lo and hi and lo > 0) then return nil end
  local s = 0.5 + (lvl - (lo + hi) / 2) / 12
  return floor(max(0, min(1, s)) * 10 + 0.5) / 10
end
local function SecColor(s)
  if not s then return { C.dim[1], C.dim[2], C.dim[3] } end
  return SEC[floor(s * 10 + 0.5)] or SEC[5]
end

local function MapInfo(id) return id and Try(C_Map.GetMapInfo, id) end
local function Type(name) return Enum and Enum.UIMapType and Enum.UIMapType[name] end

-- The continent a map belongs to (or nil above continent level).
local function ContinentOf(map)
  local info, guard = MapInfo(map), 0
  local cont = Type("Continent") or 2
  while info and info.mapType and info.mapType > cont and info.parentMapID and info.parentMapID > 0 and guard < 8 do
    info = MapInfo(info.parentMapID)
    guard = guard + 1
  end
  if info and info.mapType == cont then return info.mapID end
end

local function Rect(map, top)
  local a, b, c, d = Try(C_Map.GetMapRectOnMap, map, top)
  a, b, c, d = Plain(a), Plain(b), Plain(c), Plain(d)
  if a and b and c and d and b > a and d > c then return a, b, c, d end
end

-- A continent-space point (0..1) for a position on any map, or nil.
local function OnContinent(map, x, y, cont)
  if not map then return end
  if map == cont then return x, y end
  local a, b, c, d = Rect(map, cont)
  if not a then return end
  if not x then return (a + b) / 2, (c + d) / 2 end
  return a + x * (b - a), c + y * (d - c)
end

-- Window -------------------------------------------------------------------------

local F, V, view
local nodes, byId, edges = {}, {}, {}
local linePool, routeLines, routePins = {}, {}, {}
local marker, starLayer, lineLayer, routeLayer, nodeLayer, pinLayer
local contLabel, routeText, scaleText
local continents, contIndex = {}, 1

local function Btn(parent, text, w, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 20, 16)
  ns.Box(b, { 0, 0, 0, 0.4 }, C.line)
  local l = ns.Text(b, 11, C.text)
  l:SetPoint("CENTER", 0, 1)
  l:SetText(text)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    ns.SetBoxBorder(self, C.accent)
    if tip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(tip); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function(self) ns.SetBoxBorder(self, C.line); GameTooltip:Hide() end)
  return b
end

local function Circle(parent, size, layer, sub, add)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
  t:SetTexture(ns.CIRCLE)
  t:SetSize(size, size)
  if add then t:SetBlendMode("ADD") end
  return t
end

local function Diamond(parent, size, layer, sub)
  local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 0)
  t:SetTexture(ns.WHITE)
  t:SetSize(size, size)
  t:SetRotation(pi / 4)
  return t
end

-- Procedural starfield: deterministic random dots plus two faint nebulae,
-- on a layer three viewports wide that drifts slowly with the pan.
local function Starfield()
  starLayer = CreateFrame("Frame", nil, V)
  starLayer:SetSize(VW * 3, VH * 3)
  starLayer:SetPoint("CENTER")
  local seed = 1337
  local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  end
  for _, n in ipairs({ { 0.45, 0.40, 0.30, 0.20, 0.55, 0.65 }, { 0.62, 0.58, 0.45, 0.35, 0.15, 0.40 } }) do
    local t = Circle(starLayer, VH * 1.4, "BACKGROUND", 1, true)
    t:SetPoint("CENTER", starLayer, "TOPLEFT", VW * 3 * n[1], -VH * 3 * n[2])
    t:SetVertexColor(n[3] * 0.25, n[4] * 0.25, n[5] * 0.25, 0.35)
  end
  for _ = 1, 420 do
    local s = rnd()
    local size = s > 0.97 and 3 or (s > 0.8 and 2 or 1)
    local t = starLayer:CreateTexture(nil, "BACKGROUND", nil, 2)
    t:SetTexture(ns.WHITE)
    t:SetSize(size, size)
    t:SetPoint("CENTER", starLayer, "TOPLEFT", rnd() * VW * 3, -rnd() * VH * 3)
    local tint = rnd()
    local a = 0.15 + rnd() * (size > 1 and 0.6 or 0.4)
    if tint > 0.85 then t:SetVertexColor(0.6, 0.8, 1, a)
    elseif tint > 0.75 then t:SetVertexColor(1, 0.85, 0.7, a)
    else t:SetVertexColor(0.85, 0.9, 1, a) end
  end
end

-- View transform -----------------------------------------------------------------

local function ToView(x, y)
  local s = view.s * view.z
  return (x - view.cx) * view.aspect * s + view.px, -(y - view.cy) * s + view.py
end

local function Place()
  if not view then return end
  for _, n in ipairs(nodes) do
    n:ClearAllPoints()
    n:SetPoint("CENTER", V, "CENTER", ToView(n.x, n.y))
  end
  for _, p in ipairs(routePins) do
    if p:IsShown() then p:ClearAllPoints(); p:SetPoint("CENTER", V, "CENTER", ToView(p.x, p.y)) end
  end
  if marker.x then marker:ClearAllPoints(); marker:SetPoint("CENTER", V, "CENTER", ToView(marker.x, marker.y)) end
  local ox = max(-VW, min(VW, view.px * 0.15))
  local oy = max(-VH, min(VH, view.py * 0.15))
  starLayer:ClearAllPoints()
  starLayer:SetPoint("CENTER", V, "CENTER", ox, oy)
  scaleText:SetFormattedText("ZOOM %.1fx", view.z)
end

-- Systems --------------------------------------------------------------------------

local function Line(layer, pool, i)
  local l = pool[i]
  if not l then
    l = layer:CreateLine(nil, "ARTWORK")
    pool[i] = l
  end
  l:Show()
  return l
end

local function QuestsIn(id)
  local out = {}
  local raw = C_QuestLog and Try(C_QuestLog.GetQuestsOnMap, id)
  if type(raw) ~= "table" then return out end
  local seen = {}
  for _, q in ipairs(raw) do
    local qid = Plain(q.questID)
    if qid and not seen[qid] then
      seen[qid] = true
      local log = ns.pilot and ns.pilot.log and ns.pilot.log[qid]
      local title = (log and log.title) or Plain(Try(C_QuestLog.GetTitleForQuestID, qid)) or ("Quest " .. qid)
      out[#out + 1] = { title = title, done = log and log.complete }
    end
  end
  return out
end

local OpenAt
local function NodeEnter(n)
  n.glow:SetSize(n.gs * 1.5, n.gs * 1.5)
  n.label:SetTextColor(unpack(C.title))
  GameTooltip:SetOwner(n, "ANCHOR_RIGHT", 6, 0)
  local c = n.col
  GameTooltip:AddLine(n.name, c[1], c[2], c[3])
  if n.sec then
    GameTooltip:AddDoubleLine(("Security %.1f"):format(n.sec), ("Level %d-%d"):format(n.lo, n.hi), 0.7, 0.75, 0.78, 0.86, 0.89, 0.91)
  else
    GameTooltip:AddLine("Security unknown", 0.5, 0.56, 0.59)
  end
  if n.city then GameTooltip:AddLine("Station (city)", 0.36, 0.78, 0.86) end
  if n.here then GameTooltip:AddLine("You are here", 0.36, 0.78, 0.86) end
  if n.steps then GameTooltip:AddLine("Autopilot route: step " .. table.concat(n.steps, ", "), 0.36, 0.78, 0.86) end
  local qs = QuestsIn(n.id)
  if #qs > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("QUESTS (%d)"):format(#qs), 0.5, 0.56, 0.59)
    for i, q in ipairs(qs) do
      if i > 8 then GameTooltip:AddLine(("+%d more"):format(#qs - 8), 0.5, 0.56, 0.59); break end
      if q.done then GameTooltip:AddLine(q.title .. "  (complete)", 0.35, 0.9, 0.45)
      else GameTooltip:AddLine(q.title, 0.86, 0.89, 0.91) end
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: open the world map here", 0.5, 0.56, 0.59)
  GameTooltip:Show()
end

local function NodeLeave(n)
  n.glow:SetSize(n.gs, n.gs)
  n.label:SetTextColor(unpack(n.steps and C.accent or C.text))
  GameTooltip:Hide()
end

local function MakeNode(i)
  local n = CreateFrame("Button", nil, nodeLayer)
  n:SetSize(18, 18)
  n.glow = Circle(n, 30, "ARTWORK", 0, true)
  n.glow:SetPoint("CENTER")
  n.ring = Circle(n, 44, "ARTWORK", 1, true)
  n.ring:SetPoint("CENTER")
  n.core = Circle(n, 8, "ARTWORK", 2)
  n.core:SetPoint("CENTER")
  n.spark = Circle(n, 3, "ARTWORK", 3, true)
  n.spark:SetPoint("CENTER")
  n.spark:SetVertexColor(1, 1, 1, 0.9)
  n.label = ns.Text(n, 10, C.text)
  n.label:SetFont(ns.FONT_BOLD, 10, "")
  n.label:SetPoint("TOP", n, "BOTTOM", 0, -1)
  n.secText = ns.Text(n, 9, C.dim, "LEFT")
  n.secText:SetPoint("LEFT", n.label, "RIGHT", 3, 0)
  n:SetScript("OnEnter", NodeEnter)
  n:SetScript("OnLeave", NodeLeave)
  n:SetScript("OnClick", function(self) OpenAt(self.id) end)
  n:EnableMouseWheel(true)
  n:SetScript("OnMouseWheel", function(_, d) V:GetScript("OnMouseWheel")(V, d) end)
  nodes[i] = n
  return n
end

local function Build(cont)
  for _, n in ipairs(nodes) do n:Hide() end
  for _, l in ipairs(linePool) do l:Hide() end
  local list = {}
  byId = {}
  local zone = Type("Zone") or 3
  local kids = Try(C_Map.GetMapChildrenInfo, cont, zone, false) or {}
  if #kids == 0 then
    for _, k in ipairs(Try(C_Map.GetMapChildrenInfo, cont, zone, true) or {}) do
      if k.parentMapID == cont then kids[#kids + 1] = k end
    end
  end
  for _, k in ipairs(kids) do
    local id = Plain(k.mapID)
    local a, b, c, d = id and Rect(id, cont)
    if a and (b - a) < 0.95 and not byId[id] then
      local lo, hi = Try(C_Map.GetMapLevels, id)
      lo, hi = Plain(lo), Plain(hi)
      local z = { id = id, name = Plain(k.name) or ("Map " .. id), x = (a + b) / 2, y = (c + d) / 2,
        r = { a, b, c, d }, lo = lo, hi = hi, city = Plain(Try(C_Map.IsCityMap, id)) == true }
      z.sec = Security(lo, hi)
      list[#list + 1] = z
      byId[id] = z
    end
  end

  -- Framing: fit the systems' bounding box into the viewport.
  local x0, x1, y0, y1 = 1, 0, 1, 0
  for _, z in ipairs(list) do
    x0, x1, y0, y1 = min(x0, z.x), max(x1, z.x), min(y0, z.y), max(y1, z.y)
  end
  if #list == 0 then x0, x1, y0, y1 = 0, 1, 0, 1 end
  local ww, wh = Try(C_Map.GetMapWorldSize, cont)
  ww, wh = Plain(ww), Plain(wh)
  local aspect = (ww and wh and wh > 0) and ww / wh or 1.5
  local bw, bh = max(x1 - x0, 0.05) * aspect, max(y1 - y0, 0.05)
  view = { cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, aspect = aspect, z = 1, px = 0, py = 0,
    s = min((VW - 160) / bw, (VH - 110) / bh) }

  -- Nodes.
  for i, z in ipairs(list) do
    local n = nodes[i] or MakeNode(i)
    for k, v in pairs(z) do n[k] = v end
    n.here, n.steps = nil, nil
    n.col = SecColor(z.sec)
    local c = n.col
    n.gs = z.city and 22 or 30
    n.glow:SetSize(n.gs, n.gs)
    n.glow:SetVertexColor(c[1], c[2], c[3], 0.45)
    n.core:SetSize(z.city and 6 or 8, z.city and 6 or 8)
    n.core:SetVertexColor(min(1, c[1] * 0.6 + 0.4), min(1, c[2] * 0.6 + 0.4), min(1, c[3] * 0.6 + 0.4), 1)
    n.ring:Hide()
    n.label:SetText(z.name:upper())
    n.label:SetTextColor(unpack(C.text))
    if z.sec then
      n.secText:SetText(("%.1f"):format(z.sec))
      n.secText:SetTextColor(c[1], c[2], c[3], 1)
    else
      n.secText:SetText("")
    end
    n:Show()
  end

  -- Jump lines: rects that touch or overlap, keeping each system's four
  -- nearest such neighbours; a system with none joins its nearest.
  local pad = 0.004
  local near = {}
  local function D2(a, b) local dx, dy = (a.x - b.x) * aspect, a.y - b.y; return dx * dx + dy * dy end
  for i = 1, #list do
    local a, cand = list[i], {}
    for j = 1, #list do
      local b = list[j]
      if i ~= j and a.r[1] <= b.r[2] + pad and b.r[1] <= a.r[2] + pad
        and a.r[3] <= b.r[4] + pad and b.r[3] <= a.r[4] + pad then
        cand[#cand + 1] = { j, D2(a, b) }
      end
    end
    if #cand == 0 then
      local best, bd
      for j = 1, #list do
        if j ~= i then
          local d = D2(a, list[j])
          if not bd or d < bd then best, bd = j, d end
        end
      end
      if best then cand[1] = { best, bd } end
    end
    table.sort(cand, function(p, q) return p[2] < q[2] end)
    near[i] = {}
    for k = 1, min(4, #cand) do near[i][cand[k][1]] = true end
  end
  edges = {}
  local nl = 0
  for i = 1, #list do
    for j in pairs(near[i]) do
      if i < j or not near[j][i] then
        nl = nl + 1
        local l = Line(lineLayer, linePool, nl)
        l:SetThickness(1.2)
        l:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.55)
        l:SetStartPoint("CENTER", nodes[i])
        l:SetEndPoint("CENTER", nodes[j])
        edges[#edges + 1] = { i, j }
      end
    end
  end
  F.count = #list
end

-- Player and autopilot route --------------------------------------------------------

local function Refresh()
  if not (F and F:IsShown() and view) then return end
  local cont = continents[contIndex]
  local info = MapInfo(cont)
  contLabel:SetText(((info and info.name) or "Unknown"):upper() .. ("  ·  %d SYSTEMS"):format(F.count or 0))

  -- You are here.
  for _, n in ipairs(nodes) do
    if n:IsShown() then n.here, n.steps = nil, nil; n.ring:Hide(); n.label:SetTextColor(unpack(C.text)) end
  end
  marker.x = nil
  marker:Hide()
  local pmap = Plain(Try(C_Map.GetBestMapForUnit, "player"))
  if pmap and ContinentOf(pmap) == cont then
    local pos = Try(C_Map.GetPlayerMapPosition, cont, "player")
    local x, y
    if pos then x, y = pos:GetXY(); x, y = Plain(x), Plain(y) end
    if x and (x ~= 0 or y ~= 0) then marker.x, marker.y = x, y; marker:Show() end
    local m, guard = pmap, 0
    while m and not byId[m] and guard < 8 do
      local mi = MapInfo(m)
      m = mi and mi.parentMapID
      guard = guard + 1
    end
    for _, n in ipairs(nodes) do
      if n:IsShown() and n.id == m then
        n.here = true
        n.ring:Show()
        n.ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
        if not marker.x then marker.x, marker.y = n.x, n.y; marker:Show() end
      end
    end
  end

  -- Route: the pilot's next steps (up to six), drawn through the systems.
  for _, p in ipairs(routePins) do p:Hide() end
  for _, l in ipairs(routeLines) do l:Hide() end
  local P = ns.pilot
  local list = (P and P.mapList) or {}
  local prev = marker.x and marker or nil
  local np, nl, off = 0, 0, 0
  for _, s in ipairs(list) do
    local x, y = OnContinent(s.map, s.x, s.y, cont)
    if x then
      np = np + 1
      local p = routePins[np]
      if not p then
        p = CreateFrame("Frame", nil, pinLayer)
        p:SetSize(16, 16)
        p.b = Diamond(p, 19, "OVERLAY", 0)
        p.b:SetPoint("CENTER")
        p.b:SetVertexColor(0, 0, 0, 0.85)
        p.d = Diamond(p, 15, "OVERLAY", 1)
        p.d:SetPoint("CENTER")
        p.n = ns.Text(p, 10, C.black)
        p.n:SetFont(ns.FONT_BOLD, 10, "")
        p.n:SetShadowOffset(0, 0)
        p.n:SetPoint("CENTER", 0, 0)
        routePins[np] = p
      end
      p.x, p.y = x, y
      local c = np == 1 and C.accent or { C.accent[1] * 0.6, C.accent[2] * 0.6, C.accent[3] * 0.6, 1 }
      p.d:SetVertexColor(c[1], c[2], c[3], 1)
      p.n:SetText(s.n or np)
      p:Show()
      if prev then
        for k = 1, 2 do
          nl = nl + 1
          local l = Line(routeLayer, routeLines, nl)
          l:SetStartPoint("CENTER", prev)
          l:SetEndPoint("CENTER", p)
          if k == 1 then
            l:SetThickness(7)
            l:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], np == 1 and 0.18 or 0.10)
          else
            l:SetThickness(2)
            l:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], np == 1 and 0.95 or 0.6)
          end
        end
      end
      prev = p
      -- Highlight the system the step lies in.
      local best, bd
      for _, n in ipairs(nodes) do
        if n:IsShown() and x >= n.r[1] and x <= n.r[2] and y >= n.r[3] and y <= n.r[4] then
          local d = (n.x - x) ^ 2 + (n.y - y) ^ 2
          if not bd or d < bd then best, bd = n, d end
        end
      end
      if best then
        best.steps = best.steps or {}
        table.insert(best.steps, s.n or np)
        best.label:SetTextColor(unpack(C.accent))
      end
    elseif s.map then
      off = off + 1
    end
  end

  local cur = P and P.Current and Try(P.Current)
  if cur then
    local where = (np == 0 and off > 0) and "  ·  route continues in another region" or ""
    if np == 0 and off == 0 then where = "  ·  no positions for the route yet" end
    routeText:SetText(("AUTOPILOT  %s  |cffdbe3e8%s|r%s"):format(
      cur.index and ("%d/%d"):format(cur.index, cur.total) or "AUTO", cur.text or "", where))
  else
    routeText:SetText("AUTOPILOT  no destination")
  end
  Place()
end

-- Pick a continent -------------------------------------------------------------------

local function Continents(home)
  local out, seen = {}, {}
  local info = MapInfo(home)
  local world = info and info.parentMapID
  if world and world > 0 then
    for _, k in ipairs(Try(C_Map.GetMapChildrenInfo, world, Type("Continent") or 2, false) or {}) do
      local id = Plain(k.mapID)
      if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
    end
  end
  if home and not seen[home] then table.insert(out, 1, home) end
  return out
end

local function Show(cont)
  continents = Continents(cont)
  contIndex = 1
  for i, id in ipairs(continents) do if id == cont then contIndex = i end end
  Build(continents[contIndex])
  Refresh()
end

local function Home()
  local pmap = Plain(Try(C_Map.GetBestMapForUnit, "player"))
  local cont = pmap and ContinentOf(pmap)
  if not cont then
    local fb = Plain(Try(C_Map.GetFallbackWorldMapID))
    local kids = fb and Try(C_Map.GetMapChildrenInfo, fb, Type("Continent") or 2, false)
    cont = kids and kids[1] and Plain(kids[1].mapID)
  end
  return cont
end

local function Cycle(d)
  if #continents == 0 then return end
  contIndex = (contIndex - 1 + d) % #continents + 1
  Build(continents[contIndex])
  Refresh()
end

-- World map ---------------------------------------------------------------------------

local pendingMap
function OpenAt(id)
  if InCombatLockdown() then
    pendingMap = id
    ns.Print("star map: the world map opens after combat.")
    return
  end
  F:Hide()
  if not OpenWorldMap and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_WorldMap") end
  if OpenWorldMap then
    pcall(OpenWorldMap, id)
  elseif WorldMapFrame then
    pcall(ShowUIPanel, WorldMapFrame)
    pcall(WorldMapFrame.SetMapID, WorldMapFrame, id)
  end
end

-- Build the window ----------------------------------------------------------------------

local function Create()
  F = ns.CreatePanel("EveUIStarMap", ns.root, "Star Map", W, H)
  F:SetFrameStrata("HIGH")
  F:SetToplevel(true)
  F:SetClampedToScreen(true)
  F:SetMovable(true)
  F:EnableMouse(true)
  F:Hide()
  local sp = EveUIDB.starmap and EveUIDB.starmap.pos
  if sp then F:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4]) else F:SetPoint("CENTER", UIParent, "CENTER", 0, 30) end
  tinsert(UISpecialFrames, "EveUIStarMap")

  local drag = CreateFrame("Frame", nil, F)
  drag:SetPoint("TOPLEFT", 1, -1)
  drag:SetPoint("TOPRIGHT", -1, -1)
  drag:SetHeight(ns.HEADER - 1)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() F:StartMoving() end)
  drag:SetScript("OnDragStop", function()
    F:StopMovingOrSizing()
    local p, _, rp, x, y = F:GetPoint()
    EveUIDB.starmap = EveUIDB.starmap or {}
    EveUIDB.starmap.pos = { p, rp, floor(x + 0.5), floor(y + 0.5) }
  end)

  contLabel = ns.Text(F, 11, C.accent, "LEFT")
  contLabel:SetPoint("LEFT", F.title, "RIGHT", 10, 0)

  local close = Btn(drag, "×", 20, nil, function() F:Hide() end)
  close:SetPoint("TOPRIGHT", F, "TOPRIGHT", -3, -3)
  local nextB = Btn(drag, ">", 20, "Next region", function() Cycle(1) end)
  nextB:SetPoint("RIGHT", close, "LEFT", -8, 0)
  local prevB = Btn(drag, "<", 20, "Previous region", function() Cycle(-1) end)
  prevB:SetPoint("RIGHT", nextB, "LEFT", -2, 0)
  local homeB = Btn(drag, "HOME", 44, "Your region, centred on you", function()
    local cont = Home()
    if cont then Show(cont) end
    if marker.x and view then
      local x, y = ToView(marker.x, marker.y)
      view.px, view.py = view.px - x, view.py - y
      Place()
    end
  end)
  homeB:SetPoint("RIGHT", prevB, "LEFT", -6, 0)
  local fitB = Btn(drag, "FIT", 34, "Reset pan and zoom", function()
    if view then view.z, view.px, view.py = 1, 0, 0; Place() end
  end)
  fitB:SetPoint("RIGHT", homeB, "LEFT", -2, 0)
  scaleText = ns.Text(drag, 10, C.dim, "RIGHT")
  scaleText:SetPoint("RIGHT", fitB, "LEFT", -8, 0)

  -- Viewport.
  V = CreateFrame("Frame", nil, F)
  V:SetPoint("TOPLEFT", 1, -ns.HEADER - 1)
  V:SetPoint("BOTTOMRIGHT", -1, FOOT + 1)
  V:SetClipsChildren(true)
  local bg = V:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetTexture(ns.WHITE)
  bg:SetAllPoints()
  ns.Gradient(bg, { 0.005, 0.008, 0.012, 1 }, { 0.02, 0.035, 0.05, 1 })
  Starfield()
  local function Layer(lvl)
    local l = CreateFrame("Frame", nil, V)
    l:SetAllPoints()
    l:SetFrameLevel(V:GetFrameLevel() + lvl)
    return l
  end
  lineLayer, routeLayer, nodeLayer, pinLayer = Layer(2), Layer(3), Layer(4), Layer(8)

  -- You-are-here marker: a pulse, a dark rim and a bright diamond.
  marker = CreateFrame("Frame", nil, pinLayer)
  marker:SetSize(12, 12)
  marker:SetFrameLevel(pinLayer:GetFrameLevel() + 2)
  marker.pulse = Circle(marker, 12, "OVERLAY", 0, true)
  marker.pulse:SetPoint("CENTER")
  marker.rim = Diamond(marker, 13, "OVERLAY", 1)
  marker.rim:SetPoint("CENTER")
  marker.rim:SetVertexColor(0, 0, 0, 0.9)
  marker.dot = Diamond(marker, 9, "OVERLAY", 2)
  marker.dot:SetPoint("CENTER")
  marker.you = ns.Text(marker, 9, C.accent)
  marker.you:SetPoint("BOTTOM", marker, "TOP", 0, 6)
  marker.you:SetText("YOU")
  marker:Hide()

  -- Footer: security legend, route summary.
  local fl = F:CreateTexture(nil, "ARTWORK")
  fl:SetColorTexture(unpack(C.line))
  fl:SetPoint("BOTTOMLEFT", 1, FOOT)
  fl:SetPoint("BOTTOMRIGHT", -1, FOOT)
  fl:SetHeight(1)
  local secL = ns.Text(F, 9, C.dim, "LEFT")
  secL:SetPoint("BOTTOMLEFT", 8, 6)
  secL:SetText("SEC")
  local last = secL
  for i = 10, 0, -1 do
    local sw = F:CreateTexture(nil, "ARTWORK")
    sw:SetColorTexture(SEC[i][1], SEC[i][2], SEC[i][3], 1)
    sw:SetSize(10, 6)
    sw:SetPoint("LEFT", last, "RIGHT", last == secL and 5 or 1, 0)
    last = sw
  end
  local hint = ns.Text(F, 9, C.dim, "LEFT")
  hint:SetPoint("LEFT", last, "RIGHT", 10, 0)
  hint:SetText("DRAG PAN  ·  WHEEL ZOOM  ·  CLICK SYSTEM FOR WORLD MAP")
  routeText = ns.Text(F, 10, C.accent, "RIGHT")
  routeText:SetPoint("BOTTOMRIGHT", -8, 6)
  routeText:SetPoint("LEFT", hint, "RIGHT", 12, 0)

  -- Pan and zoom.
  V:EnableMouse(true)
  V:EnableMouseWheel(true)
  local dragging, lx, ly
  local function Cursor()
    local x, y = GetCursorPosition()
    local s = V:GetEffectiveScale()
    return x / s, y / s
  end
  V:SetScript("OnMouseDown", function(_, b)
    if b == "LeftButton" then dragging = true; lx, ly = Cursor() end
  end)
  V:SetScript("OnMouseUp", function() dragging = false end)
  V:SetScript("OnMouseWheel", function(_, d)
    if not view then return end
    local z2 = max(ZMIN, min(ZMAX, view.z * (d > 0 and 1.2 or 1 / 1.2)))
    local cx, cy = Cursor()
    local vx, vy = V:GetCenter()
    local rx, ry = cx - vx, cy - vy
    local k = z2 / view.z
    view.px, view.py = rx - (rx - view.px) * k, ry - (ry - view.py) * k
    view.z = z2
    Place()
  end)

  local SafeRefresh = ns.Safe("starmap refresh", Refresh)
  local t, acc = 0, 0
  F:SetScript("OnUpdate", function(_, el)
    t, acc = t + el, acc + el
    if dragging and view then
      if not IsMouseButtonDown("LeftButton") then dragging = false
      else
        local x, y = Cursor()
        if x ~= lx or y ~= ly then
          view.px, view.py = view.px + x - lx, view.py + y - ly
          lx, ly = x, y
          Place()
        end
      end
    end
    -- Pulse.
    local ph = (t % 1.6) / 1.6
    local s = 12 + ph * 34
    marker.pulse:SetSize(s, s)
    marker.pulse:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.55 * (1 - ph))
    marker.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8 + 0.2 * sin(t * 6))
    if acc > 1 then
      acc = 0
      SafeRefresh()
    end
  end)
  F:SetScript("OnHide", function() dragging = false end)

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  ev:RegisterEvent("PLAYER_LEVEL_UP")
  ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_REGEN_ENABLED" then
      if pendingMap then local id = pendingMap; pendingMap = nil; OpenAt(id) end
    elseif F:IsShown() then
      local cont = continents[contIndex]
      if cont then ns.Safe("starmap build", Build)(cont); ns.Safe("starmap refresh", Refresh)() end
    end
  end)
end

function ns.ToggleStarMap()
  if not ns.ModuleOn("starmap") then return ns.Print("star map is turned off in settings.") end
  if not F then Create() end
  if F:IsShown() then F:Hide(); return end
  local cont = Home()
  if not cont then return ns.Print("star map: no map for this place.") end
  F:Show()
  ns.Safe("starmap open", Show)(cont)
end

ns.RegisterModule(function()
  EveUIDB.starmap = EveUIDB.starmap or {}
end, "starmap")
