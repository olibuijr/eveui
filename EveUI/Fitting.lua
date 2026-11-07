local ADDON, ns = ...
-- Fitting window: the character's gear as an EVE ship fitting screen. A round
-- ship disc with the player model sits in the middle; equipped items are
-- modules on the ring (high: weapons and trinkets, mid: head to chest, low:
-- wrists to rings). The right column shows stats as EVE gauges. Read-only.

local C = ns.C
local Plain = ns.Plain

local W, H = 660, 500
local RING_W = 420 -- left area holding the ring
local R = 145      -- slot ring radius
local DISC = 210   -- ship disc diameter
local SLOT = 34
local ROW_H, SEC_H = 20, 18

local function Slot(name, id) return _G[name] or id end
-- { inventory slot id, short label, group }
local SLOTS = {
  high = {
    { Slot("INVSLOT_MAINHAND", 16), "Main" }, { Slot("INVSLOT_OFFHAND", 17), "Off" },
    { Slot("INVSLOT_RANGED", 18), "Rng", optional = true },
    { Slot("INVSLOT_TRINKET1", 13), "Trk" }, { Slot("INVSLOT_TRINKET2", 14), "Trk" },
  },
  mid = {
    { Slot("INVSLOT_HEAD", 1), "Head" }, { Slot("INVSLOT_NECK", 2), "Neck" },
    { Slot("INVSLOT_SHOULDER", 3), "Shld" }, { Slot("INVSLOT_BACK", 15), "Back" },
    { Slot("INVSLOT_CHEST", 5), "Chst" },
  },
  low = {
    { Slot("INVSLOT_WRIST", 9), "Wrst" }, { Slot("INVSLOT_HAND", 10), "Hand" },
    { Slot("INVSLOT_WAIST", 6), "Wst" }, { Slot("INVSLOT_LEGS", 7), "Legs" },
    { Slot("INVSLOT_FEET", 8), "Feet" }, { Slot("INVSLOT_FINGER1", 11), "Ring" },
    { Slot("INVSLOT_FINGER2", 12), "Ring" },
  },
}
-- Arc (degrees, 0 = right, counter-clockwise) for each group.
local ARCS = { high = { 145, 35 }, mid = { 15, -65 }, low = { -95, -245 } }
local GROUP_LABEL = { high = "HIGH SLOTS", mid = "MID SLOTS", low = "LOW SLOTS" }

local function QualityColor(q)
  q = Plain(q)
  if type(q) ~= "number" then return C.border end
  if C_Item and C_Item.GetItemQualityColor then
    local r, g, b = ns.Call(C_Item.GetItemQualityColor, q)
    if r then return { r, g, b, 1 } end
  end
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return { c.r, c.g, c.b, 1 } end
  return C.border
end

local function ItemLevel(link)
  if not link then return nil end
  local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  return Plain(ns.Call(f, link))
end

local function Fmt(v)
  v = Plain(v)
  if type(v) ~= "number" then return "-" end
  if BreakUpLargeNumbers then
    local s = ns.Call(BreakUpLargeNumbers, math.floor(v + 0.5))
    if s then return s end
  end
  return tostring(math.floor(v + 0.5))
end

local function Pct(v)
  v = Plain(v)
  if type(v) ~= "number" then return "-" end
  return ("%.1f%%"):format(v)
end

