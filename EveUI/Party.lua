-- Fleet window (party frames): one secure row per party member with class
-- colour, health bar, health %, power line and out-of-range fade. Left-click
-- targets, right-click opens the unit menu. Hidden when solo or in a raid
-- (raids keep Blizzard's raid frames).
local ADDON, ns = ...
local C = ns.C

local W, ROW_H, TOP = 230, 34, ns.HEADER + 4
local VISIBILITY = "[group:raid] hide; [group:party] show; hide"

ns.RegisterModule(function()
  local f = ns.CreatePanel("EveUIFleet", ns.root, "Fleet", W, TOP + 4 * ROW_H + 4, "SecureHandlerStateTemplate")
  ns.Movable(f, "fleet", "TOPLEFT", "TOPLEFT", 64, -34, function(unlocked)
    if unlocked then UnregisterStateDriver(f, "visibility"); f:Show()
    else RegisterStateDriver(f, "visibility", VISIBILITY) end
  end)
  RegisterStateDriver(f, "visibility", VISIBILITY)

  local count = ns.Text(f, 12, C.dim, "RIGHT")
  count:SetPoint("TOPRIGHT", -10, -5)

  local rows = {}
  for i = 1, 4 do
    local unit = "party" .. i
    local r = CreateFrame("Button", "EveUIFleetRow" .. i, f, "SecureUnitButtonTemplate")
    r:SetSize(W - 8, ROW_H - 2)
    r:SetPoint("TOPLEFT", 4, -(TOP + (i - 1) * ROW_H))
    r:RegisterForClicks("AnyUp", "AnyDown")
    r:SetAttribute("unit", unit)
    r:SetAttribute("type1", "target")
    r:SetAttribute("type2", "togglemenu")
    RegisterUnitWatch(r)
    r.unit = unit

    local body = CreateFrame("Frame", nil, r)
    body:SetAllPoints()
    r.body = body
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    r.sel = body:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16)

    r.name = ns.Text(body, 13, C.text, "LEFT")
    r.name:SetPoint("TOPLEFT", 6, -3)
    r.name:SetWidth(W - 70)
    r.pct = ns.Text(body, 12, C.title, "RIGHT")
    r.pct:SetPoint("TOPRIGHT", -6, -3)

    r.hp = CreateFrame("StatusBar", nil, body)
    r.hp:SetPoint("BOTTOMLEFT", 6, 9)
    r.hp:SetPoint("BOTTOMRIGHT", -6, 9)
    r.hp:SetHeight(7)
    r.hp:SetStatusBarTexture(ns.WHITE)
    r.hp:SetMinMaxValues(0, 100)
    local bg = r.hp:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(ns.WHITE)
    ns.Gradient(bg, { 0, 0, 0, 0.5 }, { 1, 1, 1, 0.06 })
    ns.Bar3D(r.hp)

    r.pw = CreateFrame("StatusBar", nil, body)
    r.pw:SetPoint("TOPLEFT", r.hp, "BOTTOMLEFT", 0, -2)
    r.pw:SetPoint("TOPRIGHT", r.hp, "BOTTOMRIGHT", 0, -2)
    r.pw:SetHeight(3)
    r.pw:SetStatusBarTexture(ns.WHITE)
    r.pw:SetMinMaxValues(0, 100)
    ns.Bar3D(r.pw)
    rows[i] = r
  end

  local function Update()
    local n = 0
    for _, r in ipairs(rows) do
      local u = r.unit
      if UnitExists(u) then
        n = n + 1
        local cc = ns.ClassColor(u)
        r.name:SetText(UnitName(u))
        r.name:SetTextColor(unpack(cc))
        ns.SetBarColor(r.hp, C.health)
        pcall(r.hp.SetValue, r.hp, ns.HealthPct100(u))
        local pc = ns.PowerColor(u)
        ns.SetBarColor(r.pw, pc)
        pcall(r.pw.SetValue, r.pw, ns.PowerPct100(u))
        if ns.Plain(UnitIsConnected(u)) == false then
          r.pct:SetText("OFFLINE")
        elseif ns.Plain(UnitIsDeadOrGhost(u)) then
          r.pct:SetText("WRECK")
        else
          ns.SetHealthText(r.pct, u)
        end
        r.sel:SetShown(ns.Plain(UnitIsUnit(u, "target")) == true)
        local inRange = UnitInRange(u)
        if r.body.SetAlphaFromBoolean and ns.issecret(inRange) then
          r.body:SetAlphaFromBoolean(inRange, 1, 0.45)
        else
          r.body:SetAlpha(inRange == false and 0.45 or 1)
        end
      end
    end
    count:SetText(n > 0 and (n + 1) or "")
  end
  ns.Every(0.2, "fleet", Update)
end, "fleet")
