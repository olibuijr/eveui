-- Overview: a table of nearby units (from nameplates). Click a row to target.
-- Rows are secure buttons, so they are only re-sorted out of combat; in
-- combat the order freezes but every row keeps updating.
local ADDON, ns = ...
local C = ns.C

local ROWS, ROW_H, W = 16, 20, 340
local TOP = ns.HEADER + 22
local MAX_PLATES = 40

local function Kind(unit)
  if ns.Plain(UnitIsDead(unit)) then return "Wreck" end
  local lvl = ns.Plain(UnitLevel(unit))
  local s = (lvl and lvl > 0) and ("Lv" .. lvl) or "Lv??"
  local class = ns.Plain(UnitClassification(unit))
  if class == "elite" or class == "rareelite" or class == "worldboss" then s = s .. "+" end
  local kind
  if ns.Plain(UnitIsPlayer(unit)) then kind = ns.Plain(UnitClass(unit)) else kind = ns.Plain(UnitCreatureType(unit)) end
  return kind and (s .. " " .. kind) or s
end

ns.RegisterModule(function()
  local f = ns.CreatePanel("EveUIOverview", ns.root, "Overview", W, TOP + ROWS * ROW_H + 6)
  ns.Movable(f, "overview", "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 16)

  local count = ns.Text(f, 12, C.dim, "RIGHT")
  count:SetPoint("TOPRIGHT", -10, -5)

  local COLS = { { "DIST", 22 }, { "NAME", 78 }, { "TYPE", 232 } }
  for _, col in ipairs(COLS) do
    local t = ns.Text(f, 11, C.dim, "LEFT")
    t:SetPoint("TOPLEFT", col[2], -(ns.HEADER + 6))
    t:SetText(col[1])
  end
  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(unpack(C.line))
  sep:SetPoint("TOPLEFT", 1, -(TOP - 2))
  sep:SetPoint("TOPRIGHT", -1, -(TOP - 2))
  sep:SetHeight(1)

  local empty = ns.Text(f, 12, C.dim)
  empty:SetPoint("TOP", 0, -(TOP + 4))
  empty:SetText("No contacts. Show nameplates with V / Shift+V.")

  local rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", "EveUIOverviewRow" .. i, f, "SecureActionButtonTemplate")
    r:SetSize(W - 2, ROW_H)
    r:SetPoint("TOPLEFT", 1, -(TOP + (i - 1) * ROW_H))
    r:RegisterForClicks("AnyUp", "AnyDown")
    r:SetAttribute("type", "target")
    r:HookScript("PostClick", function(self, button, down)
      if EveUIDB.debugClicks then
        ns.Print(("row %s unit=%s exists=%s down=%s target=%s"):format(self:GetName(), tostring(self:GetAttribute("unit")),
          tostring(ns.Plain(UnitExists(self:GetAttribute("unit") or ""))), tostring(down), tostring(ns.Plain(UnitName("target")))))
      end
    end)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexture(ns.WHITE)
    r.icon:SetSize(8, 8)
    r.icon:SetPoint("LEFT", 9, 0)
    r.dist = ns.Text(r, 12, C.text, "LEFT")
    r.dist:SetPoint("LEFT", 21, 0)
    r.dist:SetWidth(54)
    r.name = ns.Text(r, 12, C.text, "LEFT")
    r.name:SetPoint("LEFT", 77, 0)
    r.name:SetWidth(150)
    r.kind = ns.Text(r, 12, C.dim, "LEFT")
    r.kind:SetPoint("LEFT", 231, 0)
    r.kind:SetWidth(W - 236)
    r:SetAlpha(0)
    rows[i] = r
  end

  local active, list, keys, used = {}, {}, {}, {}

  -- Out of combat: order visible units by range, then give leftover rows
  -- unused nameplate tokens so units that appear mid-combat still get a row.
  local function Scan()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
      if token then active[token] = true end
    end
  end

  local function Sort()
    Scan()
    if InCombatLockdown() then return end
    wipe(list); wipe(keys); wipe(used)
    for token in pairs(active) do
      if UnitExists(token) then
        list[#list + 1] = token
        local name = ns.Plain(UnitName(token)) or ""
        keys[token] = { (ns.Range(token)), ns.Plain(UnitCanAttack("player", token)) and 0 or 1, name }
      end
    end
    table.sort(list, function(a, b)
      local x, y = keys[a], keys[b]
      if x[1] ~= y[1] then return x[1] < y[1] end
      if x[2] ~= y[2] then return x[2] < y[2] end
      return x[3] < y[3]
    end)
    for _, t in ipairs(list) do used[t] = true end
    local spare = 1
    for i, r in ipairs(rows) do
      local t = list[i]
      if not t then
        while used["nameplate" .. spare] do spare = spare + 1 end
        t = "nameplate" .. spare
        spare = spare + 1
      end
      used[t] = true
      r.unit = t
      -- This client won't target hostiles by nameplate token, so target by
      -- name (plain out of combat); fall back to the token otherwise.
      local name = ns.Plain(UnitName(t))
      if type(name) == "string" and name ~= "" then
        r:SetAttribute("type", "macro")
        r:SetAttribute("macrotext", "/targetexact " .. name)
      else
        r:SetAttribute("type", "target")
        r:SetAttribute("macrotext", nil)
      end
      r:SetAttribute("unit", t)
    end
    f:SetHeight(TOP + math.max(math.min(#list, ROWS), 1) * ROW_H + 6)
  end

  local function Draw()
    local n = 0
    for token in pairs(active) do if UnitExists(token) then n = n + 1 end end
    count:SetText(n > 0 and n or "")
    empty:SetShown(n == 0)
    -- In combat the panel can't grow (secure rows), so rows past its height stay hidden.
    local fit = math.floor((f:GetHeight() - TOP - 6) / ROW_H + 0.5)
    for i, r in ipairs(rows) do
      local u = r.unit
      if u and i <= fit and UnitExists(u) then
        local c = ns.ReactionColor(u)
        local dead = ns.Plain(UnitIsDead(u))
        r.icon:SetVertexColor(c[1], c[2], c[3], dead and 0.4 or 1)
        r.icon:SetRotation(ns.Plain(UnitIsPlayer(u)) and math.pi / 4 or 0)
        ns.SetUnitName(r.name, u)
        if dead then r.name:SetTextColor(unpack(C.dim)) else r.name:SetTextColor(c[1], c[2], c[3]) end
        local _, label = ns.Range(u)
        r.dist:SetText(label)
        r.kind:SetText(Kind(u))
        r.sel:SetShown(ns.Plain(UnitIsUnit(u, "target")) == true)
        r:SetAlpha(1)
      else
        r:SetAlpha(0)
      end
    end
  end

  f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  f:SetScript("OnEvent", function(_, event, unit)
    active[unit] = event == "NAME_PLATE_UNIT_ADDED" or nil
  end)
  for i = 1, MAX_PLATES do
    if UnitExists("nameplate" .. i) then active["nameplate" .. i] = true end
  end

  ns.Every(1, "overview sort", Sort)
  ns.Every(0.25, "overview draw", Draw)
end, "overview")
