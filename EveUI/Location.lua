-- Location panel (top right): the minimap as a square EVE window with zone
-- title, tracking/mail/queue icons and a system readout (coordinates,
-- framerate and latency, durability, wealth, clocks). Also parks the
-- player's buffs and debuffs to its left.
local ADDON, ns = ...
local C = ns.C

local MAP, PAD, ROW = 240, 4, 18
local INFO = { "COORDINATES", "PERFORMANCE", "DURABILITY", "WEALTH", "TIME" }

local function Money(c)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return ("|cffe6c35c%d|rg |cffc0c8cc%02d|rs |cffc8875a%02d|rc"):format(g, s, k) end
  if s > 0 then return ("|cffc0c8cc%d|rs |cffc8875a%02d|rc"):format(s, k) end
  return ("|cffc8875a%d|rc"):format(k)
end

local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
local function Durability()
  local low
  for _, slot in ipairs(SLOTS) do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then
      local p = cur / max
      if not low or p < low then low = p end
    end
  end
  return low
end

ns.RegisterModule(function()
  local W = MAP + 2 * PAD + 2
  local H = ns.HEADER + PAD + MAP + PAD + #INFO * ROW + 8
  local f = ns.CreatePanel("EveUILocation", ns.root, "Location", W, H)
  ns.Movable(f, "location", "TOPRIGHT", "TOPRIGHT", -16, -16)
  f:SetFrameStrata("LOW")

  -- Minimap ------------------------------------------------------------------
  local holder = CreateFrame("Frame", nil, f)
  holder:SetSize(MAP, MAP)
  holder:SetPoint("TOP", 0, -(ns.HEADER + PAD))

  local function PlaceMinimap()
    Minimap.eveLock = true
    Minimap:SetParent(holder)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", holder, "CENTER")
    Minimap:SetSize(MAP, MAP)
    Minimap:SetScale(1)
    Minimap.eveLock = nil
  end
  PlaceMinimap()
  Minimap:SetMaskTexture(ns.WHITE)
  if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(0) end
  if Minimap.SetQuestBlobRingScalar then Minimap:SetQuestBlobRingScalar(0) end
  hooksecurefunc(Minimap, "SetPoint", function(self)
    if not self.eveLock and not InCombatLockdown() then PlaceMinimap() end
  end)
  ns.OnLayout(PlaceMinimap)

  for _, r in ipairs({ MinimapCompassTexture, MinimapBackdrop, MinimapBorder, MinimapBorderTop }) do
    if r then r:SetAlpha(0) end
  end
  for _, b in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut, Minimap.ZoomHitArea, GameTimeFrame,
    TimeManagerClockButton, ExpansionLandingPageMinimapButton, MinimapCluster.ZoneTextButton,
    MinimapCluster.BorderTop, MinimapZoomIn, MinimapZoomOut }) do
    ns.Hide(b)
  end
  MinimapCluster:SetAlpha(0)
  MinimapCluster:EnableMouse(false)

  Minimap:EnableMouseWheel(true)
  Minimap:SetScript("OnMouseWheel", function(self, d)
    local z = self:GetZoom() + (d > 0 and 1 or -1)
    self:SetZoom(math.max(0, math.min(self:GetZoomLevels() - 1, z)))
  end)

  -- Header icons: tracking at the right of the title bar, mail and other
  -- indicators in the map's top-left corner, the queue eye bottom-left.
  local tracking = MinimapCluster.Tracking
  if tracking then
    tracking:SetParent(f)
    tracking:ClearAllPoints()
    tracking:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -1)
    tracking:SetSize(20, 20)
    tracking:SetAlpha(0.8)
    if tracking.Background then tracking.Background:SetAlpha(0) end
    ns.SteelArt(tracking)
  end
  local ind = MinimapCluster.IndicatorFrame
  if ind then
    ind:SetParent(holder)
    ind:ClearAllPoints()
    ind:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -4)
    -- Mail / crafting-order icons: steel, re-applied when Blizzard swaps them.
    local function SteelInd() ns.SteelArt(ind) end
    SteelInd()
    for _, c in ipairs({ ind:GetChildren() }) do c:HookScript("OnShow", SteelInd) end
  end
  if AddonCompartmentFrame then
    AddonCompartmentFrame:SetParent(f)
    AddonCompartmentFrame:ClearAllPoints()
    AddonCompartmentFrame:SetPoint("RIGHT", tracking or f, tracking and "LEFT" or "TOPRIGHT", -4, 0)
    AddonCompartmentFrame:SetScale(0.8)
    ns.SteelArt(AddonCompartmentFrame)
  end
  local function PlaceQueue()
    if QueueStatusButton then
      QueueStatusButton:SetParent(holder)
      QueueStatusButton:ClearAllPoints()
      QueueStatusButton:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 2, 2)
      QueueStatusButton:SetScale(0.75)
      QueueStatusButton:SetFrameLevel(holder:GetFrameLevel() + 10)
    end
  end
  PlaceQueue()
  ns.OnLayout(PlaceQueue)

  -- Zone title ---------------------------------------------------------------
  local subzone = ns.Text(f, 11, C.dim, "RIGHT")
  subzone:SetPoint("TOPRIGHT", -26, -6)
  subzone:SetWidth(110)
  local function Zone()
    f.title:SetText((GetZoneText() or ""):upper())
    local pvp = (C_PvP and C_PvP.GetZonePVPInfo or GetZonePVPInfo or function() end)()
    -- EVE security colours: cyan for safe space, white for contested, red
    -- for hostile; no gold.
    if pvp == "sanctuary" or pvp == "friendly" then f.title:SetTextColor(unpack(C.accent))
    elseif pvp == "hostile" or pvp == "combat" then f.title:SetTextColor(unpack(C.hostile))
    else f.title:SetTextColor(unpack(C.title)) end
    local sz = GetMinimapZoneText()
    subzone:SetText(sz ~= GetZoneText() and sz or "")
  end
  local zev = CreateFrame("Frame")
  for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do zev:RegisterEvent(e) end
  zev:SetScript("OnEvent", ns.Safe("zone", Zone))
  ns.Safe("zone", Zone)()

  -- System readout -----------------------------------------------------------
  local top = ns.HEADER + PAD + MAP + PAD + 4
  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(unpack(C.line))
  sep:SetPoint("TOPLEFT", 1, -(top - 3))
  sep:SetPoint("TOPRIGHT", -1, -(top - 3))
  sep:SetHeight(1)
  local values = {}
  for i, label in ipairs(INFO) do
    local l = ns.Text(f, 11, C.dim, "LEFT")
    l:SetPoint("TOPLEFT", 10, -(top + (i - 1) * ROW + 2))
    l:SetText(label)
    local v = ns.Text(f, 12, C.text, "RIGHT")
    v:SetPoint("TOPRIGHT", -10, -(top + (i - 1) * ROW + 1))
    values[label] = v
  end

  local function Info()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y
    if pos then x, y = pos:GetXY() end
    x, y = ns.Plain(x), ns.Plain(y)
    values.COORDINATES:SetText(x and ("%.1f, %.1f"):format(x * 100, y * 100) or "-")
    local _, _, home, world = GetNetStats()
    values.PERFORMANCE:SetFormattedText("%d fps  |cff808c93·|r  %d ms", GetFramerate(), math.max(home or 0, world or 0))
    local d = Durability()
    if d then
      local col = d < 0.25 and "|cffeb4538" or d < 0.5 and "|cfff5b838" or "|cffdbe3e8"
      values.DURABILITY:SetText(("%s%d%%|r"):format(col, d * 100))
    else
      values.DURABILITY:SetText("-")
    end
    values.WEALTH:SetText(Money(GetMoney()))
    local h, m = GetGameTime()
    values.TIME:SetFormattedText("%s  |cff808c93server|r %02d:%02d", date("%H:%M"), h, m)
  end
  ns.Every(1, "location info", Info)

  -- Buffs, debuffs and the quest tracker hang off movable EveUI anchors, so
  -- dragging never touches the Blizzard frames from addon code; the next
  -- layout pass (out of combat) re-anchors them with the plain C calls.
  -- Each anchor takes the on-screen size of its Blizzard frame when unlocked.
  local function Match(anchor, bf, w, h)
    if bf and bf:GetWidth() > 0 then
      local k = bf:GetEffectiveScale() / anchor:GetEffectiveScale()
      w, h = math.max(bf:GetWidth() * k, 60), math.max(bf:GetHeight() * k, 30)
    end
    anchor:SetSize(w, h)
  end
  local buffs = CreateFrame("Frame", "EveUIBuffAnchor", ns.root)
  buffs:SetSize(360, 90)
  ns.Mover(buffs, { key = "buffs", label = "Buffs", point = "TOPRIGHT", rel = f, relPoint = "TOPLEFT", x = -14, y = 0,
    onUnlock = function(on) if on then Match(buffs, BuffFrame, 360, 90) end end })

  local tracker = CreateFrame("Frame", "EveUITrackerAnchor", ns.root)
  tracker:SetSize(260, 300)
  ns.Mover(tracker, { key = "tracker", label = "Quest tracker",
    default = function() return "TOPRIGHT", f, "BOTTOMRIGHT", 0, -(12 + (ns.mapButtonRow or 0)) end,
    onUnlock = function(on) if on then Match(tracker, ObjectiveTrackerFrame, 260, 300) end end })

  local function PlaceAuras()
    if BuffFrame then
      ns.Move(BuffFrame, "TOPRIGHT", buffs, "TOPRIGHT", 0, 0)
    end
    if DebuffFrame and BuffFrame then
      ns.Move(DebuffFrame, "TOPRIGHT", BuffFrame, "BOTTOMRIGHT", 0, -10 * ns.Px(DebuffFrame))
    end
  end
  ns.OnLayout(PlaceAuras)

  local function PlaceTracker()
    local t = ObjectiveTrackerFrame
    if not t then return end
    if InCombatLockdown() and t:IsProtected() then return end
    if not ns.Layout().pos.tracker and not InCombatLockdown() then ns.ApplyPos(tracker) end
    t.eveLock = true
    ns.Move(t, "TOPRIGHT", tracker, "TOPRIGHT", 0, 0)
    t.eveLock = nil
  end
  if ObjectiveTrackerFrame then
    hooksecurefunc(ObjectiveTrackerFrame, "SetPoint", function(self)
      if not self.eveLock then PlaceTracker() end
    end)
  end
  PlaceTracker()
  ns.PlaceTracker = PlaceTracker
  ns.OnLayout(PlaceTracker)
end)
