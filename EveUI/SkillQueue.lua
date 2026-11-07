local ADDON, ns = ...
-- Skill queue window: the player's level as the skill in training (XP bar,
-- XP/hour this session and over the last 10 minutes, time to next level,
-- rested XP) and professions/skills as the queue below, each with an EVE
-- "Level I-V" tier and five pips derived from rank / max rank.
-- XP samples are kept per character in EveUIDB.chars[...].skillqueue.

local C = ns.C
local Plain = ns.Plain

local W, H = 440, 470
local ROW_H, VISIBLE = 34, 8
local WINDOW = 600     -- rolling rate window, seconds
local MAX_SAMPLES = 400
local ROMAN = { "I", "II", "III", "IV", "V" }

local function Comma(v)
  v = math.floor((Plain(v) or 0) + 0.5)
  if BreakUpLargeNumbers then
    local s = ns.Call(BreakUpLargeNumbers, v)
    if s then return s end
  end
  return tostring(v)
end

local function Duration(sec)
  if not sec or sec ~= sec or sec == math.huge or sec < 0 then return "-" end
  sec = math.floor(sec)
  local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
  if d > 0 then return ("%dd %dh %dm"):format(d, h, m) end
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return ("%dm %ds"):format(m, sec % 60)
end

-- Tier from rank / maxRank: five even brackets, Level V at max.
local function Tier(rank, max)
  if not rank or not max or max <= 0 then return 0, 0 end
  local x = math.min(rank / max, 1) * 5
  local lvl = math.floor(x + 1e-9)
  return lvl, lvl >= 5 and 1 or (x - lvl)
end

