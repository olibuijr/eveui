-- Module racks: Blizzard's own action buttons (so keybinds, paging, druid
-- forms, macros, cooldowns and drag-and-drop all keep working) restyled as
-- round EVE modules and laid out in staggered rows beside the HUD.
--   right rack: action bar 1 (bottom row), bars 2 and 3 above it
--   left rack:  stance bar and pet bar
-- Also hides the Blizzard bar art, micro menu and bag bar (the Neocom
-- replaces them) and draws an EVE-style experience line under the racks.
local ADDON, ns = ...
local C = ns.C

local MOD, PITCH, ROW, STAGGER = 40, 46, 44, 23

local RIGHT_ROWS = {
  { bar = "MainActionBar", prefix = "ActionButton", count = 12 },
  { bar = "MultiBarBottomLeft", prefix = "MultiBarBottomLeftButton", count = 12 },
  { bar = "MultiBarBottomRight", prefix = "MultiBarBottomRightButton", count = 12 },
}
local LEFT_ROWS = {
  { bar = "StanceBar", prefix = "StanceButton", count = 10 },
  { bar = "PetActionBar", prefix = "PetActionButton", count = 10 },
}
local SIDE_BARS = {
  { bar = "MultiBarRight", prefix = "MultiBarRightButton" },
  { bar = "MultiBarLeft", prefix = "MultiBarLeftButton" },
  { bar = "MultiBar5", prefix = "MultiBar5Button" },
  { bar = "MultiBar6", prefix = "MultiBar6Button" },
  { bar = "MultiBar7", prefix = "MultiBar7Button" },
}

local function zap(r) if r then r:SetAlpha(0) end end

local function CircleRegion(r, color)
  if not r then return end
  r:SetTexture(ns.CIRCLE)
  r:SetTexCoord(0, 1, 0, 1)
  r:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
  if r.SetBlendMode then r:SetBlendMode("BLEND") end
end

