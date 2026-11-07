-- Damage meter: an EVE panel over the game's own combat tracking (C_DamageMeter),
-- which replaces Blizzard's unthemed meter window.
--
-- Modes: damage, DPS, healing, HPS, absorbs, interrupts, dispels, damage taken,
-- avoidable damage, deaths, enemy damage taken. Segments: current fight,
-- overall and every past fight the game keeps. Click a row for its spell
-- breakdown, right-click to go back. Hover for the top spells.
--
-- In combat the game hands out amounts as secret values. They go straight to
-- StatusBars, AbbreviateNumbers and SetFormattedText, which accept them; maths
-- (percentages, totals per second), reports and spell breakdowns of units with
-- a secret GUID wait until the values are plain again after combat.
local ADDON, ns = ...
local C = ns.C

local ROW_H, SUB_H = 18, 18
local TOP = ns.HEADER + SUB_H + 1
local MIN_W, MIN_H, MAX_ROWS = 220, TOP + 3 * ROW_H + 4, 40

local E = Enum or {}
local MT = E.DamageMeterType or {}
local ST = E.DamageMeterSessionType or { Overall = 0, Current = 1 }

-- rate: amount per second is the main number; noRate: no per-second column.
local MODES = {
  { MT.DamageDone or 0, "Damage Done" },
  { MT.Dps or 1, "DPS", rate = true },
  { MT.HealingDone or 2, "Healing Done" },
  { MT.Hps or 3, "HPS", rate = true },
  { MT.Absorbs or 4, "Absorbs" },
  { MT.Interrupts or 5, "Interrupts", noRate = true },
  { MT.Dispels or 6, "Dispels", noRate = true },
  { MT.DamageTaken or 7, "Damage Taken", taken = true },
  { MT.AvoidableDamageTaken or 8, "Avoidable Damage", taken = true },
  { MT.Deaths or 9, "Deaths", noRate = true, deaths = true },
  { MT.EnemyDamageTaken or 10, "Enemy Damage Taken" },
}

local issecret = ns.issecret
local Plain = ns.Plain

local function Abbr(v)
  if type(v) ~= "number" then return "0" end
  if AbbreviateNumbers then
    local ok, s = pcall(AbbreviateNumbers, v)
    if ok then return s end
  end
  if issecret(v) then return v end
  return tostring(math.floor(v + 0.5))
end

local function Clock(sec)
  sec = Plain(sec)
  if type(sec) ~= "number" or sec < 0 then return "" end
  sec = math.floor(sec)
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function Pct(v, total)
  v, total = Plain(v), Plain(total)
  if type(v) ~= "number" or type(total) ~= "number" or total <= 0 then return nil end
  return v / total * 100
end

local classColors = {}
local function SourceColor(src)
  local cls = src.classFilename
  if type(cls) == "string" and cls ~= "" then
    if not classColors[cls] then
      local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[cls]
      classColors[cls] = c and { c.r, c.g, c.b, 1 } or C.friendly
    end
    return classColors[cls]
  end
  local disp = Plain(src.sourceDisplayType)
  local SD = E.DamageMeterSourceDisplayType or { Enemy = 2 }
  if disp == SD.Enemy then return C.hostile end
  return C.neutral
end

local function SpellInfo(id)
  if issecret(id) or type(id) ~= "number" then return nil, nil end
  local name = C_Spell and C_Spell.GetSpellName and ns.Call(C_Spell.GetSpellName, id)
  local icon = C_Spell and C_Spell.GetSpellTexture and ns.Call(C_Spell.GetSpellTexture, id)
  if not name and GetSpellInfo then
    local n, _, i = ns.Call(GetSpellInfo, id)
    name, icon = n, icon or i
  end
  return name, icon
end