ns.RegisterModule(function()
  local f = ns.CreatePanel("EveUIFitting", ns.root, "Fitting", W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); ns.SavePos(s) end)
  f:Hide()
  tinsert(UISpecialFrames, "EveUIFitting")

  local sub = ns.Text(f, 11, C.dim, "LEFT")
  sub:SetPoint("LEFT", f.title, "RIGHT", 8, 0)

  local close = CreateFrame("Button", nil, f)
  close:SetSize(ns.HEADER - 4, ns.HEADER - 4)
  close:SetPoint("TOPRIGHT", -2, -2)
  local x = ns.Text(close, 14, C.dim)
  x:SetPoint("CENTER", 0, 1)
  x:SetText("×")
  close:SetScript("OnEnter", function() x:SetTextColor(unpack(C.hostile)) end)
  close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.dim)) end)
  close:SetScript("OnClick", function() f:Hide() end)

  -- Divider between ring and stats.
  local div = f:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(unpack(C.line))
  div:SetPoint("TOPLEFT", RING_W, -ns.HEADER - 1)
  div:SetPoint("BOTTOMLEFT", RING_W, 1)
  div:SetWidth(1)

  -- Ship ring -----------------------------------------------------------------------
  local ring = CreateFrame("Frame", nil, f)
  ring:SetPoint("TOPLEFT", 1, -ns.HEADER - 1)
  ring:SetSize(RING_W - 1, H - ns.HEADER - 2)
  local cx, cy = (RING_W - 1) / 2, -(H - ns.HEADER - 2) / 2 + 6

  local function Line(x1, y1, x2, y2, color, thick)
    local l = ring:CreateLine(nil, "BORDER")
    l:SetColorTexture(unpack(color))
    l:SetThickness(thick or 1)
    l:SetStartPoint("TOPLEFT", ring, cx + x1, cy + y1)
    l:SetEndPoint("TOPLEFT", ring, cx + x2, cy + y2)
    return l
  end
  local function Circle(radius, color, from, to, segs, thick)
    from, to = math.rad(from or 0), math.rad(to or 360)
    segs = segs or 72
    for i = 0, segs - 1 do
      local a1 = from + (to - from) * i / segs
      local a2 = from + (to - from) * (i + 1) / segs
      Line(math.cos(a1) * radius, math.sin(a1) * radius, math.cos(a2) * radius, math.sin(a2) * radius, color, thick)
    end
  end
  Circle(R, C.line)
  Circle(R + SLOT / 2 + 6, { C.line[1], C.line[2], C.line[3], 0.2 })
  for g, a in pairs(ARCS) do
    Circle(R + SLOT / 2 + 6, { C.accent[1], C.accent[2], C.accent[3], 0.55 }, a[1] + 4 * (a[2] < a[1] and 1 or -1),
      a[2] - 4 * (a[2] < a[1] and 1 or -1), 24, 2)
    local mid = math.rad((a[1] + a[2]) / 2)
    local lbl = ns.Text(ring, 10, C.dim)
    local lr = R + SLOT / 2 + 18
    lbl:SetPoint("CENTER", ring, "TOPLEFT", cx + math.cos(mid) * lr, cy + math.sin(mid) * lr)
    lbl:SetText(GROUP_LABEL[g])
    ring[g .. "Label"] = lbl
  end

  local orb = ns.Orb(ring, DISC, 0.85, "BACKGROUND", 0)
  orb:SetPoint("CENTER", ring, "TOPLEFT", cx, cy)

  -- Player model, or a round portrait when models are unavailable.
  local model = ns.Call(CreateFrame, "PlayerModel", nil, ring)
  local portrait
  if model then
    model:SetSize(DISC * 0.92, DISC * 0.92)
    model:SetPoint("CENTER", ring, "TOPLEFT", cx, cy)
    model:EnableMouse(true)
    local facing, startX = 0, nil
    model:SetScript("OnMouseDown", function() startX = GetCursorPosition() end)
    model:SetScript("OnMouseUp", function() startX = nil end)
    model:SetScript("OnUpdate", function(m)
      if not startX then return end
      local cxp = GetCursorPosition()
      facing = facing + (cxp - startX) / 120
      startX = cxp
      ns.Call(m.SetFacing, m, facing)
    end)
  else
    portrait = ring:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(DISC * 0.7, DISC * 0.7)
    portrait:SetPoint("CENTER", ring, "TOPLEFT", cx, cy)
  end

  local shipName = ns.Text(ring, 12, C.title)
  shipName:SetFont(ns.FONT_BOLD, 12, "")
  shipName:SetPoint("BOTTOM", ring, "BOTTOM", 0, 26)
  local shipSub = ns.Text(ring, 10, C.dim)
  shipSub:SetPoint("TOP", shipName, "BOTTOM", 0, -2)

  -- Slot buttons --------------------------------------------------------------------
  local buttons = {}
  local function MakeSlot(def)
    local b = CreateFrame("Button", nil, ring)
    b:SetSize(SLOT, SLOT)
    ns.Box(b, { 0.02, 0.03, 0.04, 0.9 }, C.border)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.empty = ns.Text(b, 9, C.dim)
    b.empty:SetPoint("CENTER")
    b.empty:SetText(def[2]:upper())
    b.ilvl = ns.Text(b, 10, C.title, "RIGHT", "OUTLINE")
    b.ilvl:SetPoint("BOTTOMRIGHT", -1, 2)
    b.dura = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b.dura:SetPoint("BOTTOMLEFT", 1, 1)
    b.dura:SetPoint("BOTTOMRIGHT", -1, 1)
    b.dura:SetHeight(2)
    b.broken = b:CreateTexture(nil, "OVERLAY", nil, 5)
    b.broken:SetAllPoints(b.icon)
    b.broken:SetColorTexture(C.hostile[1], C.hostile[2], C.hostile[3], 0.35)
    b.slot = def[1]
    b.def = def
    b:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      if not GameTooltip:SetInventoryItem("player", s.slot) then
        GameTooltip:SetText(s.def[2])
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end

  local function PlaceGroup(g)
    local list, vis = SLOTS[g], {}
    for _, def in ipairs(list) do
      local b = buttons[def[1]]
      local has = GetInventoryItemTexture("player", def[1]) ~= nil
      if not def.optional or has then vis[#vis + 1] = b; b:Show() else b:Hide() end
    end
    local a1, a2 = ARCS[g][1], ARCS[g][2]
    for i, b in ipairs(vis) do
      local t = #vis == 1 and 0.5 or (i - 1) / (#vis - 1)
      local a = math.rad(a1 + (a2 - a1) * t)
      b:ClearAllPoints()
      b:SetPoint("CENTER", ring, "TOPLEFT", cx + math.cos(a) * R, cy + math.sin(a) * R)
    end
  end

  for _, g in ipairs({ "high", "mid", "low" }) do
    for _, def in ipairs(SLOTS[g]) do buttons[def[1]] = MakeSlot(def) end
  end

  local function UpdateSlot(b)
    local slot = b.slot
    local tex = GetInventoryItemTexture("player", slot)
    if tex then
      b.icon:SetTexture(tex); b.icon:Show(); b.empty:Hide()
      local link = GetInventoryItemLink("player", slot)
      local q = GetInventoryItemQuality("player", slot)
      ns.SetBoxBorder(b, QualityColor(q))
      local il = ItemLevel(link)
      b.ilvl:SetText(il and tostring(il) or "")
      local cur, max = ns.Call(GetInventoryItemDurability, slot)
      cur, max = Plain(cur), Plain(max)
      if type(cur) == "number" and type(max) == "number" and max > 0 then
        local p = cur / max
        local c = p > 0.5 and C.heal or (p > 0.2 and C.neutral or C.hostile)
        b.dura:SetColorTexture(c[1], c[2], c[3], 0.9)
        b.dura:Show()
        b.broken:SetShown(cur == 0)
      else
        b.dura:Hide(); b.broken:Hide()
      end
    else
      b.icon:Hide(); b.empty:Show(); b.ilvl:SetText("")
      b.dura:Hide(); b.broken:Hide()
      ns.SetBoxBorder(b, C.border)
    end
  end

  -- Stat gauges ---------------------------------------------------------------------
  local col = CreateFrame("Frame", nil, f)
  col:SetPoint("TOPLEFT", RING_W + 1, -ns.HEADER - 1)
  col:SetPoint("BOTTOMRIGHT", -1, 1)
  local rows, heads = {}, {}

  local function Head(i)
    local h = heads[i]
    if not h then
      h = ns.Text(col, 10, C.accent, "LEFT")
      heads[i] = h
    end
    return h
  end
  local function Row(i)
    local r = rows[i]
    if not r then
      r = CreateFrame("Frame", nil, col)
      r:SetHeight(ROW_H)
      r.label = ns.Text(r, 11, C.text, "LEFT")
      r.label:SetPoint("TOPLEFT", 0, -2)
      r.value = ns.Text(r, 11, C.title, "RIGHT")
      r.value:SetPoint("TOPRIGHT", 0, -2)
      r.bar = CreateFrame("StatusBar", nil, r)
      r.bar:SetStatusBarTexture(ns.WHITE)
      r.bar:SetPoint("BOTTOMLEFT", 0, 2)
      r.bar:SetPoint("BOTTOMRIGHT", 0, 2)
      r.bar:SetHeight(3)
      r.bar:SetMinMaxValues(0, 1)
      local bg = r.bar:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(unpack(C.off))
      r:EnableMouse(true)
      r:SetScript("OnEnter", function(s)
        if not s.tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText(s.label:GetText() or "")
        GameTooltip:AddLine(s.tip, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      rows[i] = r
    end
    return r
  end

  local footer = ns.Text(col, 11, C.dim, "LEFT")
  footer:SetPoint("BOTTOMLEFT", 10, 8)
  local footerV = ns.Text(col, 13, C.title, "RIGHT")
  footerV:SetFont(ns.FONT_BOLD, 13, "")
  footerV:SetPoint("BOTTOMRIGHT", -10, 7)
  footer:SetText("AVERAGE ITEM LEVEL")

  local STAT_NAMES = { SPELL_STAT1_NAME or "Strength", SPELL_STAT2_NAME or "Agility",
    SPELL_STAT3_NAME or "Stamina", SPELL_STAT4_NAME or "Intellect" }
  local function Stat(i)
    local base, eff = ns.Call(UnitStat, "player", i)
    return Plain(eff) or Plain(base)
  end
  local function Num(fn, ...)
    if not fn then return nil end
    local v = Plain(ns.Call(fn, ...))
    return type(v) == "number" and v or nil
  end

  -- Builds { section, { label, valueText, fill 0-1, color, tip } ... } lists.
  local function Collect()
    local out = {}
    local lvl = Plain(UnitLevel("player")) or 1

    -- Resources: primary stat = powergrid, stamina = CPU.
    local best, bestI = nil, 1
    for _, i in ipairs({ 1, 2, 4 }) do
      local v = Stat(i)
      if v and (not best or v > best) then best, bestI = v, i end
    end
    local sta = Stat(3)
    local top = math.max(best or 0, sta or 0, 1) * 1.15
    out[#out + 1] = { "RESOURCES",
      { "Powergrid", Fmt(best), best and best / top, C.cap, STAT_NAMES[bestI] .. " (primary stat)" },
      { "CPU", Fmt(sta), sta and sta / top, C.accent, STAT_NAMES[3] },
    }

    -- Defense: shields = avoidance, armor, hull = max health.
    local dodge, parry, block = Num(GetDodgeChance), Num(GetParryChance), Num(GetBlockChance)
    local av = (dodge or 0) + (parry or 0) + (block or 0)
    local _, armor = ns.Call(UnitArmor, "player")
    armor = Plain(armor)
    local red = armor and C_PaperDollInfo and Num(C_PaperDollInfo.GetArmorEffectiveness, armor, lvl)
    local hull = Num(UnitHealthMax, "player")
    local absorb = Num(UnitGetTotalAbsorbs, "player")
    out[#out + 1] = { "DEFENSE",
      { "Shields", Pct(av), av / 100, C.shield,
        ("Dodge %s, parry %s, block %s%s"):format(Pct(dodge or 0), Pct(parry or 0), Pct(block or 0),
          (absorb and absorb > 0) and (", absorb " .. Fmt(absorb)) or "") },
      { "Armor", Fmt(armor) .. (red and ("  " .. Pct(red * 100)) or ""), red or 0, C.neutral,
        red and ("Physical damage reduced by " .. Pct(red * 100)) or "Armor" },
      { "Hull", Fmt(hull), hull and 1 or 0, C.hull, "Maximum health" },
    }

    -- Resistances, EVE damage types.
    local res, any = {}, false
    for _, d in ipairs({ { 6, "EM", "Arcane" }, { 2, "Thermal", "Fire" }, { 4, "Kinetic", "Frost" },
      { 3, "Explosive", "Nature" }, { 5, "Exotic", "Shadow" } }) do
      local base, eff = ns.Call(UnitResistance, "player", d[1])
      local v = Plain(eff) or Plain(base)
      if type(v) == "number" then
        if v > 0 then any = true end
        res[#res + 1] = { d[2], Fmt(v), math.min(v / math.max(lvl * 5, 1), 1), C.friendly, d[3] .. " resistance" }
      end
    end
    if any then out[#out + 1] = { "RESISTANCES", unpack(res) } end

    -- Navigation and targeting.
    local nav = { "NAVIGATION / TARGETING" }
    local _, run = ns.Call(GetUnitSpeed, "player")
    run = Plain(run)
    if type(run) == "number" and run > 0 then
      local p = run / 7 * 100
      nav[#nav + 1] = { "Velocity", ("%d%%"):format(math.floor(p + 0.5)), math.min(p / 200, 1), C.accent, "Run speed" }
    end
    local crit = math.max(Num(GetCritChance) or 0, Num(GetRangedCritChance) or 0,
      Num(GetSpellCritChance, 2) or 0)
    if GetCritChance then nav[#nav + 1] = { "Critical", Pct(crit), crit / 100, C.hostile, "Critical strike chance" } end
    local function Add(label, v, tip)
      if v then nav[#nav + 1] = { label, Pct(v), math.min(v / 100, 1), C.cast, tip } end
    end
    Add("Haste", Num(GetHaste), "Haste")
    local mastery = Num(GetMasteryEffect)
    if mastery and mastery > 0 then Add("Mastery", mastery, "Mastery effect") end
    local CRV = CR_VERSATILITY_DAMAGE_DONE or 29
    local vers = Num(GetCombatRatingBonus, CRV)
    if vers then Add("Versatility", vers + (Num(GetVersatilityBonus, CRV) or 0), "Damage and healing done bonus") end
    local leech = Num(GetLifesteal)
    if leech and leech > 0 then Add("Leech", leech, "Leech") end
    local avoid = Num(GetAvoidance)
    if avoid and avoid > 0 then Add("Avoidance", avoid, "Area damage avoidance") end
    local speed = Num(GetSpeed)
    if speed and speed > 0 then Add("Speed", speed, "Speed stat") end
    if #nav > 1 then out[#out + 1] = nav end
    return out
  end

  local function UpdateStats()
    for _, r in ipairs(rows) do r:Hide() end
    for _, h in ipairs(heads) do h:Hide() end
    local y, ri, hi = -8, 0, 0
    for _, sec in ipairs(Collect()) do
      hi = hi + 1
      local h = Head(hi)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", 10, y)
      h:SetText(sec[1])
      h:Show()
      y = y - SEC_H
      for j = 2, #sec do
        local d = sec[j]
        ri = ri + 1
        local r = Row(ri)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, y)
        r:SetPoint("TOPRIGHT", -10, y)
        r.label:SetText(d[1])
        r.value:SetText(d[2])
        r.bar:SetValue(math.max(0, math.min(d[3] or 0, 1)))
        ns.SetBarColor(r.bar, d[4] or C.accent)
        r.tip = d[5]
        r:Show()
        y = y - ROW_H
      end
      y = y - 4
    end
    local avg, equipped = ns.Call(GetAverageItemLevel)
    equipped = Plain(equipped) or Plain(avg)
    footerV:SetText(type(equipped) == "number" and ("%.1f"):format(equipped) or "-")
  end

  local function Refresh()
    for _, g in ipairs({ "high", "mid", "low" }) do PlaceGroup(g) end
    for _, b in pairs(buttons) do UpdateSlot(b) end
    local name = Plain(UnitName("player")) or ""
    local cls = Plain(UnitClass("player")) or ""
    local lvl = Plain(UnitLevel("player")) or ""
    shipName:SetText(name:upper())
    shipName:SetTextColor(unpack(ns.ClassColor("player")))
    shipSub:SetText(("Level %s %s"):format(lvl, cls))
    sub:SetText(cls:upper())
    UpdateStats()
  end

  local dirty = true
  f:SetScript("OnShow", function()
    if model then ns.Call(model.SetUnit, model, "player") end
    if portrait and SetPortraitTexture then ns.Call(SetPortraitTexture, portrait, "player") end
    dirty = true
  end)

  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY", "PLAYER_AVG_ITEM_LEVEL_UPDATE",
    "PLAYER_LEVEL_UP", "COMBAT_RATING_UPDATE", "MASTERY_UPDATE", "SPEED_UPDATE", "LIFESTEAL_UPDATE",
    "AVOIDANCE_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  pcall(ev.RegisterUnitEvent, ev, "UNIT_STATS", "player")
  pcall(ev.RegisterUnitEvent, ev, "UNIT_RESISTANCES", "player")
  pcall(ev.RegisterUnitEvent, ev, "UNIT_INVENTORY_CHANGED", "player")
  pcall(ev.RegisterUnitEvent, ev, "UNIT_MODEL_CHANGED", "player")
  ev:SetScript("OnEvent", function(_, e)
    if e == "UNIT_MODEL_CHANGED" and model and f:IsShown() then ns.Call(model.SetUnit, model, "player") end
    dirty = true
  end)
  ns.Every(0.5, "fitting", function()
    if dirty and f:IsShown() then dirty = false; Refresh() end
  end)

  ns.Mover(f, { key = "fitting", label = "Fitting", point = "CENTER", x = -40, y = 40 })

  function ns.ToggleFitting()
    f:SetShown(not f:IsShown())
  end
end, "fitting")