-- Round module skin for any Blizzard action-style button. sizePx = diameter.
local function SkinButton(b, sizePx)
  local px = ns.Px(b)
  local size = sizePx * px
  if not b.eveSkin then
    b.eveSkin = true
    zap(b.SlotArt); zap(b.SlotBackground); zap(b.BorderShadow); zap(b.Name); zap(b.Border)
    zap(b.NormalTexture); zap(b:GetNormalTexture())
    -- Square cast / interrupt / targeting animations; the cycle ring shows these.
    zap(b.InterruptDisplay); zap(b.SpellCastAnimFrame); zap(b.TargetReticleAnimFrame); zap(b.CooldownFlash)
    if b.UpdateButtonArt then
      hooksecurefunc(b, "UpdateButtonArt", function(self)
        zap(self:GetNormalTexture()); zap(self.NormalTexture); zap(self.SlotArt); zap(self.SlotBackground)
      end)
    end

    b.eveRing = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.eveRing:SetTexture(ns.CIRCLE)
    b.eveRing:SetVertexColor(C.border[1], C.border[2], C.border[3], 0.95)
    b.eveGap = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    b.eveGap:SetTexture(ns.CIRCLE)
    b.eveGap:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 0.45)

    b:SetHighlightTexture(ns.CIRCLE)
    CircleRegion(b:GetHighlightTexture(), { 1, 1, 1, 0.16 })
    b:SetPushedTexture(ns.CIRCLE)
    CircleRegion(b:GetPushedTexture(), { C.accent[1], C.accent[2], C.accent[3], 0.35 })
    if b.SetCheckedTexture then
      b:SetCheckedTexture(ns.CIRCLE)
      CircleRegion(b:GetCheckedTexture(), { C.accent[1], C.accent[2], C.accent[3], 0.3 })
    end
    CircleRegion(b.Flash, { C.hostile[1], C.hostile[2], C.hostile[3], 0.45 })
    CircleRegion(b.SpellHighlightTexture, { C.cap[1], C.cap[2], C.cap[3], 0.5 })
    CircleRegion(b.NewActionTexture, { C.accent[1], C.accent[2], C.accent[3], 0.4 })

    for _, cd in ipairs({ b.cooldown, b.chargeCooldown, b.lossOfControlCooldown }) do
      if cd then
        cd:SetSwipeTexture(ns.CIRCLE)
        cd:SetSwipeColor(0, 0, 0, 0.72)
        cd:SetDrawEdge(false)
        if cd.SetUseCircularEdge then cd:SetUseCircularEdge(true) end
      end
    end

    if b.IconMask then
      b.IconMask:SetTexture(ns.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    elseif b.icon then
      local m = b:CreateMaskTexture()
      m:SetTexture(ns.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetAllPoints(b.icon)
      b.icon:AddMaskTexture(m)
    end
  end

  b:SetSize(size, size)
  b.eveRing:ClearAllPoints()
  b.eveRing:SetPoint("TOPLEFT", -2 * px, 2 * px)
  b.eveRing:SetPoint("BOTTOMRIGHT", 2 * px, -2 * px)
  b.eveGap:ClearAllPoints()
  b.eveGap:SetPoint("TOPLEFT", -1 * px, 1 * px)
  b.eveGap:SetPoint("BOTTOMRIGHT", 1 * px, -1 * px)

  local icon = b.icon or b.Icon
  if icon then
    icon:ClearAllPoints()
    icon:SetAllPoints(b)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
  if b.IconMask then
    b.IconMask:ClearAllPoints()
    b.IconMask:SetAllPoints(b)
  end
  for _, r in ipairs({ b:GetHighlightTexture(), b:GetPushedTexture(), b.GetCheckedTexture and b:GetCheckedTexture(),
    b.Flash, b.SpellHighlightTexture, b.NewActionTexture }) do
    if r then r:ClearAllPoints(); r:SetAllPoints(b) end
  end
  for _, cd in ipairs({ b.cooldown, b.chargeCooldown, b.lossOfControlCooldown }) do
    if cd then cd:ClearAllPoints(); cd:SetAllPoints(b) end
  end
  if b.HotKey then
    ns.SetFont(b.HotKey, 11, "OUTLINE", b)
    b.HotKey:SetTextColor(C.text[1], C.text[2], C.text[3])
    b.HotKey:ClearAllPoints()
    b.HotKey:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3 * px, 3 * px)
    b.HotKey:SetJustifyH("RIGHT")
  end
  if b.Count then
    ns.SetFont(b.Count, 12, "OUTLINE", b)
    b.Count:ClearAllPoints()
    b.Count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2 * px, -2 * px)
  end
end
ns.SkinActionButton = SkinButton

-- The frame Blizzard positions for a button: its container when it has one.
local function Positioned(b)
  local p = b:GetParent()
  local n = p and p.GetName and p:GetName()
  if n and n:find("ButtonContainer") then return p end
  return b
end