-- Professions (GetProfessions) or, on clients without them, every ranked
-- skill line (C_SkillInfo / GetSkillLineInfo).
local function Skills()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local list = { ns.Call(GetProfessions) }
    for i = 1, 5 do
      local idx = list[i]
      if idx then
        local name, icon, rank, max = ns.Call(GetProfessionInfo, idx)
        if name then out[#out + 1] = { name = name, icon = icon, rank = Plain(rank), max = Plain(max) } end
      end
    end
    if #out > 0 then return out end
  end
  local n = (C_SkillInfo and ns.Call(C_SkillInfo.GetNumSkillLines)) or ns.Call(GetNumSkillLines) or 0
  local header
  for i = 1, n do
    local name, isHeader, rank, max
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfo then
      local s = ns.Call(C_SkillInfo.GetSkillLineInfo, i)
      if s then name, isHeader, rank, max = s.name, s.isHeader, s.rank, s.maxRank end
    elseif GetSkillLineInfo then
      local a, h, _, r, _, _, m = ns.Call(GetSkillLineInfo, i)
      name, isHeader, rank, max = a, h, r, m
    end
    if isHeader then
      header = name
    elseif name and Plain(max) and Plain(max) > 1 then
      out[#out + 1] = { name = name, group = header, rank = Plain(rank), max = Plain(max) }
    end
  end
  return out
end

ns.RegisterModule(function()
  local l = ns.Layout()
  l.skillqueue = l.skillqueue or {}
  local db = l.skillqueue
  db.total = db.total or 0         -- cumulative XP gained while tracked
  db.samples = db.samples or {}    -- { time(), total }

  -- XP tracking ------------------------------------------------------------------
  local lastXP, lastMax = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
  local last = db.samples[#db.samples]
  -- A new session unless the last sample is recent (a /reload).
  if not db.session or not last or time() - last[1] > WINDOW then
    db.session = { time(), db.total }
  end

  local function Sample()
    local now = time()
    local s = db.samples
    local tail = s[#s]
    if tail and now - tail[1] < 5 then tail[2] = db.total
    else s[#s + 1] = { now, db.total } end
    while #s > MAX_SAMPLES do table.remove(s, 1) end
  end
  Sample()

  local function OnXP()
    local xp, max = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
    if not xp or not max then return end
    if lastXP and lastMax then
      local d = xp - lastXP
      if d < 0 then d = (lastMax - lastXP) + xp end -- levelled up
      if d > 0 then db.total = db.total + d end
    end
    lastXP, lastMax = xp, max
    Sample()
  end

  local function Rates()
    local now = time()
    local sRate
    local st = now - db.session[1]
    if st >= 30 then sRate = (db.total - db.session[2]) / st * 3600 end
    local base
    for i = #db.samples, 1, -1 do
      local p = db.samples[i]
      if now - p[1] > WINDOW then break end
      base = p
    end
    -- Use the last sample before the window as the anchor when there is one.
    local rRate
    local anchorT, anchorV
    for i = #db.samples, 1, -1 do
      local p = db.samples[i]
      if now - p[1] >= WINDOW then anchorT, anchorV = now - WINDOW, p[2]; break end
    end
    if not anchorT and base then anchorT, anchorV = base[1], base[2] end
    if anchorT and now - anchorT >= 30 then rRate = (db.total - anchorV) / (now - anchorT) * 3600 end
    return sRate, rRate
  end

  -- Window -------------------------------------------------------------------------
  local f = ns.CreatePanel("EveUISkillQueue", ns.root, "Character", W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); ns.SavePos(s) end)
  f:Hide()
  tinsert(UISpecialFrames, "EveUISkillQueue")
  local sub = ns.Text(f, 11, C.dim, "LEFT")
  sub:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
  sub:SetText("SKILL QUEUE")

  local close = CreateFrame("Button", nil, f)
  close:SetSize(ns.HEADER - 4, ns.HEADER - 4)
  close:SetPoint("TOPRIGHT", -2, -2)
  local x = ns.Text(close, 14, C.dim)
  x:SetPoint("CENTER", 0, 1)
  x:SetText("×")
  close:SetScript("OnEnter", function() x:SetTextColor(unpack(C.hostile)) end)
  close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.dim)) end)
  close:SetScript("OnClick", function() f:Hide() end)

  local function Section(text, y)
    local h = ns.Text(f, 10, C.accent, "LEFT")
    h:SetPoint("TOPLEFT", 12, y)
    h:SetText(text)
    local ln = f:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(unpack(C.line))
    ln:SetPoint("LEFT", h, "RIGHT", 6, 0)
    ln:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    ln:SetHeight(1)
    return h
  end

  local function Pips(parent)
    local p = {}
    for i = 1, 5 do
      local t = parent:CreateTexture(nil, "ARTWORK")
      t:SetSize(7, 7)
      p[i] = t
    end
    p[1]:SetPoint("RIGHT", parent, "RIGHT", -(4 * 9), 0)
    for i = 2, 5 do p[i]:SetPoint("LEFT", p[i - 1], "RIGHT", 2, 0) end
    function p.Set(lvl, partial)
      for i = 1, 5 do
        local c = (i <= lvl) and C.accent or (i == lvl + 1 and partial > 0 and { C.accent[1], C.accent[2], C.accent[3], 0.35 })
          or C.off
        p[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
      end
    end
    return p
  end

  local function Bar(parent, h)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(ns.WHITE)
    b:SetHeight(h)
    b:SetMinMaxValues(0, 1)
    ns.Box(b, C.off, C.line)
    return b
  end

  -- Training block.
  local y = -(ns.HEADER + 10)
  Section("CURRENTLY TRAINING", y)
  y = y - 18
  local train = CreateFrame("Frame", nil, f)
  train:SetPoint("TOPLEFT", 12, y)
  train:SetPoint("TOPRIGHT", -12, y)
  train:SetHeight(112)
  ns.Box(train, { 0.05, 0.07, 0.09, 0.8 }, C.line)
  local icon = train:CreateTexture(nil, "ARTWORK")
  icon:SetSize(40, 40)
  icon:SetPoint("TOPLEFT", 8, -8)
  local tName = ns.Text(train, 13, C.title, "LEFT")
  tName:SetFont(ns.FONT_BOLD, 13, "")
  tName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
  local tLevel = ns.Text(train, 11, C.accent, "LEFT")
  tLevel:SetPoint("TOPLEFT", tName, "BOTTOMLEFT", 0, -3)
  local tPips = Pips(train)
  tPips[1]:ClearAllPoints()
  tPips[1]:SetPoint("TOPRIGHT", train, "TOPRIGHT", -(8 + 4 * 9), -12)
  local tEta = ns.Text(train, 11, C.text, "RIGHT")
  tEta:SetPoint("TOPRIGHT", -8, -26)

  local rested = CreateFrame("StatusBar", nil, train)
  rested:SetStatusBarTexture(ns.WHITE)
  rested:SetMinMaxValues(0, 1)
  rested:SetPoint("TOPLEFT", 8, -56)
  rested:SetPoint("TOPRIGHT", -8, -56)
  rested:SetHeight(8)
  rested:SetStatusBarColor(C.friendly[1], C.friendly[2], C.friendly[3], 0.35)
  local xpBar = Bar(train, 8)
  xpBar:SetAllPoints(rested)
  xpBar:SetFrameLevel(rested:GetFrameLevel() + 1)
  if xpBar.eveBox then xpBar.eveBox.bg:Hide(); ns.boxBgs[xpBar.eveBox.bg] = nil end
  local rbg = rested:CreateTexture(nil, "BACKGROUND")
  rbg:SetAllPoints()
  rbg:SetColorTexture(unpack(C.off))
  ns.SetBarColor(xpBar, C.accent)
  local tXP = ns.Text(train, 11, C.text, "LEFT")
  tXP:SetPoint("TOPLEFT", rested, "BOTTOMLEFT", 0, -5)
  local tPct = ns.Text(train, 11, C.title, "RIGHT")
  tPct:SetPoint("TOPRIGHT", rested, "BOTTOMRIGHT", 0, -5)
  local tRate = ns.Text(train, 11, C.dim, "LEFT")
  tRate:SetPoint("TOPLEFT", tXP, "BOTTOMLEFT", 0, -5)
  local tRested = ns.Text(train, 11, C.friendly, "RIGHT")
  tRested:SetPoint("TOPRIGHT", tPct, "BOTTOMRIGHT", 0, -5)

  -- Queue.
  y = y - 112 - 12
  Section("SKILL QUEUE", y)
  local qCount = ns.Text(f, 10, C.dim, "RIGHT")
  qCount:SetPoint("TOPRIGHT", -12, y + 1)
  y = y - 18
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", 12, y)
  list:SetPoint("BOTTOMRIGHT", -12, 10)
  list:EnableMouseWheel(true)
  local empty = ns.Text(list, 11, C.dim, "LEFT")
  empty:SetPoint("TOPLEFT", 4, -6)
  empty:SetText("No skills to show.")

  local rows = {}
  for i = 1, VISIBLE do
    local r = CreateFrame("Frame", nil, list)
    r:SetHeight(ROW_H - 2)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    ns.Box(r, { 0.05, 0.07, 0.09, 0.6 }, false)
    r.num = ns.Text(r, 10, C.dim, "LEFT")
    r.num:SetPoint("TOPLEFT", 4, -4)
    r.num:SetWidth(14)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("TOPLEFT", 20, -5)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = ns.Text(r, 12, C.text, "LEFT")
    r.name:SetPoint("TOPLEFT", 46, -4)
    r.level = ns.Text(r, 10, C.accent, "RIGHT")
    r.level:SetPoint("TOPRIGHT", -(8 + 5 * 9 + 6), -5)
    r.pips = Pips(r)
    r.pips[1]:ClearAllPoints()
    r.pips[1]:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(8 + 4 * 9), -7)
    r.bar = Bar(r, 4)
    r.bar:SetPoint("BOTTOMLEFT", 46, 6)
    r.bar:SetPoint("BOTTOMRIGHT", -100, 6)
    ns.SetBarColor(r.bar, C.accent)
    r.rank = ns.Text(r, 10, C.dim, "RIGHT")
    r.rank:SetPoint("BOTTOMRIGHT", -8, 3)
    rows[i] = r
  end

  local offset, skills = 0, {}
  local function DrawQueue()
    offset = math.max(0, math.min(offset, #skills - VISIBLE))
    empty:SetShown(#skills == 0)
    qCount:SetText(#skills > 0 and (#skills .. (#skills == 1 and " SKILL" or " SKILLS")) or "")
    for i, r in ipairs(rows) do
      local s = skills[i + offset]
      if s then
        local lvl, part = Tier(s.rank, s.max)
        r.num:SetText(i + offset)
        r.icon:SetTexture(s.icon or "Interface\\Icons\\INV_Misc_Book_09")
        r.name:SetText(s.name .. (s.group and ("  |cff808a90" .. s.group .. "|r") or ""))
        r.level:SetText(lvl > 0 and ("Level " .. ROMAN[lvl]) or "Untrained")
        r.pips.Set(lvl, part)
        r.bar:SetValue(lvl >= 5 and 1 or part)
        r.rank:SetText(("%s / %s"):format(s.rank or "?", s.max or "?"))
        r:Show()
      else
        r:Hide()
      end
    end
  end
  list:SetScript("OnMouseWheel", function(_, d) offset = offset - d; DrawQueue() end)

  local function DrawTraining()
    local lvl = Plain(UnitLevel("player")) or 0
    local maxLvl = Plain(ns.Call(GetMaxPlayerLevel)) or 0
    local xp, max = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
    local cls = Plain(UnitClass("player")) or ""
    tName:SetText(("Capsuleer Operation: %s"):format(cls))
    ns.Call(SetPortraitTexture, icon, "player")
    local capped = maxLvl > 0 and lvl >= maxLvl
    tLevel:SetText(capped and ("Level %d  (fully trained)"):format(lvl) or ("Level %d  >  %d"):format(lvl, lvl + 1))
    local frac = (xp and max and max > 0) and xp / max or 0
    if capped then frac = 1 end
    -- Pips: fifths of the current level.
    local fifth = math.floor(frac * 5 + 1e-9)
    tPips.Set(fifth, frac * 5 - fifth)
    xpBar:SetValue(frac)
    local rest = Plain(ns.Call(GetXPExhaustion))
    if rest and max and max > 0 and not capped then
      rested:SetValue(math.min((xp + rest) / max, 1))
      tRested:SetText(("Rested %s (%d%%)"):format(Comma(rest), math.floor(rest / max * 100 + 0.5)))
    else
      rested:SetValue(0)
      tRested:SetText(capped and "" or "Not rested")
    end
    if capped then
      tXP:SetText("Maximum level reached")
      tPct:SetText("100%")
      tRate:SetText("")
      tEta:SetText("")
      return
    end
    tXP:SetText(xp and max and ("%s / %s XP"):format(Comma(xp), Comma(max)) or "-")
    tPct:SetText(("%.1f%%"):format(frac * 100))
    local sRate, rRate = Rates()
    tRate:SetText(("Session %s/h   10 min %s/h"):format(sRate and Comma(sRate) or "-", rRate and Comma(rRate) or "-"))
    local rate = (rRate and rRate > 0 and rRate) or (sRate and sRate > 0 and sRate)
    if rate and xp and max then
      tEta:SetText("Next level in " .. Duration((max - xp) / rate * 3600))
    else
      tEta:SetText("Next level in -")
    end
  end

  local skillsDirty = true
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "SKILL_LINES_CHANGED",
    "TRADE_SKILL_LIST_UPDATE", "CHAT_MSG_SKILL" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", ns.Safe("skill queue", function(_, e)
    if e == "PLAYER_XP_UPDATE" or e == "PLAYER_LEVEL_UP" then OnXP()
    elseif e ~= "UPDATE_EXHAUSTION" then skillsDirty = true end
  end))

  f:SetScript("OnShow", function() skillsDirty = true end)
  ns.Every(1, "skill queue", function()
    if not f:IsShown() then return end
    if skillsDirty then skillsDirty = false; skills = Skills(); DrawQueue() end
    DrawTraining()
  end)

  ns.Mover(f, { key = "skillqueue", label = "Skill queue", point = "CENTER", x = 0, y = 40 })

  function ns.ToggleSkillQueue()
    f:SetShown(not f:IsShown())
  end
end, "skillqueue")
