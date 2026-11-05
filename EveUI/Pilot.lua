-- Autopilot: quest waypoints with an arrow on screen, a pointer on the HUD
-- rim, a minimap pin and numbered route pins on the world map.
--
-- Targets come from the AI guide (Guide.lua, written by the pilot service on
-- titan from EveUIDB.pilotState) or, without one, from the game's own quest
-- positions: the nearest unfinished objective or turn-in.
--
-- Only information is shown; nothing moves, targets or clicks for the player.
local ADDON, ns = ...
local C = ns.C
local sin, cos, sqrt, abs, floor, pi = math.sin, math.cos, math.sqrt, math.abs, math.floor, math.pi
local atan2 = math.atan2 or atan2

local P = { log = {}, order = {} }
ns.pilot = P
function P.Refresh() end -- replaced when the module loads

local function Plain(v) return ns.Plain(v) end
local function Try(fn, ...) if fn then return ns.Call(fn, ...) end end

-- Geometry ---------------------------------------------------------------------
-- World coordinates: x points north, y points west (yards). Bearings and the
-- player's facing are radians counter-clockwise from north.

local function PlayerPos()
  local map = Plain(Try(C_Map.GetBestMapForUnit, "player"))
  if not map then return end
  local pos = Try(C_Map.GetPlayerMapPosition, map, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  x, y = Plain(x), Plain(y)
  if not x or (x == 0 and y == 0) then return end
  return map, x, y
end

local function World(map, x, y)
  if not (map and x and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local inst, w = Try(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if not w then return end
  local wx, wy = w:GetXY()
  return inst, wx, wy
end

-- Distance (yards) and bearing from the player to a map position.
local function Delta(map, x, y)
  local pm, px, py = PlayerPos()
  if not pm then return end
  local i1, ax, ay = World(pm, px, py)
  local i2, bx, by = World(map, x, y)
  if not (i1 and i2) or i1 ~= i2 then return end
  local dx, dy = bx - ax, by - ay
  return sqrt(dx * dx + dy * dy), atan2(dy, dx), dx, dy
end
P.Delta = Delta

local function Facing() return Plain(GetPlayerFacing and GetPlayerFacing()) end

-- Quest log --------------------------------------------------------------------

local function Objectives(id, index)
  local out = {}
  local list = C_QuestLog and Try(C_QuestLog.GetQuestObjectives, id)
  if type(list) == "table" then
    for _, o in ipairs(list) do
      out[#out + 1] = { text = Plain(o.text) or "", done = Plain(o.finished) == true, type = Plain(o.type),
        have = Plain(o.numFulfilled), need = Plain(o.numRequired) }
    end
  elseif index and GetNumQuestLeaderBoards then
    for j = 1, (Plain(GetNumQuestLeaderBoards(index)) or 0) do
      local text, kind, done = GetQuestLogLeaderBoard(j, index)
      out[#out + 1] = { text = Plain(text) or "", done = Plain(done) == true or Plain(done) == 1, type = Plain(kind) }
    end
  end
  return out
end

local function IsDone(id)
  if not id then return false end
  if EveUIDB.pilotTurnedIn and EveUIDB.pilotTurnedIn[id] then return true end
  local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
  return Plain(Try(f, id)) == true
end

function P.ReadLog()
  local log, order = {}, {}
  local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and Plain(C_QuestLog.GetNumQuestLogEntries())
  if n then
    for i = 1, n do
      local info = Try(C_QuestLog.GetInfo, i)
      local id = info and Plain(info.questID)
      if id and id > 0 and not Plain(info.isHeader) and not Plain(info.isHidden) then
        local complete = Plain(Try(C_QuestLog.IsComplete, id))
        if complete == nil then complete = Plain(info.isComplete) end
        log[id] = { id = id, title = Plain(info.title) or ("Quest " .. id), level = Plain(info.level),
          complete = complete == true or complete == 1, objectives = Objectives(id, i), index = i }
        order[#order + 1] = id
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, (Plain(GetNumQuestLogEntries()) or 0) do
      local title, level, _, header, _, complete, _, id = GetQuestLogTitle(i)
      id = Plain(id)
      if id and not Plain(header) then
        log[id] = { id = id, title = Plain(title), level = Plain(level), complete = Plain(complete) == 1,
          objectives = Objectives(id, i), index = i }
        order[#order + 1] = id
      end
    end
  end
  local byTitle = {}
  for id, q in pairs(log) do if q.title then byTitle[q.title:lower()] = id end end
  P.log, P.order, P.byTitle = log, order, byTitle
  return log
end

-- Where the game says a quest's objective (or turn-in) is.
local onMap = {}
local function QuestsOnMap(map)
  local c = onMap[map]
  if c and GetTime() - c.t < 2 then return c.list end
  local list = {}
  local raw = C_QuestLog and Try(C_QuestLog.GetQuestsOnMap, map)
  if type(raw) == "table" then
    for _, q in ipairs(raw) do
      local id, x, y = Plain(q.questID), Plain(q.x), Plain(q.y)
      if id and x then list[id] = { x, y } end
    end
  end
  onMap[map] = { t = GetTime(), list = list }
  return list
end

function P.QuestPOI(id)
  local pm = PlayerPos()
  if pm then
    local q = QuestsOnMap(pm)[id]
    if q then return pm, q[1], q[2] end
  end
  if C_QuestLog and C_QuestLog.GetNextWaypoint then
    local m, x, y = Try(C_QuestLog.GetNextWaypoint, id)
    m, x, y = Plain(m), Plain(x), Plain(y)
    if m and x then return m, x, y end
  end
  if pm and QuestPOIGetIconInfo then
    local _, x, y = Try(QuestPOIGetIconInfo, id)
    x, y = Plain(x), Plain(y)
    if x and x > 0 then return pm, x, y end
  end
  if pm and C_TaskQuest and C_TaskQuest.GetQuestLocation then
    local x, y = Try(C_TaskQuest.GetQuestLocation, id, pm)
    x, y = Plain(x), Plain(y)
    if x then return pm, x, y end
  end
end

-- State export (read by the pilot service after /reload) ----------------------

local function Continent(map)
  local info = map and Try(C_Map.GetMapInfo, map)
  local guard = 0
  while info and info.mapType and Enum and Enum.UIMapType and info.mapType > Enum.UIMapType.Continent
    and info.parentMapID and info.parentMapID > 0 and guard < 8 do
    info = Try(C_Map.GetMapInfo, info.parentMapID)
    guard = guard + 1
  end
  return info
end

function P.Export()
  local map, x, y = PlayerPos()
  local mi = map and Try(C_Map.GetMapInfo, map)
  local cont = Continent(map)
  local zones = {}
  if cont and C_Map.GetMapChildrenInfo and Enum and Enum.UIMapType then
    local kids = Try(C_Map.GetMapChildrenInfo, cont.mapID, Enum.UIMapType.Zone, true)
    for _, z in ipairs(kids or {}) do zones[#zones + 1] = { id = z.mapID, name = z.name } end
  end
  if map then zones[#zones + 1] = { id = map, name = mi and mi.name } end
  local quests = {}
  for _, id in ipairs(P.order) do
    local q = P.log[id]
    local m, qx, qy = P.QuestPOI(id)
    quests[#quests + 1] = { id = id, title = q.title, level = q.level, complete = q.complete,
      objectives = q.objectives, poi = m and { map = m, x = qx, y = qy } or nil }
  end
  local done = {}
  for id in pairs(EveUIDB.pilotTurnedIn or {}) do done[#done + 1] = id end
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  EveUIDB.pilotState = {
    v = 1, time = date("%Y-%m-%d %H:%M:%S"), epoch = time(),
    char = (Plain(UnitName("player")) or "?") .. "-" .. (GetRealmName() or "?"),
    level = Plain(UnitLevel("player")), class = class, race = race,
    faction = Plain(UnitFactionGroup("player")), money = Plain(GetMoney()),
    map = map and { id = map, name = mi and mi.name, x = x, y = y } or nil,
    continent = cont and { id = cont.mapID, name = cont.name } or nil,
    zones = zones, quests = quests, turnedIn = done,
    guide = EveUI_GUIDE and EveUI_GUIDE.id or nil, step = P.stepIndex,
    goal = EveUIDB.pilotGoal,
  }
end

-- Guide steps ------------------------------------------------------------------

local function Guide() return EveUIDB.pilotMode ~= "auto" and EveUI_GUIDE or nil end

local function Marks()
  local g = EveUI_GUIDE
  local id = g and g.id or "none"
  local m = EveUIDB.pilotMarks
  if not m or m.id ~= id then
    m = { id = id, skip = {}, reached = {} }
    EveUIDB.pilotMarks = m
  end
  return m
end

local function StepDone(s, i)
  local m = Marks()
  if m.skip[i] then return true end
  local q = s.quest
  local inLog = q and P.log[q]
  if s.kind == "accept" then
    -- The planner's quest id can be off; the title is the fallback.
    return inLog ~= nil or IsDone(q) or (s.title and P.byTitle and P.byTitle[s.title:lower()] ~= nil) or false
  end
  if s.kind == "turnin" then return IsDone(q) end
  if q then
    if IsDone(q) then return true end
    if inLog then
      if s.obj and inLog.objectives[s.obj] then return inLog.objectives[s.obj].done end
      if s.kind ~= "goto" then return inLog.complete end
    end
  end
  return m.reached[i] == true
end

-- The current target: { text, sub, map, x, y, kind, index, total, source }.
function P.Current()
  local g = Guide()
  if g and g.steps and #g.steps > 0 then
    for i, s in ipairs(g.steps) do
      if not StepDone(s, i) then
        local map, x, y = s.map, s.x, s.y
        if not x and s.quest and P.log[s.quest] then map, x, y = P.QuestPOI(s.quest) end
        local q = s.quest and P.log[s.quest]
        return { text = s.text, sub = s.note or (q and q.title), map = map, x = x, y = y, kind = s.kind,
          index = i, total = #g.steps, source = "AI", radius = s.radius }
      end
    end
  end
  -- Auto: nearest quest position the game knows.
  local best, bestD
  for _, id in ipairs(P.order) do
    local q = P.log[id]
    local m, x, y = P.QuestPOI(id)
    if m then
      local d = Delta(m, x, y) or 1e9
      if not bestD or d < bestD then
        local obj
        for _, o in ipairs(q.objectives) do if not o.done then obj = o.text; break end end
        best = { text = q.complete and "Turn in" or (obj or "Objective"), sub = q.title, map = m, x = x, y = y,
          kind = q.complete and "turnin" or "objective", source = "AUTO" }
        bestD = d
      end
    end
  end
  return best
end

function P.Skip(dir)
  local g = EveUI_GUIDE
  if not (g and g.steps) then return ns.Print("no AI guide loaded; autopilot follows the nearest quest.") end
  local m = Marks()
  if dir > 0 then
    local cur = P.Current()
    if cur and cur.index then m.skip[cur.index] = true end
  else
    local last
    for i in pairs(m.skip) do if not last or i > last then last = i end end
    if last then m.skip[last] = nil end
  end
  P.Refresh()
end

-- Drawing helpers ----------------------------------------------------------------

-- A chevron made of two bars meeting at the tip; rotates as a whole.
-- angle: radians counter-clockwise, 0 = pointing up.
local function Chevron(parent, size, thick, layer, sub)
  local o = { size = size, bars = {} }
  local L = size * 0.62
  for k = 1, 2 do
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetTexture(ns.WHITE)
    t:SetSize(L, thick)
    o.bars[k] = t
  end
  local th = math.rad(42)
  -- Bar centres relative to the chevron centre, pointing up.
  local tipY = size * 0.32
  o.local_ = {}
  for k, sgn in ipairs({ -1, 1 }) do
    local dx, dy = sgn * sin(th), -cos(th)
    o.local_[k] = { dx * L / 2, tipY + dy * L / 2, atan2(dy, dx) }
  end
  function o:Set(angle, rel, x, y)
    local ca, sa = cos(angle), sin(angle)
    for k, t in ipairs(self.bars) do
      local lx, ly, la = unpack(self.local_[k])
      t:ClearAllPoints()
      t:SetPoint("CENTER", rel, "CENTER", x + lx * ca - ly * sa, y + lx * sa + ly * ca)
      t:SetRotation(la + angle)
    end
  end
  function o:Color(c, a)
    for _, t in ipairs(self.bars) do ns.Lit(t, { c[1], c[2], c[3], a or 1 }, 0.6, 1.2) end
  end
  function o:Shown(v) for _, t in ipairs(self.bars) do t:SetShown(v) end end
  return o
end
P.Chevron = Chevron

local function Diamond(parent, size, layer, sub)
  local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 0)
  t:SetTexture(ns.WHITE)
  t:SetSize(size, size)
  t:SetRotation(pi / 4)
  return t
end

local KIND = { accept = "ACCEPT", turnin = "TURN IN", kill = "KILL", loot = "LOOT", use = "USE", talk = "TALK",
  ["goto"] = "GO TO", fly = "FLY", hearth = "HEARTH", train = "TRAIN", vendor = "VENDOR", objective = "OBJECTIVE" }

-- Module -----------------------------------------------------------------------

ns.MOVER_LABELS.pilot = "Autopilot"

ns.RegisterModule(function()
  EveUIDB.pilotTurnedIn = EveUIDB.pilotTurnedIn or {}

  -- Panel: big arrow on the left, step, quest, distance and ETA on the right.
  local f = CreateFrame("Frame", "EveUIPilot", ns.root)
  f:SetSize(300, 86)
  ns.Box(f, C.panel)
  ns.Movable(f, "pilot", "BOTTOM", "BOTTOM", 0, 430)
  local mark = f:CreateTexture(nil, "ARTWORK")
  mark:SetColorTexture(unpack(C.accent))
  mark:SetPoint("TOPLEFT", 1, -1); mark:SetPoint("BOTTOMLEFT", 1, 1); mark:SetWidth(2)

  local dial = CreateFrame("Frame", nil, f)
  dial:SetSize(76, 76)
  dial:SetPoint("LEFT", 6, 0)
  local orb = ns.Orb(dial, 64, 0.7, "BACKGROUND", 0, { 0.05, 0.10, 0.14 })
  orb:SetPoint("CENTER")
  local shadow = Chevron(dial, 40, 9, "ARTWORK", 0)
  for _, t in ipairs(shadow.bars) do t:SetVertexColor(0, 0, 0, 0.55) end
  local arrow = Chevron(dial, 40, 9, "ARTWORK", 2)
  local arrow2 = Chevron(dial, 26, 6, "ARTWORK", 3)

  local head = ns.Text(f, 10, C.accent, "LEFT")
  head:SetPoint("TOPLEFT", dial, "TOPRIGHT", 6, -4)
  local step = ns.Text(f, 10, C.dim, "RIGHT")
  step:SetPoint("TOPRIGHT", -8, -6)
  local title = ns.Text(f, 14, C.title, "LEFT")
  title:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
  title:SetPoint("RIGHT", -8, 0)
  local sub = ns.Text(f, 11, C.text, "LEFT")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetPoint("RIGHT", -8, 0)
  local dist = ns.Text(f, 13, C.accent, "LEFT")
  dist:SetPoint("BOTTOMLEFT", dial, "BOTTOMRIGHT", 6, 6)
  local hint = ns.Text(f, 10, C.dim, "RIGHT")
  hint:SetPoint("BOTTOMRIGHT", -30, 8)

  local function Btn(text, x, onClick, tip)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(18, 18)
    b:SetPoint("BOTTOMRIGHT", x, 6)
    ns.Box(b, { 0, 0, 0, 0.4 }, C.line)
    local l = ns.Text(b, 12, C.text)
    l:SetPoint("CENTER", 0, 1)
    l:SetText(text)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
      ns.SetBoxBorder(self, C.accent)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) ns.SetBoxBorder(self, C.line); GameTooltip:Hide() end)
  end
  Btn(">", -6, function() P.Skip(1) end, "Skip this step")
  Btn("<", -26, function() P.Skip(-1) end, "Back one step")
  hint:ClearAllPoints()
  hint:SetPoint("BOTTOMRIGHT", -48, 9)

  -- HUD rim pointer: a chevron orbiting the HUD, top = straight ahead.
  local hudPtr, hudDist
  if ns.hud and ns.hudVisual then
    hudPtr = Chevron(ns.hud, 22, 5, "OVERLAY", 5)
    hudDist = ns.Text(ns.hud, 11, C.accent)
  end

  -- Minimap: diamond on the target, chevron on the edge when it's off the map.
  local mm = Minimap and CreateFrame("Frame", nil, Minimap)
  local mmDot, mmRing, mmEdge
  if mm then
    mm:SetAllPoints()
    mm:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    mmRing = Diamond(mm, 14, "OVERLAY", 0)
    mmRing:SetVertexColor(0, 0, 0, 0.7)
    mmDot = Diamond(mm, 10, "OVERLAY", 1)
    mmEdge = Chevron(mm, 16, 4, "OVERLAY", 2)
  end
  local pulse = 0

  -- World map: numbered pins for the next steps.
  local pins = {}
  local function MapPins(list)
    local wm = WorldMapFrame
    local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
    if not (child and wm:IsShown()) then
      for _, p in ipairs(pins) do p:Hide() end
      return
    end
    local shown = Plain(wm:GetMapID())
    local scale = Try(wm.ScrollContainer.GetCanvasScale, wm.ScrollContainer) or 1
    local cw, ch = child:GetWidth(), child:GetHeight()
    for i = 1, 6 do
      local s = list[i]
      local p = pins[i]
      if not p then
        p = CreateFrame("Frame", nil, child)
        p:SetFrameLevel(child:GetFrameLevel() + 50)
        p.d = Diamond(p, 1, "OVERLAY", 1)
        p.d:SetAllPoints()
        p.b = Diamond(p, 1, "OVERLAY", 0)
        p.b:SetVertexColor(0, 0, 0, 0.8)
        p.n = ns.Text(p, 12, C.black)
        p.n:SetPoint("CENTER")
        pins[i] = p
      end
      local mx, my
      if s and s.x then
        if s.map == shown then
          mx, my = s.x, s.y
        else
          local inst, wx, wy = World(s.map, s.x, s.y)
          if inst and C_Map.GetMapPosFromWorldPos then
            local _, pos = Try(C_Map.GetMapPosFromWorldPos, inst, CreateVector2D(wx, wy), shown)
            if pos then mx, my = pos:GetXY() end
          end
        end
      end
      if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
        local size = 22 / scale
        p:SetSize(size, size)
        p.b:ClearAllPoints()
        p.b:SetPoint("CENTER")
        p.b:SetSize(size + 4 / scale, size + 4 / scale)
        p:ClearAllPoints()
        p:SetPoint("CENTER", child, "TOPLEFT", mx * cw, -my * ch)
        local c = i == 1 and C.accent or C.dim
        p.d:SetVertexColor(c[1], c[2], c[3], 1)
        ns.SetFont(p.n, math.max(floor(11 / scale + 0.5), 6), "")
        p.n:SetText(s.n or i)
        p:Show()
      else
        p:Hide()
      end
    end
  end

  local cur
  function P.Refresh()
    P.ReadLog()
    cur = P.Current()
    P.stepIndex = cur and cur.index
    if not cur then
      f:SetAlpha(0.6)
      head:SetText("AUTOPILOT")
      title:SetText("No destination")
      sub:SetText(EveUI_GUIDE_FILE and "Accept a quest, or wait for the pilot service" or
        "Restart the game once to load AI guides")
      step:SetText(""); dist:SetText(""); hint:SetText("")
      return
    end
    f:SetAlpha(1)
    head:SetText((KIND[cur.kind] or "OBJECTIVE") .. (cur.source == "AI" and "" or "  ·  NEAREST"))
    title:SetText(cur.text or "")
    sub:SetText(cur.sub or "")
    step:SetText(cur.index and ("%d / %d  AI"):format(cur.index, cur.total) or "AUTO")
    -- Next steps for the world map.
    local list = {}
    local g = Guide()
    if cur.index and g then
      for i = cur.index, #g.steps do
        local s = g.steps[i]
        if not StepDone(s, i) then
          local m, x, y = s.map, s.x, s.y
          if not x and s.quest and P.log[s.quest] then m, x, y = P.QuestPOI(s.quest) end
          list[#list + 1] = { map = m, x = x, y = y, n = i }
          if #list >= 6 then break end
        end
      end
    elseif cur.x then
      list[1] = { map = cur.map, x = cur.x, y = cur.y, n = 1 }
    end
    P.mapList = list
  end

  local function Hide()
    arrow:Shown(false); arrow2:Shown(false); shadow:Shown(false)
    if hudPtr then hudPtr:Shown(false); hudDist:SetText("") end
    if mm then mmDot:Hide(); mmRing:Hide(); mmEdge:Shown(false) end
  end

  local acc = 0
  local function Tick(_, el)
    acc = acc + el
    pulse = pulse + el
    if acc < 0.04 then return end
    acc = 0
    if EveUIDB.pilotMode == "off" or not cur or not cur.x then
      Hide()
      if cur and not cur.x then dist:SetText("no position"); hint:SetText("") end
      return
    end
    local d, bearing, dx, dy = Delta(cur.map, cur.x, cur.y)
    if not d then Hide(); dist:SetText("other zone"); return end

    -- Arrival: goto steps finish inside their radius; others just say so.
    local radius = cur.radius or 20
    if d <= radius and cur.index and (cur.kind == "goto" or cur.kind == "fly" or not cur.kind) then
      Marks().reached[cur.index] = true
      P.Refresh()
      return
    end

    local facing = Facing()
    local rel = facing and (bearing - facing) or bearing
    local aligned = facing and abs(((rel + pi) % (2 * pi)) - pi) < 0.26
    local col = d <= radius and C.heal or (aligned and C.title or C.accent)

    arrow:Shown(true); arrow2:Shown(true); shadow:Shown(true)
    shadow:Set(rel, dial, 2, -3)
    arrow:Set(rel, dial, 0, 0)
    arrow2:Set(rel, dial, -sin(rel) * -10, cos(rel) * -10)
    arrow:Color(col); arrow2:Color(col, 0.55)

    local spd = Plain(GetUnitSpeed("player")) or 0
    local eta = d / ((spd > 0.5) and spd or 7)
    local etaText = eta >= 60 and ("%dm %02ds"):format(eta / 60, eta % 60) or ("%ds"):format(eta)
    dist:SetFormattedText("%d yd  |cff808c93·|r  %s", d, etaText)
    if d <= radius then dist:SetText("ARRIVED") end
    hint:SetText(facing and (aligned and "ON COURSE" or "") or "N-UP")

    if hudPtr then
      local R = 124
      hudPtr:Shown(true)
      hudPtr:Set(rel, ns.hud, -sin(rel) * R, cos(rel) * R)
      hudPtr:Color(col)
      hudDist:ClearAllPoints()
      hudDist:SetPoint("CENTER", ns.hud, "CENTER", -sin(rel) * (R + 18), cos(rel) * (R + 18))
      hudDist:SetFormattedText("%d", d)
    end

    if mm then
      local w = Minimap:GetWidth()
      local zoom = Plain(Minimap:GetZoom()) or 0
      local indoor = IsIndoors and Plain(IsIndoors())
      local OUT = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
      local IN = { [0] = 300, 240, 180, 120, 80, 50 }
      local diameter = (indoor and IN[zoom] or OUT[zoom]) or 400
      local k = w / diameter
      local ex, ny = -dy * k, dx * k
      if GetCVar("rotateMinimap") == "1" and facing then
        local b = -facing
        ex, ny = ex * cos(b) - ny * sin(b), ex * sin(b) + ny * cos(b)
      end
      local half = w / 2 - 7
      local m = math.max(abs(ex), abs(ny))
      if m <= half then
        mmEdge:Shown(false)
        local s = 1 + 0.15 * sin(pulse * 5)
        mmDot:SetSize(10 * s, 10 * s); mmRing:SetSize(14 * s, 14 * s)
        mmDot:ClearAllPoints(); mmDot:SetPoint("CENTER", Minimap, "CENTER", ex, ny)
        mmRing:ClearAllPoints(); mmRing:SetPoint("CENTER", Minimap, "CENTER", ex, ny)
        mmDot:SetVertexColor(col[1], col[2], col[3], 1)
        mmDot:Show(); mmRing:Show()
      else
        mmDot:Hide(); mmRing:Hide()
        local s = half / m
        mmEdge:Shown(true)
        mmEdge:Set(atan2(ny, ex) - pi / 2, Minimap, ex * s, ny * s)
        mmEdge:Color(col)
      end
    end
  end

  f:SetScript("OnUpdate", function(self, el)
    local ok, err = pcall(Tick, self, el)
    if not ok and not P.tickErr then P.tickErr = true; ns.Safe("pilot tick", error)(err) end
  end)

  -- Refresh on quest and zone changes (debounced), and keep the export fresh.
  local pending
  local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
      pending = nil
      ns.Safe("pilot refresh", P.Refresh)()
      ns.Safe("pilot export", P.Export)()
    end)
  end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP",
    "PLAYER_LOGOUT" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, e, a1)
    if e == "QUEST_TURNED_IN" and a1 then EveUIDB.pilotTurnedIn[a1] = true end
    if e == "PLAYER_LOGOUT" then pcall(P.Export); return end
    Soon()
  end)
  ns.Every(1, "pilot map", function() MapPins(P.mapList or {}) end)
  ns.Every(5, "pilot poll", function() P.Refresh() end)
  ns.Safe("pilot refresh", P.Refresh)()
end, "pilot")

-- /eve pilot [next|back|auto|ai|off|on|goal <text>]
function P.Command(arg)
  local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  if cmd == "next" then P.Skip(1)
  elseif cmd == "back" or cmd == "prev" then P.Skip(-1)
  elseif cmd == "auto" then EveUIDB.pilotMode = "auto"; P.Refresh(); ns.Print("autopilot: nearest quest (AI guide ignored)")
  elseif cmd == "ai" or cmd == "on" then EveUIDB.pilotMode = nil; P.Refresh(); ns.Print("autopilot: AI guide when loaded")
  elseif cmd == "off" then EveUIDB.pilotMode = "off"; ns.Print("autopilot off")
  elseif cmd == "goal" then
    EveUIDB.pilotGoal = rest ~= "" and rest or nil
    P.Export()
    ns.Print("pilot goal: " .. (EveUIDB.pilotGoal or "none") .. " (sent to the planner on your next /reload)")
  else
    local g = EveUI_GUIDE
    ns.Print(("autopilot: mode %s, guide %s"):format(EveUIDB.pilotMode or "ai",
      g and ("%s (%d steps)"):format(g.created or g.id or "?", g.steps and #g.steps or 0) or
      (EveUI_GUIDE_FILE and "none yet" or "file not loaded, restart the game once")))
    if g and g.summary then ns.Print("  " .. g.summary) end
    ns.Print("  /eve pilot next | back | auto | ai | off | goal <what you want to do>")
  end
end