ns.RegisterModule(function()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end

  EveUIDB.meter = EveUIDB.meter or {}
  local cfg = EveUIDB.meter
  cfg.mode = cfg.mode or 1
  cfg.show = cfg.show or "always"
  if cfg.hideBlizzard == nil then cfg.hideBlizzard = true end
  if not MODES[cfg.mode] then cfg.mode = 1 end

  -- Session being viewed: { type = n } or { id = n, name = s }.
  local seg = { type = ST.Current }
  local detail -- { guid, creatureID, name, color } while a spell breakdown is open
  local offset, dirty = 0, true
  local data = {} -- rows to draw, rebuilt by Fetch

  local l = ns.Layout()
  local size = l.meterSize or { 300, TOP + 8 * ROW_H + 4 }
  local f = ns.CreatePanel("EveUIDamageMeter", ns.root, nil, size[1], size[2])
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, 600, TOP + MAX_ROWS * ROW_H + 4)
  elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
  f:EnableMouse(true)
  ns.meter = f

  -- Title bar (drawn here, not by CreatePanel, so the title is a button).
  local hb = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  hb:SetColorTexture(unpack(C.header))
  hb:SetPoint("TOPLEFT", 1, -1); hb:SetPoint("TOPRIGHT", -1, -1)
  hb:SetHeight(ns.HEADER - 1)
  local mark = f:CreateTexture(nil, "ARTWORK")
  mark:SetColorTexture(unpack(C.accent))
  mark:SetPoint("TOPLEFT", 1, -1); mark:SetSize(2, ns.HEADER - 1)
  for _, yy in ipairs({ ns.HEADER, TOP }) do
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(C.line))
    line:SetPoint("TOPLEFT", 1, -yy); line:SetPoint("TOPRIGHT", -1, -yy)
    line:SetHeight(1)
  end

  local function TextButton(parent, size, color, justify, bold)
    local b = CreateFrame("Button", nil, parent)
    b.text = ns.Text(b, size, color, justify or "LEFT")
    if bold then b.text:SetFont(ns.FONT_BOLD, size, "") end
    b.text:SetAllPoints()
    b.color = color
    b:SetScript("OnEnter", function(s) s.text:SetTextColor(unpack(C.accent)) end)
    b:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(s.color)) end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return b
  end

  local title = TextButton(f, 12, C.title, "LEFT", true)
  title:SetPoint("TOPLEFT", 10, -1)
  title:SetSize(150, ns.HEADER - 1)

  local resetB = TextButton(f, 11, C.dim, "RIGHT")
  resetB:SetPoint("TOPRIGHT", -8, -1)
  resetB:SetSize(40, ns.HEADER - 1)
  resetB.text:SetText("RESET")
  local reportB = TextButton(f, 11, C.dim, "RIGHT")
  reportB:SetPoint("RIGHT", resetB, "LEFT", -8, 0)
  reportB:SetSize(48, ns.HEADER - 1)
  reportB.text:SetText("REPORT")

  local segB = TextButton(f, 11, C.text, "LEFT")
  segB:SetPoint("TOPLEFT", 10, -(ns.HEADER + 1))
  segB:SetSize(140, SUB_H)
  local stats = ns.Text(f, 11, C.dim, "RIGHT")
  stats:SetPoint("TOPRIGHT", -8, -(ns.HEADER + 1))
  stats:SetHeight(SUB_H)
  stats:SetPoint("LEFT", segB, "RIGHT", 4, 0)

  local empty = ns.Text(f, 11, C.dim)
  empty:SetPoint("TOPLEFT", 8, -(TOP + 8)); empty:SetPoint("TOPRIGHT", -8, -(TOP + 8))
  if empty.SetWordWrap then empty:SetWordWrap(true) end

  -- Popup menu ----------------------------------------------------------------------
  local menu = ns.CreatePanel("EveUIDamageMeterMenu", ns.root, nil, 180, 20)
  menu:SetFrameStrata("DIALOG")
  menu:EnableMouse(true)
  menu:Hide()
  menu.items = {}
  pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
  menu:SetScript("OnEvent", function(m)
    if m:IsShown() and not m:IsMouseOver() and not (m.owner and m.owner:IsMouseOver()) then m:Hide() end
  end)

  local function OpenMenu(owner, items)
    if menu:IsShown() and menu.owner == owner then menu:Hide() return end
    menu.owner = owner
    local w = 140
    for i, it in ipairs(items) do
      local b = menu.items[i]
      if not b then
        b = CreateFrame("Button", nil, menu)
        b:SetHeight(18)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
        b.text = ns.Text(b, 11, C.text, "LEFT")
        b.text:SetPoint("LEFT", 16, 0); b.text:SetPoint("RIGHT", -8, 0)
        b.tick = b:CreateTexture(nil, "ARTWORK")
        b.tick:SetColorTexture(unpack(C.accent))
        b.tick:SetSize(4, 4); b.tick:SetPoint("LEFT", 6, 0)
        menu.items[i] = b
      end
      b:SetPoint("TOPLEFT", 1, -(4 + (i - 1) * 18)); b:SetPoint("TOPRIGHT", -1, -(4 + (i - 1) * 18))
      b.text:SetText(it.text)
      b.text:SetTextColor(unpack(it.header and C.dim or C.text))
      b.tick:SetShown(it.checked == true)
      b:SetEnabled(not it.header)
      b:SetScript("OnClick", function() menu:Hide(); if it.func then it.func() end end)
      b:Show()
      w = math.max(w, b.text:GetStringWidth() + 28)
    end
    for i = #items + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(w, #items * 18 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -4, -2)
    menu:SetClampedToScreen(true)
    menu:Show()
  end

  -- Data --------------------------------------------------------------------------
  local function Mode() return MODES[cfg.mode] end

  local function Session()
    local t = Mode()[1]
    if seg.id then return ns.Call(C_DamageMeter.GetCombatSessionFromID, seg.id, t) end
    return ns.Call(C_DamageMeter.GetCombatSessionFromType, seg.type, t)
  end

  local function SourceData()
    local t = Mode()[1]
    if seg.id then
      return ns.Call(C_DamageMeter.GetCombatSessionSourceFromID, seg.id, t, detail.guid, detail.creatureID)
    end
    return ns.Call(C_DamageMeter.GetCombatSessionSourceFromType, seg.type, t, detail.guid, detail.creatureID)
  end

  local function Duration(session)
    if seg.id then return session and session.durationSeconds end
    return ns.Call(C_DamageMeter.GetSessionDurationSeconds, seg.type)
  end

  local function SegmentName()
    if seg.id then return seg.name or "Fight" end
    return seg.type == ST.Overall and "Overall" or "Current Fight"
  end

  -- Fetch fills `data` with one entry per row and returns the header totals.
  local function Fetch()
    wipe(data)
    if detail then
      local sd = SourceData()
      if not sd then return nil end
      for i, sp in ipairs(sd.combatSpells or {}) do
        data[#data + 1] = { spell = sp, rank = i, max = sd.maxAmount, total = sd.totalAmount,
          value = sp.totalAmount, rate = sp.amountPerSecond }
      end
      return sd.totalAmount
    end
    local session = Session()
    if not session then return nil end
    for i, src in ipairs(session.combatSources or {}) do
      data[#data + 1] = { src = src, rank = i, max = session.maxAmount, total = session.totalAmount,
        value = src.totalAmount, rate = src.amountPerSecond }
    end
    return session.totalAmount, session
  end

  -- Rows --------------------------------------------------------------------------
  local rows = {}
  local ShowTooltip, Drill, Back

  local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, f)
    r:SetHeight(ROW_H - 1)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 3, ROW_H - 3)
    r.icon:SetPoint("LEFT", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 2, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetStatusBarTexture(ns.WHITE)
    r.bar:SetMinMaxValues(0, 1)
    local bg = r.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(unpack(C.off))
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(r.bar); hl:SetColorTexture(1, 1, 1, 0.06)
    r.me = r.bar:CreateTexture(nil, "OVERLAY")
    r.me:SetColorTexture(unpack(C.accent))
    r.me:SetPoint("TOPRIGHT"); r.me:SetPoint("BOTTOMRIGHT"); r.me:SetWidth(2)
    r.name = ns.Text(r.bar, 11, C.title, "LEFT")
    r.name:SetPoint("LEFT", 4, 0)
    r.value = ns.Text(r.bar, 11, C.title, "RIGHT")
    r.value:SetPoint("RIGHT", -5, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, d) f:GetScript("OnMouseWheel")(f, d) end)
    r:SetScript("OnEnter", function(s) ShowTooltip(s) end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(s, button)
      if button == "RightButton" then Back() elseif s.entry then Drill(s.entry) end
    end)
    rows[i] = r
    return r
  end

  local function ValueText(fs, e)
    local m = Mode()
    if e.src and m.deaths then
      fs:SetText(Clock(e.src.deathTimeSeconds))
      return
    end
    local main, extra = e.value, e.rate
    if m.rate then main, extra = e.rate, e.value end
    local pct = Pct(e.value, e.total)
    if m.noRate then
      if pct then fs:SetFormattedText("%s  %.0f%%", Abbr(main), pct) else fs:SetText(Abbr(main)) end
    elseif pct then
      fs:SetFormattedText("%s (%s)  %.0f%%", Abbr(main), Abbr(extra), pct)
    else
      fs:SetFormattedText("%s (%s)", Abbr(main), Abbr(extra))
    end
  end

  local function DrawRow(r, e, i, count)
    r.entry = e
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 1, -(TOP + 2 + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", -1, -(TOP + 2 + (i - 1) * ROW_H))
    local color, isMe = C.friendly, false
    if e.src then
      local src = e.src
      color, isMe = SourceColor(src), src.isLocalPlayer == true
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      local spec = src.specIconID
      if issecret(spec) or (type(spec) == "number" and spec ~= 0) then
        r.icon:SetTexture(spec)
        r.icon:SetVertexColor(1, 1, 1, 1)
      elseif GetClassAtlas and type(src.classFilename) == "string" and src.classFilename ~= "" then
        r.icon:SetTexCoord(0, 1, 0, 1)
        r.icon:SetAtlas(GetClassAtlas(src.classFilename))
        r.icon:SetVertexColor(1, 1, 1, 1)
      else
        r.icon:SetTexture(ns.WHITE)
        r.icon:SetVertexColor(color[1], color[2], color[3], 0.6)
      end
      r.name:SetFormattedText("%d. %s", e.rank, src.name)
    else
      local sp = e.spell
      local name, icon = SpellInfo(sp.spellID)
      color = detail and detail.color or C.accent
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.icon:SetTexture(icon or 134400) -- question mark
      r.icon:SetVertexColor(1, 1, 1, 1)
      local who = sp.creatureName
      if Mode().taken and type(who) == "string" and (issecret(who) or who ~= "") then
        r.name:SetFormattedText("%d. %s: %s", e.rank, who, name or "Melee")
      else
        r.name:SetFormattedText("%d. %s", e.rank, name or (Plain(sp.spellID) and ("Spell " .. sp.spellID)) or "Spell")
      end
    end
    ns.SetBarColor(r.bar, color)
    if Mode().deaths and e.src then
      r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(1)
    else
      local max = e.max
      if not issecret(max) and (type(max) ~= "number" or max <= 0) then max = 1 end
      r.bar:SetMinMaxValues(0, max)
      r.bar:SetValue(e.value)
    end
    ValueText(r.value, e)
    r.me:SetShown(isMe)
    r:Show()
  end

  local function Visible() return math.max(1, math.floor((f:GetHeight() - TOP - 4) / ROW_H)) end

  local function Redraw()
    dirty = false
    local avail, why = true, nil
    if C_DamageMeter.IsDamageMeterAvailable then
      local ok, a, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
      if ok then avail, why = a, reason end
    end
    local m = Mode()
    if detail then
      title.text:SetFormattedText("< %s", detail.name or "?")
    else
      title.text:SetText(m[2]:upper())
    end
    segB.text:SetFormattedText("%s  v", SegmentName():upper())

    local total, session = Fetch()
    local dur = Duration(session)
    local clock = Clock(dur)
    if m.deaths or m.noRate or type(total) == "nil" then
      stats:SetText(clock)
    else
      local t, d = Plain(total), Plain(dur)
      if t and d and d > 0 then
        stats:SetFormattedText("%s  %s/s  %s", Abbr(t), Abbr(t / d), clock)
      else
        stats:SetFormattedText("%s  %s", Abbr(total), clock)
      end
    end

    local n = Visible()
    offset = math.max(0, math.min(offset, #data - n))
    -- Keep the player in view: the last row shows them if they scrolled away.
    local meIdx
    if not detail then
      for i, e in ipairs(data) do if e.src.isLocalPlayer == true then meIdx = i break end end
    end
    local shown = 0
    for i = 1, n do
      local e = data[offset + i]
      if i == n and meIdx and (meIdx <= offset or meIdx > offset + n) then e = data[meIdx] end
      if e then shown = shown + 1; DrawRow(Row(i), e, i, n) end
    end
    for i = shown + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end

    if not avail then
      empty:SetText("Damage meter unavailable" .. (type(why) == "string" and why ~= "" and (": " .. why) or "."))
    elseif detail and #data == 0 then
      empty:SetText(InCombatLockdown() and "Spell breakdown shows after combat." or "No spells recorded.")
    else
      empty:SetText(#data == 0 and "No combat data yet." or "")
    end
    empty:SetShown(shown == 0)
  end

  local function Refresh() dirty = true end

  -- Drill-down ----------------------------------------------------------------------
  function Drill(e)
    if detail or not e.src then return end
    local src = e.src
    if Mode().deaths then
      local id = Plain(src.deathRecapID)
      if id and id ~= 0 and OpenDeathRecapUI then ns.Call(OpenDeathRecapUI, id) end
      return
    end
    if issecret(src.sourceGUID) or issecret(src.sourceCreatureID) then
      ns.Print("spell breakdown for this unit shows after combat.")
      return
    end
    detail = { guid = src.sourceGUID, creatureID = src.sourceCreatureID, name = Plain(src.name) or "Unit",
      color = SourceColor(src) }
    offset = 0
    GameTooltip:Hide()
    Redraw()
  end

  function Back()
    if detail then detail = nil; offset = 0; Redraw() end
  end

  -- Tooltip: totals and the five biggest spells.
  function ShowTooltip(r)
    local e = r.entry
    if not e then return end
    GameTooltip:SetOwner(r, "ANCHOR_LEFT")
    local ok = pcall(function()
      if e.src then
        GameTooltip:AddLine(e.src.name, 1, 1, 1)
        local pct = Pct(e.value, e.total)
        GameTooltip:AddDoubleLine(Mode()[2], Abbr(e.value), 0.6, 0.65, 0.7, 1, 1, 1)
        if not Mode().noRate then GameTooltip:AddDoubleLine("Per second", Abbr(e.rate), 0.6, 0.65, 0.7, 1, 1, 1) end
        if pct then GameTooltip:AddDoubleLine("Share", ("%.1f%%"):format(pct), 0.6, 0.65, 0.7, 1, 1, 1) end
        if not (issecret(e.src.sourceGUID) or issecret(e.src.sourceCreatureID)) and not Mode().deaths then
          local t = Mode()[1]
          local sd
          if seg.id then
            sd = ns.Call(C_DamageMeter.GetCombatSessionSourceFromID, seg.id, t, e.src.sourceGUID, e.src.sourceCreatureID)
          else
            sd = ns.Call(C_DamageMeter.GetCombatSessionSourceFromType, seg.type, t, e.src.sourceGUID, e.src.sourceCreatureID)
          end
          if sd and sd.combatSpells and #sd.combatSpells > 0 then
            GameTooltip:AddLine(" ")
            for i = 1, math.min(5, #sd.combatSpells) do
              local sp = sd.combatSpells[i]
              local name, icon = SpellInfo(sp.spellID)
              local label = (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. (name or "Melee")
              GameTooltip:AddDoubleLine(label, Abbr(sp.totalAmount), 0.86, 0.89, 0.91, 1, 1, 1)
            end
          end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Mode().deaths and "Click: death recap" or "Click: spell breakdown", C.accent[1], C.accent[2], C.accent[3])
      else
        local name = SpellInfo(e.spell.spellID)
        GameTooltip:AddLine(name or "Spell", 1, 1, 1)
        GameTooltip:AddDoubleLine("Amount", Abbr(e.value), 0.6, 0.65, 0.7, 1, 1, 1)
        if not Mode().noRate then GameTooltip:AddDoubleLine("Per second", Abbr(e.rate), 0.6, 0.65, 0.7, 1, 1, 1) end
        local pct = Pct(e.value, e.total)
        if pct then GameTooltip:AddDoubleLine("Share", ("%.1f%%"):format(pct), 0.6, 0.65, 0.7, 1, 1, 1) end
        local ok2 = Plain(e.spell.overkillAmount)
        if ok2 and ok2 > 0 then GameTooltip:AddDoubleLine("Overkill", Abbr(ok2), 0.6, 0.65, 0.7, 1, 1, 1) end
        GameTooltip:AddLine("Right-click: back", C.accent[1], C.accent[2], C.accent[3])
      end
    end)
    if ok then GameTooltip:Show() else GameTooltip:Hide() end
  end

  -- Controls ------------------------------------------------------------------------
  local function SetMode(i)
    cfg.mode = ((i - 1) % #MODES) + 1
    offset = 0
    Redraw()
  end

  title:SetScript("OnClick", function(s, button)
    if detail then Back() return end
    if button == "RightButton" then return end
    local items = {}
    for i, m in ipairs(MODES) do
      items[#items + 1] = { text = m[2], checked = i == cfg.mode, func = function() SetMode(i) end }
    end
    OpenMenu(s, items)
  end)

  segB:SetScript("OnClick", function(s)
    local items = {
      { text = "Current Fight", checked = not seg.id and seg.type == ST.Current,
        func = function() seg = { type = ST.Current }; detail = nil; Redraw() end },
      { text = "Overall", checked = not seg.id and seg.type == ST.Overall,
        func = function() seg = { type = ST.Overall }; detail = nil; Redraw() end },
    }
    local list = ns.Call(C_DamageMeter.GetAvailableCombatSessions) or {}
    if #list > 0 then items[#items + 1] = { text = "PAST FIGHTS", header = true } end
    for i = #list, math.max(1, #list - 11), -1 do
      local s2 = list[i]
      local id, name = Plain(s2.sessionID), Plain(s2.name)
      if id then
        local label = (name and name ~= "" and name or ("Fight " .. id))
        local d = Clock(s2.durationSeconds)
        if d ~= "" then label = label .. "  " .. d end
        items[#items + 1] = { text = label, checked = seg.id == id,
          func = function() seg = { id = id, name = name }; detail = nil; Redraw() end }
      end
    end
    OpenMenu(s, items)
  end)

  local resetArmed
  resetB:SetScript("OnClick", function(s)
    if resetArmed then
      resetArmed = nil
      s.color = C.dim; s.text:SetText("RESET"); s.text:SetTextColor(unpack(C.dim))
      ns.Call(C_DamageMeter.ResetAllCombatSessions)
      seg, detail, offset = { type = ST.Current }, nil, 0
      Redraw()
      return
    end
    resetArmed = true
    s.color = C.hostile; s.text:SetText("CONFIRM"); s.text:SetTextColor(unpack(C.hostile))
    C_Timer.After(3, function()
      if resetArmed then
        resetArmed = nil
        s.color = C.dim; s.text:SetText("RESET"); s.text:SetTextColor(unpack(C.dim))
      end
    end)
  end)

  -- Report the top five to a chat channel. Needs plain values, so not in combat.
  local function Report(channel)
    Fetch()
    local lines = {}
    local m = Mode()
    local head = ("EveUI %s - %s"):format(detail and (detail.name .. " " .. m[2]) or m[2], SegmentName())
    for i = 1, math.min(5, #data) do
      local e = data[i]
      local name
      if e.src then name = Plain(e.src.name) else name = (SpellInfo(e.spell.spellID)) end
      local v, rate = Plain(e.value), Plain(e.rate)
      if not name or not v then
        return ns.Print("reports are available after combat.")
      end
      local pct = Pct(e.value, e.total)
      local s = ("%d. %s  %s"):format(i, name, Abbr(m.rate and rate or v))
      if not m.noRate and rate then s = s .. (" (%s)"):format(Abbr(m.rate and v or rate)) end
      if pct then s = s .. ("  %.0f%%"):format(pct) end
      lines[#lines + 1] = s
    end
    if #lines == 0 then return ns.Print("nothing to report.") end
    table.insert(lines, 1, head)
    for _, s in ipairs(lines) do
      if channel == "SELF" then ns.Print(s) else SendChatMessage(s, channel) end
    end
  end

  reportB:SetScript("OnClick", function(s)
    local items = { { text = "Chat (only you)", func = function() Report("SELF") end } }
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
      items[#items + 1] = { text = "Instance", func = function() Report("INSTANCE_CHAT") end }
    end
    if IsInRaid() then items[#items + 1] = { text = "Raid", func = function() Report("RAID") end }
    elseif IsInGroup() then items[#items + 1] = { text = "Party", func = function() Report("PARTY") end } end
    if IsInGuild() then items[#items + 1] = { text = "Guild", func = function() Report("GUILD") end } end
    items[#items + 1] = { text = "Say", func = function() Report("SAY") end }
    OpenMenu(s, items)
  end)

  -- Right-click on the panel: display options.
  local function Options(owner)
    local function Show(v, label)
      return { text = label, checked = cfg.show == v, func = function() cfg.show = v; ns.meterVisibility() end }
    end
    OpenMenu(owner, {
      { text = "SHOW", header = true },
      Show("always", "Always"), Show("combat", "In combat"), Show("group", "In a group"),
      { text = "OTHER", header = true },
      { text = "Hide Blizzard's meter", checked = cfg.hideBlizzard, func = function()
        cfg.hideBlizzard = not cfg.hideBlizzard
        ns.Print("Blizzard's damage meter: " .. (cfg.hideBlizzard and "hidden" or "shown after a reload") .. ".")
        if cfg.hideBlizzard then ns.meterHideBlizzard() end
      end },
      { text = "Reset data", func = function() resetB:Click() end },
    })
  end
  f:SetScript("OnMouseUp", function(s, button) if button == "RightButton" then Options(s) end end)
  title:HookScript("OnClick", function(s, button) if button == "RightButton" and not detail then Options(s) end end)

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d)
    if IsShiftKeyDown() and not detail then SetMode(cfg.mode - d) return end
    offset = math.max(0, offset - d)
    Redraw()
  end)
  f:SetScript("OnSizeChanged", function() dirty = true end)

  -- Layout ------------------------------------------------------------------------
  ns.Mover(f, { key = "meter", label = "Damage meter", point = "BOTTOMRIGHT", x = -16, y = 400, resize = true,
    onUnlock = function() if ns.meterVisibility then ns.meterVisibility() end end,
    save = function(fr)
      ns.SavePos(fr)
      ns.Layout().meterSize = { math.floor(fr:GetWidth() + 0.5), math.floor(fr:GetHeight() + 0.5) }
      dirty = true
    end })

  -- Visibility ----------------------------------------------------------------------
  local inCombat = false
  function ns.meterVisibility()
    local show = cfg.show
    local on = show == "always" or (show == "combat" and inCombat) or (show == "group" and IsInGroup())
    f:SetShown(on or ns.unlocked)
    if not f:IsShown() then menu:Hide() end
  end

  -- Blizzard's meter keeps tracking (its CVar stays on) but is invisible and
  -- takes no clicks. Alpha and mouse only, so Edit Mode's fields stay untainted.
  function ns.meterHideBlizzard()
    local dm = _G.DamageMeter
    if not dm or not cfg.hideBlizzard then return end
    ns.Ghost(dm)
    if not dm.eveMeterHooked then
      dm.eveMeterHooked = true
      dm:HookScript("OnShow", function(s) if cfg.hideBlizzard then ns.Ghost(s) end end)
    end
  end
  if GetCVar and GetCVar("damageMeterEnabled") == "0" and SetCVar then
    -- The game only feeds the meter while it is enabled.
    SetCVar("damageMeterEnabled", "1")
  end
  ns.meterHideBlizzard()
  C_Timer.After(2, ns.meterHideBlizzard)

  -- Events --------------------------------------------------------------------------
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      inCombat = true
      -- A new fight: jump back to it from a past fight.
      if seg.id then seg = { type = ST.Current }; detail = nil end
      ns.meterVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
      inCombat = false
      ns.meterVisibility()
    elseif event == "GROUP_ROSTER_UPDATE" then
      ns.meterVisibility()
    elseif event == "DAMAGE_METER_RESET" then
      seg, detail, offset = { type = ST.Current }, nil, 0
    end
    dirty = true
  end)

  -- Redraw on data changes (at most 5 a second) and every second for the clock.
  local tick = 0
  ns.Every(0.2, "damage meter", function()
    tick = tick + 1
    if not f:IsVisible() then return end
    if dirty or (inCombat and tick % 5 == 0) then Redraw() end
  end)
  ns.meterVisibility()
end, "meter")