ns.RegisterModule(function()
  local hud = ns.hud

  -- Blizzard art and the bits the Neocom replaces.
  if MainActionBar then
    zap(MainActionBar.BorderArt)
    zap(MainActionBar.EndCaps)
    ns.Ghost(MainActionBar.ActionBarPageNumber)
  end
  ns.Ghost(MicroMenuContainer)
  ns.Ghost(BagsBar)
  ns.Ghost(MainStatusTrackingBarContainer)
  ns.Ghost(SecondaryStatusTrackingBarContainer)
  ns.Ghost(StatusTrackingBarManager)

  -- The right rack needs action bars 2 and 3. Turning them on from addon code
  -- (Settings.SetValue / SetActionBarToggles / Show) runs Edit Mode's bar
  -- layout inside EveUI and taints it, which then blocks the bars from moving
  -- in combat. So only point the player at the setting.
  local function CheckBars()
    if EveUIDB.barsOff or EveUIDB.barsHinted then return end
    for _, name in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight" }) do
      local bar = _G[name]
      if bar and not bar:IsShown() then
        EveUIDB.barsHinted = true
        ns.Print("turn on Action Bars 2 and 3 (Options > Gameplay > Action Bars) to fill the right rack.")
        return
      end
    end
  end
  C_Timer.After(5, CheckBars)

  local function HideDividers()
    if not MainActionBar then return end
    for _, child in ipairs({ MainActionBar:GetChildren() }) do
      local n = child:GetName() or ""
      if not n:find("ButtonContainer") and child ~= MainActionBar.VehicleLeaveButton
        and not (child.IsObjectType and child:IsObjectType("CheckButton")) then
        child:SetAlpha(0)
      end
    end
    for _, r in ipairs({ MainActionBar:GetRegions() }) do r:SetAlpha(0) end
  end
  ns.OnLayout(HideDividers)

  local function MakeRack(name, rows, side)
    local maxCount = 0
    for _, r in ipairs(rows) do maxCount = math.max(maxCount, r.count) end
    local rack = CreateFrame("Frame", name, ns.root)
    rack:SetSize(maxCount * PITCH + STAGGER, #rows * ROW)
    rack.rows = rows
    for ri, row in ipairs(rows) do
      row.sockets = {}
      local y = (ri - 1) * ROW + ROW / 2
      local x0 = (ri % 2 == 0) and STAGGER or 0
      for i = 1, row.count do
        local s = CreateFrame("Frame", nil, rack)
        s:SetSize(MOD, MOD)
        local x
        if side == "right" then x = x0 + (i - 1) * PITCH + MOD / 2
        else x = rack:GetWidth() - (x0 + (i - 1) * PITCH + MOD / 2) end
        s:SetPoint("CENTER", rack, "BOTTOMLEFT", x, y)
        local ring = ns.Disk(s, MOD + 4, 1, "BACKGROUND", -8)
        ring:SetVertexColor(C.line[1], C.line[2], C.line[3], 0.55)
        ring:SetPoint("CENTER")
        local hole = ns.Disk(s, MOD + 2, 0.3, "BACKGROUND", -7)
        hole:SetPoint("CENTER")
        row.sockets[i] = s
      end
    end
    return rack
  end

  -- The racks hold Blizzard's protected buttons: they only move while the
  -- layout is unlocked, which is never in combat.
  local right = MakeRack("EveUIRackRight", RIGHT_ROWS, "right")
  ns.Mover(right, { key = "rackRight", label = "Module rack (right)", point = "BOTTOMLEFT", rel = hud,
    relPoint = "CENTER", x = 126, y = -100 })
  local left = MakeRack("EveUIRackLeft", LEFT_ROWS, "left")
  ns.Mover(left, { key = "rackLeft", label = "Module rack (left)", point = "BOTTOMRIGHT", rel = hud,
    relPoint = "CENTER", x = -126, y = -100 })

  local function LayoutRack(rack)
    for _, row in ipairs(rack.rows) do
      local bar = _G[row.bar]
      local shown = bar and bar:IsShown()
      for i = 1, row.count do
        local b = _G[row.prefix .. i]
        local s = row.sockets[i]
        if b then
          SkinButton(b, MOD)
          local p = Positioned(b)
          p:ClearAllPoints()
          p:SetPoint("CENTER", s, "CENTER", 0, 0)
          s:SetShown(shown == true and (b:IsShown() or row.bar ~= "StanceBar" and row.bar ~= "PetActionBar"))
        else
          s:Hide()
        end
      end
    end
  end

  local function LayoutSideBars()
    for _, sb in ipairs(SIDE_BARS) do
      for i = 1, 12 do
        local b = _G[sb.prefix .. i]
        if b then SkinButton(b, 36) end
      end
    end
  end

  local function Layout()
    LayoutRack(right)
    LayoutRack(left)
    LayoutSideBars()
  end
  ns.OnLayout(Layout)

  -- Re-apply whenever Blizzard lays its bars out again.
  for _, row in ipairs({ unpack(RIGHT_ROWS) }) do
    local bar = _G[row.bar]
    if bar then
      for _, m in ipairs({ "UpdateGridLayout", "Layout", "UpdateLayout" }) do
        if bar[m] then hooksecurefunc(bar, m, function() if not InCombatLockdown() then ns.Safe("rack", Layout)() end end) end
      end
      bar:HookScript("OnShow", function() ns.RunLayout() end)
      bar:HookScript("OnHide", function() ns.RunLayout() end)
    end
  end
  for _, row in ipairs(LEFT_ROWS) do
    local bar = _G[row.bar]
    if bar then
      for _, m in ipairs({ "UpdateGridLayout", "Layout", "UpdateLayout" }) do
        if bar[m] then hooksecurefunc(bar, m, function() if not InCombatLockdown() then ns.Safe("rack", Layout)() end end) end
      end
      bar:HookScript("OnShow", function() ns.RunLayout() end)
      bar:HookScript("OnHide", function() ns.RunLayout() end)
    end
  end
  Layout()

  -- Experience line -----------------------------------------------------------
  -- Spans both racks at their default spacing; movable on its own.
  local xa = CreateFrame("Frame", "EveUIXPAnchor", ns.root)
  xa:SetSize(left:GetWidth() + right:GetWidth() + 252, 22)
  ns.Mover(xa, { key = "xp", label = "Experience", point = "BOTTOMLEFT", rel = left, relPoint = "BOTTOMLEFT",
    x = 0, y = -26 })
  local xp = CreateFrame("StatusBar", "EveUIXP", ns.root)
  xp:SetHeight(3)
  xp:SetPoint("BOTTOMLEFT", xa, "BOTTOMLEFT", 0, 0)
  xp:SetPoint("BOTTOMRIGHT", xa, "BOTTOMRIGHT", 0, 0)
  xp:SetStatusBarTexture(ns.WHITE)
  xp:SetStatusBarColor(unpack(C.accent))
  local rested = CreateFrame("StatusBar", nil, xp)
  rested:SetAllPoints()
  rested:SetFrameLevel(xp:GetFrameLevel())
  rested:SetStatusBarTexture(ns.WHITE)
  rested:SetStatusBarColor(C.friendly[1], C.friendly[2], C.friendly[3], 0.35)
  local xbg = xp:CreateTexture(nil, "BACKGROUND")
  xbg:SetPoint("TOPLEFT", -1, 1)
  xbg:SetPoint("BOTTOMRIGHT", 1, -1)
  xbg:SetColorTexture(0, 0, 0, 0.7)
  local lvl = ns.Text(xp, 11, C.dim, "LEFT")
  lvl:SetPoint("BOTTOMLEFT", xp, "TOPLEFT", 0, 4)
  local val = ns.Text(xp, 11, C.dim, "RIGHT")
  val:SetPoint("BOTTOMRIGHT", xp, "TOPRIGHT", 0, 4)
  xp:EnableMouse(true)
  xp:SetHitRectInsets(0, 0, -8, -8)
  xp:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Experience")
    GameTooltip:AddDoubleLine("Current", ("%d / %d"):format(UnitXP("player"), UnitXPMax("player")), 1, 1, 1, 1, 1, 1)
    local r = GetXPExhaustion()
    if r then GameTooltip:AddDoubleLine("Rested", r, 1, 1, 1, 0.4, 0.6, 1) end
    GameTooltip:Show()
  end)
  xp:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local function UpdateXP()
    local cur, max = ns.Plain(UnitXP("player")) or 0, ns.Plain(UnitXPMax("player")) or 0
    local maxed = max == 0 or (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel())
    xp:SetShown(not maxed)
    if maxed then return end
    xp:SetMinMaxValues(0, max)
    xp:SetValue(cur)
    rested:SetMinMaxValues(0, max)
    rested:SetValue(math.min(cur + (GetXPExhaustion() or 0), max))
    lvl:SetText("LEVEL " .. UnitLevel("player"))
    val:SetFormattedText("%.1f%%", cur / max * 100)
  end
  local xev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do xev:RegisterEvent(e) end
  xev:SetScript("OnEvent", ns.Safe("xp", UpdateXP))
  ns.Safe("xp", UpdateXP)()
end)
