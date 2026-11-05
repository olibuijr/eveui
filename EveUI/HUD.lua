-- Ship HUD (the player unit frame): capacitor rings (power) in the middle,
-- health and shield (absorb) arcs over the top, speed gauge underneath, EVE
-- readouts on the left and the player cast bar above. The centre disk is a
-- secure unit button: left-click targets yourself, right-click opens your menu.
local ADDON, ns = ...
local C = ns.C

local GREY = "|cff808c93%s|r  "

ns.RegisterModule(function()
  local f = CreateFrame("Frame", "EveUIHUD", ns.root)
  f:SetSize(320, 270)
  ns.Movable(f, "hud", "BOTTOM", "BOTTOM", 0, 34)
  ns.hud = f
  -- Traditional style: the HUD stays as an invisible anchor (action bars and
  -- combat text are placed around it) but draws nothing.
  if ns.Classic and ns.Classic() then return end
  ns.hudVisual = true

  -- Two raised glass orbs: the wide gauge plate and the capacitor core.
  local back = ns.Orb(f, 214, 0.32, "BACKGROUND", -6)
  back:SetPoint("CENTER")
  local disk = ns.Orb(f, 118, 0.62, "BACKGROUND", -2, { 0.06, 0.10, 0.18 })
  disk:SetPoint("CENTER")

  local hasAbsorb = UnitGetTotalAbsorbs ~= nil
  local hull = ns.CreateArc(f, { radius = 89, thickness = 10, from = -116, to = 116, segments = 46, color = C.health, bars = true })
  local speed = ns.CreateArc(f, { radius = 89, thickness = 5, from = 146, to = 214, segments = 12, color = C.accent })
  local cap = ns.CreateArc(f, { radius = 47, thickness = 8, from = 0, to = 360, segments = 32, color = C.mana, bars = true })
  -- Shield (absorbs): a thin straight bar above the health text.
  local shield = CreateFrame("StatusBar", nil, f)
  shield:SetSize(150, 3)
  shield:SetPoint("BOTTOM", f, "CENTER", 0, 104)
  shield:SetStatusBarTexture(ns.WHITE)
  ns.Bar3D(shield)
  ns.SetBarColor(shield, C.shield)
  local sbg = shield:CreateTexture(nil, "BACKGROUND")
  sbg:SetAllPoints()
  sbg:SetColorTexture(1, 1, 1, 0.08)
  shield:SetShown(hasAbsorb)

  local capText = ns.Text(f, 20, C.title)
  capText:SetPoint("CENTER", 0, 5)
  local capLabel = ns.Text(f, 10, C.dim)
  capLabel:SetPoint("TOP", capText, "BOTTOM", 0, -2)

  local hpText = ns.Text(f, 13, C.text)
  hpText:SetPoint("BOTTOM", f, "CENTER", 0, 112)

  local readout = {}
  for i = 1, 3 do
    local l = ns.Text(f, 12, C.text, "RIGHT")
    l:SetPoint("RIGHT", f, "CENTER", -118, 34 - i * 16)
    readout[i] = l
  end

  local speedText = ns.Text(f, 12, C.accent)
  speedText:SetPoint("CENTER", 0, -68)
  local status = ns.Text(f, 11, C.hostile)
  status:SetPoint("CENTER", 0, -108)

  -- Module-cycle cast ring between the hull arc and the capacitor, open at
  -- the bottom for the speed readout; spell name and time above the hull.
  local cast = ns.CreateCast(f, "player", { radius = 71, thickness = 3, from = -150, to = 150,
    segments = 56, textSize = 12, barWidth = 150 })
  -- Name, time and slim bar sit on their own movable anchor; the ring stays
  -- on the HUD.
  local ca = CreateFrame("Frame", "EveUICastAnchor", ns.root)
  ca:SetSize(260, 34)
  ns.Mover(ca, { key = "cast", label = "Cast bar", point = "BOTTOM", rel = f, relPoint = "CENTER", x = 0, y = 122 })
  cast.text:SetPoint("BOTTOM", ca, "BOTTOM", 0, 8)
  ns.playerCast = cast

  -- Secure centre: click to target yourself, right-click for the unit menu.
  local click = CreateFrame("Button", "EveUIPlayerButton", f, "SecureUnitButtonTemplate")
  click:SetSize(110, 110)
  click:SetPoint("CENTER")
  click:RegisterForClicks("AnyUp", "AnyDown")
  click:SetAttribute("unit", "player")
  click:SetAttribute("type1", "target")
  click:SetAttribute("type2", "togglemenu")

  local function Update()
    local hpMax = ns.Plain(UnitHealthMax("player")) or 1
    hull:SetHealth("player")
    if hasAbsorb then
      shield:SetMinMaxValues(0, math.max(hpMax, 1))
      shield:SetValue(UnitGetTotalAbsorbs("player"))
    end

    local pc = ns.PowerColor("player")
    cap:SetColor(pc)
    cap:SetPower("player")
    capText:SetFormattedText("%d", UnitPower("player"))
    local _, tok = UnitPowerType("player")
    tok = ns.Plain(tok) or "POWER"
    capLabel:SetText(tok:upper())

    hpText:SetFormattedText("%s / %s", AbbreviateNumbers(UnitHealth("player")), AbbreviateNumbers(hpMax))
    if hasAbsorb then
      readout[1]:SetFormattedText(GREY:format("SHIELD") .. "%s", AbbreviateNumbers(UnitGetTotalAbsorbs("player")))
    end
    ns.SetHealthText(readout[2], "player", GREY:format("HEALTH") .. "%.0f%%")
    readout[3]:SetFormattedText(GREY:format(tok) .. "%d / %d", UnitPower("player"), UnitPowerMax("player"))

    local spd = ns.Plain(GetUnitSpeed("player")) or 0
    speed:SetValue(spd / 14)
    speedText:SetFormattedText("%.1f yd/s", spd)

    if UnitAffectingCombat("player") then
      status:SetText("IN COMBAT"); status:SetTextColor(unpack(C.hostile))
    elseif IsResting() then
      status:SetText("DOCKED"); status:SetTextColor(unpack(C.dim))
    else
      status:SetText("")
    end
  end

  ns.Every(0.1, "hud", Update)
end)
