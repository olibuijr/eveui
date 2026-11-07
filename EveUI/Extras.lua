-- The rest of Blizzard's HUD in EVE style: window placement beside the
-- Neocom, tooltip anchor, error / raid warning / zone text, mirror timers
-- (breath, fatigue), the extra action and zone ability buttons, the vehicle
-- bar, loot window and rolls, alerts, the talking head, the durability
-- figure, reputation, minimap buttons and boss frames.
local ADDON, ns = ...
local C = ns.C
ns.extrasLoaded = true

local function zap(r) if r then r:SetAlpha(0) end end
local function px() return ns.Px(UIParent) end

-- Hide every texture region of a frame (not children).
local function StripTextures(f, keep)
  if not f then return end
  for _, r in ipairs({ f:GetRegions() }) do
    if r:IsObjectType("Texture") and not (keep and keep[r]) then r:SetAlpha(0) end
  end
end
ns.StripTextures = StripTextures

-- Remove a texture for good: clear it now and whenever Blizzard re-sets it.
-- (Alpha alone is undone by intro animations.)
local function Blank(r)
  if not r or r.eveBlank then return end
  r.eveBlank = true
  r:SetTexture(nil)
  local busy
  local function Clear(self)
    if busy then return end
    busy = true; self:SetTexture(nil); busy = false
  end
  hooksecurefunc(r, "SetTexture", Clear)
  hooksecurefunc(r, "SetAtlas", Clear)
end
ns.Blank = Blank

-- A flat EVE panel behind a frame (on its own child so the frame's art can go).
local function Panel(f, bg, border)
  if not f or f.evePanel then return f and f.evePanel end
  local p = CreateFrame("Frame", nil, f)
  p:SetAllPoints()
  p:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
  ns.Box(p, bg or C.panel, border or C.border, ns.Px(f))
  f.evePanel = p
  return p
end
ns.Panel = Panel

-- Windows: keep left-side panels clear of the Neocom strip ------------------------

local function NeocomWidth()
  if not (EveUIDB and EveUIDB.neocom ~= false) then return 0 end
  if ns.NeocomSide and ns.NeocomSide() == "right" then return 0 end
  return (44 + 8) * px()
end

local function ShiftPanels()
  local off = NeocomWidth()
  if off == 0 then return end
  -- Loot window: not a managed panel; keep it clear of the strip too.
  local lf = LootFrame
  if lf and lf:IsShown() and not InCombatLockdown() then
    local l = lf:GetLeft()
    if l and l * lf:GetEffectiveScale() < off * UIParent:GetEffectiveScale() then
      local p, rel, rp, x, y = lf:GetPoint(1)
      if p then lf:SetPoint(p, rel, rp, (x or 0) + off / (lf:GetScale() or 1), y) end
    end
  end
  for _, area in ipairs({ "left", "center", "doublewide", "fullscreen" }) do
    local f = GetUIPanel and GetUIPanel(area)
    if f and not (f.IsProtected and f:IsProtected() and InCombatLockdown()) then
      local p, rel, rp, x, y = f:GetPoint(1)
      if rel == UIParent and p and p:find("LEFT") and f.eveShiftX ~= x then
        f:SetPoint(p, rel, rp, x + off, y)
        f.eveShiftX = x + off
      end
    end
  end
end

-- Tooltip: default anchor above the Overview panel, clear of the HUD. -------------

local function TooltipAnchor()
  hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt)
    if tt:IsForbidden() then return end
    local anchor = EveUIOverview and EveUIOverview:IsShown() and EveUIOverview
    tt:ClearAllPoints()
    if anchor then
      tt:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
    else
      tt:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16 * px(), 200 * px())
    end
  end)
end

-- Messages: errors, raid warnings, boss emotes, zone text. -------------------------

local function Messages()
  local p = px()
  if UIErrorsFrame then
    UIErrorsFrame:ClearAllPoints()
    UIErrorsFrame:SetPoint("TOP", UIParent, "TOP", 0, -410 * p)
    UIErrorsFrame:SetFont(ns.FONT, 15 * p, "")
    UIErrorsFrame:SetShadowOffset(p, -p)
    UIErrorsFrame:SetShadowColor(0, 0, 0, 1)
  end
  for _, f in ipairs({ RaidWarningFrame, RaidBossEmoteFrame }) do
    if f then
      local name = f:GetName()
      for i = 1, 2 do
        local fs = f["slot" .. i] or _G[name .. "Slot" .. i]
        if fs and fs.SetFont then
          fs:SetFont(ns.FONT, 20 * p, "OUTLINE")
        end
      end
    end
  end
  if RaidWarningFrame then
    RaidWarningFrame:ClearAllPoints()
    RaidWarningFrame:SetPoint("TOP", UIParent, "TOP", 0, -450 * p)
  end
  if RaidBossEmoteFrame then
    RaidBossEmoteFrame:ClearAllPoints()
    RaidBossEmoteFrame:SetPoint("TOP", UIParent, "TOP", 0, -510 * p)
  end
  -- Zone text: thin capitals like EVE's system-entry banner.
  local zone = {
    { ZoneTextString, 30 }, { SubZoneTextString, 20 }, { PVPInfoTextString, 14 }, { PVPArenaTextString, 14 },
    { AutoFollowStatusText, 14 },
  }
  for _, z in ipairs(zone) do
    if z[1] and z[1].SetFont then
      z[1]:SetFont(ns.FONT, z[2] * p, "")
      z[1]:SetShadowOffset(p, -p)
      z[1]:SetShadowColor(0, 0, 0, 1)
    end
  end
  -- Zone colours: Blizzard's green / gold / red become EVE cyan / white / red.
  for _, z in ipairs(zone) do
    local fs = z[1]
    if fs and fs.SetTextColor then
      local busy
      local function Fix(self, r, g, b)
        if busy then return end
        if r == nil then r, g, b = self:GetTextColor() end
        if r == nil or ns.issecret(r) then return end
        local c
        if g > 0.8 and r < 0.5 and b < 0.5 then c = C.accent              -- friendly green
        elseif r > 0.8 and g > 0.5 and b < 0.35 then c = C.title          -- contested gold
        elseif r > 0.8 and g < 0.35 and b < 0.35 then c = C.hostile end   -- hostile red
        if c then busy = true; self:SetTextColor(c[1], c[2], c[3]); busy = false end
      end
      hooksecurefunc(fs, "SetTextColor", Fix)
      Fix(fs)
    end
  end
  -- A short cyan hairline under the zone name, like EVE's system banner.
  if ZoneTextString and ZoneTextFrame and not ZoneTextFrame.eveLine then
    local line = ZoneTextFrame:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    line:SetSize(160 * p, p)
    line:SetPoint("TOP", ZoneTextString, "BOTTOM", 0, -4 * p)
    ZoneTextFrame.eveLine = line
  end
  for _, f in ipairs({ ZoneTextFrame, SubZoneTextFrame }) do
    f:HookScript("OnShow", function()
      for _, fs in ipairs({ ZoneTextString, SubZoneTextString }) do
        local t = fs and fs:GetText()
        if t and not ns.issecret(t) then fs:SetText(t:upper()) end
      end
    end)
  end
end

-- Mirror timers (breath, fatigue, feign death) ----------------------------------

local MIRROR_COLORS = { BREATH = C.friendly, EXHAUSTION = C.cap, FEIGNDEATH = C.dim, DEATH = C.hostile }

local function SkinMirror(t)
  if not t or t.eveSkin then return end
  t.eveSkin = true
  local name = t:GetName()
  local bar = t.StatusBar or (name and _G[name .. "StatusBar"])
  StripTextures(t)
  zap(t.Border); zap(t.TextBorder)
  if bar then
    StripTextures(bar)
    local busy
    local function Fill(self)
      if busy then return end
      busy = true
      self:SetStatusBarTexture(ns.WHITE)
      self:GetStatusBarTexture():SetAlpha(1)
      local c = MIRROR_COLORS[t.timer or ""] or C.accent
      self:SetStatusBarColor(c[1], c[2], c[3])
      busy = false
    end
    hooksecurefunc(bar, "SetStatusBarTexture", Fill)
    hooksecurefunc(bar, "SetStatusBarColor", Fill)
    Fill(bar)
    local p = ns.Px(bar)
    local holder = CreateFrame("Frame", nil, bar)
    holder:SetPoint("TOPLEFT", -p, p)
    holder:SetPoint("BOTTOMRIGHT", p, -p)
    holder:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    ns.Box(holder, { 0, 0, 0, 0.7 }, C.border, p)
  end
  local text = t.Text or (name and _G[name .. "Text"])
  if text then
    ns.SetFont(text, 11, "OUTLINE", t)
    text:SetTextColor(unpack(C.title))
    if bar then
      text:ClearAllPoints()
      text:SetPoint("CENTER", bar, "CENTER", 0, 0)
      text:SetDrawLayer("OVERLAY", 7)
      if text:GetParent() ~= bar then
        -- Keep the label above the fill.
        local top = CreateFrame("Frame", nil, bar)
        top:SetAllPoints()
        top:SetFrameLevel(bar:GetFrameLevel() + 2)
        text:SetParent(top)
      end
    end
  end
end

local function MirrorTimers()
  local function SkinAll()
    local list = MirrorTimerContainer and MirrorTimerContainer.mirrorTimers
    for _, c in ipairs(list or {}) do SkinMirror(c) end
    for i = 1, 3 do SkinMirror(_G["MirrorTimer" .. i]) end
  end
  SkinAll()
  if MirrorTimerContainer then
    if MirrorTimerContainer.SetupTimer then hooksecurefunc(MirrorTimerContainer, "SetupTimer", SkinAll) end
    ns.Move(MirrorTimerContainer, "TOP", UIParent, "TOP", 0, -326 * px())
  end
  if MirrorTimer_Show then hooksecurefunc("MirrorTimer_Show", SkinAll) end
end

-- Extra action button and zone abilities ---------------------------------------

local function ExtraButtons()
  -- Skinning resizes secure buttons, which the game blocks in combat: wait
  -- for combat to end instead.
  local waiting
  local Skin
  local function Later()
    if waiting then return end
    waiting = CreateFrame("Frame")
    waiting:RegisterEvent("PLAYER_REGEN_ENABLED")
    waiting:SetScript("OnEvent", function(self)
      self:UnregisterAllEvents(); waiting = nil
      ns.Safe("extra", Skin)()
    end)
  end
  function Skin()
    if InCombatLockdown() then return Later() end
    local b = ExtraActionButton1
    if b then
      zap(b.style)
      if ns.SkinActionButton then ns.SkinActionButton(b, 52) end
    end
    local z = ZoneAbilityFrame
    if z then
      zap(z.Style)
      local cont = z.SpellButtonContainer
      if cont and cont.EnumerateActive then
        for btn in cont:EnumerateActive() do
          if not btn.eveSkin and ns.SkinActionButton then
            if btn.Icon and not btn.icon then btn.icon = btn.Icon end
            if btn.Cooldown and not btn.cooldown then btn.cooldown = btn.Cooldown end
            zap(btn.NormalTexture)
            ns.SkinActionButton(btn, 48)
          end
        end
      end
    end
  end
  Skin()
  if ExtraActionBarFrame then ExtraActionBarFrame:HookScript("OnShow", ns.Safe("extra", Skin)) end
  if ZoneAbilityFrame then
    ZoneAbilityFrame:HookScript("OnShow", ns.Safe("zone", Skin))
    if ZoneAbilityFrame.UpdateDisplayedZoneAbilities then
      hooksecurefunc(ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", ns.Safe("zone", Skin))
    end
  end
end

-- Vehicle / override bar ---------------------------------------------------------

local function Vehicle()
  local o = OverrideActionBar
  if o then
    local function Skin()
      if o.eveSkin then return end
      o.eveSkin = true
      StripTextures(o)
      for _, k in ipairs({ "EndCapL", "EndCapR", "_BG", "Divider1", "Divider2", "Divider3", "MicroBGL", "MicroBGR",
        "_MicroBGMid", "ButtonBGL", "ButtonBGR", "_ButtonBGMid", "PitchOverlay", "PitchButtonBG", "LeaveButtonBG",
        "HealthBarBG", "PowerBarBG", "HealthBarOverlay", "PowerBarOverlay" }) do zap(o[k]) end
      Panel(o, { 0.02, 0.03, 0.04, 0.82 }, C.border)
      for i = 1, 6 do
        local b = _G["OverrideActionBarButton" .. i]
        if b and ns.SkinActionButton then ns.SkinActionButton(b, 44) end
      end
      for _, bar in ipairs({ o.healthBar, o.powerBar, OverrideActionBarHealthBar, OverrideActionBarPowerBar }) do
        if bar and bar.SetStatusBarTexture then bar:SetStatusBarTexture(ns.WHITE) end
      end
      local xp = o.xpBar or OverrideActionBarExpBar
      if xp then StripTextures(xp); if xp.SetStatusBarTexture then xp:SetStatusBarTexture(ns.WHITE) end end
    end
    o:HookScript("OnShow", ns.Safe("vehicle", Skin))
    if o:IsShown() then ns.Safe("vehicle", Skin)() end
  end
  -- Leave-vehicle / taxi button: round module beside the HUD.
  local leave = MainMenuBarVehicleLeaveButton
  if leave and ns.SkinActionButton and not leave.eveSkin then
    if leave.GetNormalTexture and leave:GetNormalTexture() and not leave.icon then
      leave.icon = leave:GetNormalTexture()
    end
    pcall(ns.SkinActionButton, leave, 36)
    local function Place()
      if InCombatLockdown() or not ns.hud then return end
      ns.Move(leave, "CENTER", ns.hud, "CENTER", -128, 110)
    end
    -- Edit Mode re-anchors it with the action bars; put it back each time.
    hooksecurefunc(leave, "SetPoint", Place)
    Place()
  end
end

-- Loot window and loot rolls -------------------------------------------------------

local function SkinLootButton(b)
  if not b or b.eveSkin then return end
  b.eveSkin = true
  for _, k in ipairs({ "NameFrame", "BorderFrame", "HighlightNameFrame", "PushedNameFrame", "IconQuestTexture" }) do zap(b[k]) end
  if b.Item and ns.SkinItem then ns.SkinItem(b.Item) end
  local text = b.Text or b.Name
  if text then ns.SetFont(text, 12, "", b) end
  local hl = b.HighlightNameFrame
  if hl then hl:SetAlpha(0) end
end

local function Loot()
  local f = LootFrame
  if f then
    local function Update()
      if f.ScrollBox and f.ScrollBox.ForEachFrame then f.ScrollBox:ForEachFrame(SkinLootButton) end
      for i = 1, 4 do SkinLootButton(_G["LootButton" .. i]) end
    end
    f:HookScript("OnShow", function() ns.Safe("loot", Update)(); C_Timer.After(0, ns.Safe("loot", Update)) end)
    if f.ScrollBox and f.ScrollBox.Update then hooksecurefunc(f.ScrollBox, "Update", ns.Safe("loot", Update)) end
  end
  local function SkinRoll(r)
    if not r or r.eveSkin then return end
    r.eveSkin = true
    StripTextures(r)
    zap(r.Border); zap(r.Background); zap(r.NameFrame); zap(r.Decoration); zap(r.Corner)
    Panel(r, { 0.02, 0.03, 0.04, 0.92 }, C.border)
    local icon = r.IconFrame and r.IconFrame.Icon
    if icon then
      icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      StripTextures(r.IconFrame, { [icon] = true })
      ns.Box(r.IconFrame, false, C.border, ns.Px(r))
    end
    local timer = r.Timer
    if timer then
      StripTextures(timer, { [timer:GetStatusBarTexture() or 0] = true })
      timer:SetStatusBarTexture(ns.WHITE)
      timer:SetStatusBarColor(unpack(C.accent))
    end
    if r.Name then ns.SetFont(r.Name, 12, "", r) end
    for _, k in ipairs({ "NeedButton", "GreedButton", "DisenchantButton", "PassButton", "TransmogButton" }) do
      if r[k] and ns.SteelArt then ns.SteelArt(r[k]) end
    end
  end
  for i = 1, 4 do
    local r = _G["GroupLootFrame" .. i]
    if r then r:HookScript("OnShow", function(self) ns.Safe("roll", SkinRoll)(self) end) end
  end
  if GroupLootContainer then
    hooksecurefunc(GroupLootContainer, "Show", function()
      for _, c in ipairs({ GroupLootContainer:GetChildren() }) do ns.Safe("roll", SkinRoll)(c) end
    end)
  end
end

-- Alerts (achievements, loot won, money, level up toasts) ---------------------------

local KEEP_LAYERS = { ARTWORK = true, OVERLAY = true }
local function SkinAlert(a)
  ns.alertCount = (ns.alertCount or 0) + 1
  ns.lastAlert = a
  ns.alertNames = ns.alertNames or {}
  table.insert(ns.alertNames, tostring(a and (a.GetDebugName and a:GetDebugName() or a.GetObjectType and a:GetObjectType()) or type(a)) .. ":" .. tostring(a and a.eveSkin))
  if not a or a.eveSkin or (a.IsForbidden and a:IsForbidden()) then return end
  a.eveSkin = true
  if ns.FilterArt then ns.FilterArt(a) end
  -- Icons stay (alert.Icon, Icon.Texture, lootItem.Icon); every other texture goes.
  local keep = {}
  for _, v in ipairs({ a.Icon, a.Icon and a.Icon.Texture, a.lootItem and a.lootItem.Icon, a.icon, a.ItemIcon }) do
    if type(v) == "table" and v.IsObjectType and v:IsObjectType("Texture") then keep[v] = true end
  end
  for _, r in ipairs({ a:GetRegions() }) do
    if r:IsObjectType("Texture") then
      local layer = r:GetDrawLayer()
      local w, h = r:GetSize()
      local square = w and h and w > 0 and math.abs(w - h) < 2 and w <= 64
      if keep[r] then
        r:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      elseif not (KEEP_LAYERS[layer] and square) then
        Blank(r)
      end
    elseif r:IsObjectType("FontString") then
      local _, size = r:GetFont()
      r:SetFont(ns.FONT, size or 12, "")
    end
  end
  for _, k in ipairs({ "glow", "shine", "Glow", "Shine", "Background", "IconBorder", "BGAtlas", "lootItem" }) do
    local v = a[k]
    if type(v) == "table" and v.IsObjectType and v:IsObjectType("Texture") then if not keep[v] then Blank(v) end
    elseif type(v) == "table" and v.SetAlpha and v ~= a.lootItem then v:SetAlpha(0) end
  end
  local p = Panel(a, { 0.02, 0.03, 0.04, 0.94 }, C.border)
  if p and not p.mark then
    p.mark = p:CreateTexture(nil, "ARTWORK")
    p.mark:SetColorTexture(unpack(C.accent))
    p.mark:SetPoint("TOPLEFT", ns.Px(a), -ns.Px(a))
    p.mark:SetPoint("BOTTOMLEFT", ns.Px(a), ns.Px(a))
    p.mark:SetWidth(2 * ns.Px(a))
  end
end

local function Alerts()
  if AlertFrame and AlertFrame.AddAlertFrame then
    hooksecurefunc(AlertFrame, "AddAlertFrame", function(_, frame) ns.Safe("alert", SkinAlert)(frame) end)
  end
  -- Talking head.
  local th = TalkingHeadFrame
  if th then
    local function Skin()
      if th.eveSkin then return end
      th.eveSkin = true
      for _, part in ipairs({ th.BackgroundFrame, th.PortraitFrame, th.MainFrame and th.MainFrame.Overlay }) do
        StripTextures(part)
      end
      Panel(th.BackgroundFrame or th, { 0.02, 0.03, 0.04, 0.9 }, C.border)
      local name = th.NameFrame and th.NameFrame.Name
      local text = th.TextFrame and th.TextFrame.Text
      if name then name:SetFont(ns.FONT, 18 * ns.Px(th), ""); name:SetTextColor(unpack(C.accent)) end
      if text then text:SetFont(ns.FONT, 14 * ns.Px(th), ""); text:SetTextColor(unpack(C.text)) end
    end
    th:HookScript("OnShow", ns.Safe("talking head", Skin))
  end
end

-- Durability figure: hidden; the Location panel shows durability (red when low). --

local function Durability()
  if DurabilityFrame then ns.Ghost(DurabilityFrame) end
end

-- Reputation: a thin line under the XP line, in the watched faction's colour. ---

local function Reputation()
  local xp = EveUIXP
  if not xp then return end
  local rep = CreateFrame("StatusBar", "EveUIRep", ns.root)
  rep:SetHeight(2)
  rep:SetPoint("TOPLEFT", xp, "BOTTOMLEFT", 0, -3)
  rep:SetPoint("TOPRIGHT", xp, "BOTTOMRIGHT", 0, -3)
  rep:SetStatusBarTexture(ns.WHITE)
  local bg = rep:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, 0.06)
  rep:EnableMouse(true)
  rep:SetHitRectInsets(0, 0, -6, -6)
  local data
  rep:SetScript("OnEnter", function(self)
    if not data then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(data.name, 1, 1, 1)
    GameTooltip:AddDoubleLine(data.standing or "", ("%d / %d"):format(data.cur, data.max), 0.6, 0.7, 0.75, 1, 1, 1)
    GameTooltip:Show()
  end)
  rep:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local function Update()
    local w = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    local name, reaction, minV, maxV, value
    if w then
      name, reaction, minV, maxV, value = w.name, w.reaction, w.currentReactionThreshold, w.nextReactionThreshold, w.currentStanding
    elseif GetWatchedFactionInfo then
      name, reaction, minV, maxV, value = GetWatchedFactionInfo()
    end
    if not name then data = nil; rep:Hide(); return end
    local cur, max = (value or 0) - (minV or 0), (maxV or 1) - (minV or 0)
    if max <= 0 then max, cur = 1, 1 end
    local col = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction or 4] or { r = 0.4, g = 0.7, b = 0.9 }
    rep:SetStatusBarColor(col.r, col.g, col.b)
    rep:SetMinMaxValues(0, max)
    rep:SetValue(cur)
    data = { name = name, cur = cur, max = max, standing = _G["FACTION_STANDING_LABEL" .. (reaction or 4)] }
    rep:Show()
  end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do ev:RegisterEvent(e) end
  ev:SetScript("OnEvent", ns.Safe("rep", Update))
  Update()
end

-- Minimap buttons: addon icons become a row of square buttons under the map panel.

local ROW = 26
local function MapButtons()
  local panel = EveUILocation
  if not panel then return end
  local row = CreateFrame("Frame", "EveUIMapButtons", ns.root)
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -6)
  row:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -6)
  local known = {}
  local function IsAddonButton(c)
    local n = c:GetName()
    if not n or c:IsForbidden() then return false end
    if n:find("^LibDBIcon10_") then return true end
    return c.dataObject ~= nil or (n:find("MinimapButton$") and not n:find("^ExpansionLandingPage") and c:IsObjectType("Button"))
  end
  local function Collect()
    if InCombatLockdown() then return end
    local list = {}
    for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
      if parent then
        for _, c in ipairs({ parent:GetChildren() }) do
          if IsAddonButton(c) and c:IsShown() then list[#list + 1] = c end
        end
      end
    end
    for _, c in ipairs(list) do
      if not known[c] then
        known[c] = true
        for _, r in ipairs({ c:GetRegions() }) do
          if r:IsObjectType("Texture") then
            local t = r:GetTexture()
            -- Drop the round border / background art; keep the icon.
            if r ~= c.icon and r ~= c.Icon and (r:GetDrawLayer() == "OVERLAY" or r:GetDrawLayer() == "BACKGROUND") then
              r:SetAlpha(0)
            end
          end
        end
        local icon = c.icon or c.Icon
        if icon then
          icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
          icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        ns.Box(c, { 0, 0, 0, 0.5 }, C.border, ns.Px(c))
        c.eveLock = true
        hooksecurefunc(c, "SetPoint", function(self)
          if not self.eveLock and not InCombatLockdown() then self.eveLock = true; Collect() end
        end)
        c:SetScript("OnDragStart", nil)
      end
    end
    for i, c in ipairs(list) do
      c.eveLock = true
      c:SetParent(row)
      c:SetSize(ROW * ns.Px(row) / ns.Px(c), ROW * ns.Px(row) / ns.Px(c))
      c:ClearAllPoints()
      c:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(i - 1) * (ROW + 4), 0)
      c.eveLock = nil
    end
    local shown = #list > 0
    row:SetShown(shown)
    local gap = shown and (ROW + 6) or 0
    if ns.mapButtonRow ~= gap then
      ns.mapButtonRow = gap
      if ns.PlaceTracker then ns.PlaceTracker() end
    end
  end
  Collect()
  ns.Every(3, "map buttons", Collect)
end

-- Boss frames: an EVE "hostiles" list of boss1-5 (secure, click to target). ------

local BOSS_ROWS, BOSS_H = 5, 34
local function Bosses()
  if Boss1TargetFrame or BossTargetFrameContainer then
    for i = 1, 5 do
      local b = _G["Boss" .. i .. "TargetFrame"]
      if b then
        ns.Kill(b)
      end
    end
    if BossTargetFrameContainer then ns.Ghost(BossTargetFrameContainer) end
  end
  local f = ns.CreatePanel("EveUIBoss", ns.root, "Hostiles", 260, ns.HEADER + BOSS_ROWS * BOSS_H + 8, "SecureHandlerStateTemplate")
  local VIS = "[@boss1,exists] show; hide"
  ns.Movable(f, "boss", "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 420, function(unlocked)
    if unlocked then UnregisterStateDriver(f, "visibility"); f:Show()
    else RegisterStateDriver(f, "visibility", VIS) end
  end)
  RegisterStateDriver(f, "visibility", VIS)
  f.rows = {}
  for i = 1, BOSS_ROWS do
    local unit = "boss" .. i
    local r = CreateFrame("Button", "EveUIBossRow" .. i, f, "SecureUnitButtonTemplate")
    r:SetSize(260 - 2, BOSS_H)
    r:SetPoint("TOPLEFT", 1, -(ns.HEADER + 4 + (i - 1) * BOSS_H))
    r:RegisterForClicks("AnyUp", "AnyDown")
    r:SetAttribute("unit", unit)
    r:SetAttribute("type1", "target")
    r:SetAttribute("type2", "togglemenu")
    RegisterUnitWatch(r)
    r.unit = unit
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints(); r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16)
    r.name = ns.Text(r, 12, C.title, "LEFT")
    r.name:SetPoint("TOPLEFT", 10, -4)
    r.name:SetWidth(180)
    r.pct = ns.Text(r, 12, C.text, "RIGHT")
    r.pct:SetPoint("TOPRIGHT", -10, -4)
    r.hp = CreateFrame("StatusBar", nil, r)
    r.hp:SetStatusBarTexture(ns.WHITE)
    r.hp:SetStatusBarColor(unpack(C.hostile))
    r.hp:SetPoint("BOTTOMLEFT", 10, 6)
    r.hp:SetPoint("BOTTOMRIGHT", -10, 6)
    r.hp:SetHeight(4)
    r.hp:SetMinMaxValues(0, 100)
    local bg = r.hp:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.08)
    f.rows[i] = r
  end
  local function Update()
    for _, r in ipairs(f.rows) do
      local u = r:GetAttribute("unit") or r.unit
      if UnitExists(u) then
        ns.SetUnitName(r.name, u)
        local c = ns.ReactionColor(u)
        r.hp:SetStatusBarColor(c[1], c[2], c[3])
        pcall(function() r.hp:SetValue(ns.HealthPct100(u)) end)
        if ns.SetHealthText then ns.SetHealthText(r.pct, u) end
        r.sel:SetShown(ns.Plain(UnitIsUnit(u, "target")) == true)
      end
    end
  end
  ns.Every(0.2, "boss", Update)
  ns.bossPanel = f
end

-- /eve preview <mirror|alert|boss|error|warning|zone> ------------------------------

function ns.Preview(what)
  what = what or ""
  if what == "plate" and ns.PreviewPlateCast then
    ns.PreviewPlateCast()
  elseif what == "mirror" then
    if MirrorTimerContainer and MirrorTimerContainer.SetupTimer then
      pcall(MirrorTimerContainer.SetupTimer, MirrorTimerContainer, "BREATH", 42000, 60000, 0, "Breath")
      pcall(MirrorTimerContainer.SetupTimer, MirrorTimerContainer, "EXHAUSTION", 20000, 60000, 0, "Fatigue")
      -- Freeze the preview bars (the game would reset them to the real, empty timers).
      MirrorTimerContainer:SetScript("OnUpdate", nil)
      for _, t in pairs(MirrorTimerContainer.activeTimers or {}) do
        t:SetScript("OnUpdate", nil)
        local function Freeze()
          if t.StatusBar then t.StatusBar:SetMinMaxValues(0, 1); t.StatusBar:SetValue(t.timer == "BREATH" and 0.7 or 0.33) end
        end
        Freeze(); C_Timer.After(0.2, Freeze); C_Timer.After(0.6, Freeze)
      end
    elseif MirrorTimer_Show then
      pcall(MirrorTimer_Show, "BREATH", 42000, 60000, -1, 0, "Breath")
    end
  elseif what == "alert" then
    for _, sys in ipairs({ { "MoneyWonAlertSystem", 123456 }, { "AchievementAlertSystem", 6 },
      { "NewRecipeLearnedAlertSystem", 2550 }, { "HonorAwardedAlertSystem", 100 } }) do
      local o = _G[sys[1]]
      if o and o.AddAlert then
        local ok, err = pcall(o.AddAlert, o, sys[2])
        ns.Print(sys[1] .. ": " .. (ok and "ok" or tostring(err)))
      else
        ns.Print(sys[1] .. ": missing")
      end
    end
  elseif what == "boss" then
    if InCombatLockdown() then return end
    local f = ns.bossPanel
    UnregisterStateDriver(f, "visibility")
    f:Show()
    for i, r in ipairs(f.rows) do
      UnregisterUnitWatch(r)
      r:SetAttribute("unit", i == 1 and "target" or "player")
      r:SetShown(i <= 3)
    end
  elseif what == "error" then
    UIErrorsFrame:AddMessage("Target is out of range.", 1, 0.2, 0.2)
  elseif what == "warning" then
    if RaidNotice_AddMessage then RaidNotice_AddMessage(RaidWarningFrame, "WARP SCRAMBLER ACTIVE", ChatTypeInfo["RAID_WARNING"]) end
  elseif what == "zone" then
    if ZoneTextFrame then
      ZoneTextString:SetText("TELDRASSIL"); SubZoneTextString:SetText("SHADOWGLEN")
      ZoneTextFrame:Show(); SubZoneTextFrame:Show()
      if FadingFrame_Show then pcall(FadingFrame_Show, ZoneTextFrame); pcall(FadingFrame_Show, SubZoneTextFrame) end
    end
  else
    ns.Print("preview: mirror | alert | boss | error | warning | zone")
  end
end

ns.RegisterModule(function()
  ns.Safe("mirror", MirrorTimers)()
  ns.Safe("extra", ExtraButtons)()
  ns.Safe("vehicle", Vehicle)()
  ns.Safe("loot", Loot)()
  ns.Safe("alerts", Alerts)()
  ns.Safe("durability", Durability)()
  ns.Safe("rep", Reputation)()
  ns.Safe("map buttons", MapButtons)()
  ns.Safe("bosses", Bosses)()
  if UpdateUIPanelPositions then hooksecurefunc("UpdateUIPanelPositions", ns.Safe("panels", ShiftPanels)) end
  if ShowUIPanel then hooksecurefunc("ShowUIPanel", ns.Safe("panels", ShiftPanels)) end
  if LootFrame then LootFrame:HookScript("OnShow", function() C_Timer.After(0, ns.Safe("panels", ShiftPanels)) end) end
  ns.Safe("tooltip anchor", TooltipAnchor)()
  ns.Safe("messages", Messages)()
end)

-- Settings window (/eveui) ----------------------------------------------------------
-- Layout lock and reset, UI scale and panel opacity, and module switches.
-- Module switches take effect on the next reload.

local function SButton(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 24)
  ns.Box(b, { 0.06, 0.08, 0.10, 0.95 }, C.border)
  b.text = ns.Text(b, 11, C.title)
  b.text:SetPoint("CENTER")
  function b:SetLabel(t) self.text:SetText(t:upper()) end
  b:SetLabel(text)
  b:SetScript("OnEnter", function(self) ns.SetBoxBorder(self, C.accent) end)
  b:SetScript("OnLeave", function(self) ns.SetBoxBorder(self, C.border) end)
  b:SetScript("OnClick", onClick)
  return b
end

local function SHeader(parent, text, y)
  local t = ns.Text(parent, 10, C.dim, "LEFT")
  t:SetPoint("TOPLEFT", 14, -y)
  t:SetText(text:upper())
  local l = parent:CreateTexture(nil, "ARTWORK")
  l:SetColorTexture(unpack(C.line))
  l:SetHeight(1)
  l:SetPoint("LEFT", t, "RIGHT", 8, 0)
  l:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
  return t
end

local function SToggle(parent, label, y, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(150, 20)
  b:SetPoint("TOPLEFT", 14, -y)
  local box = CreateFrame("Frame", nil, b)
  box:SetSize(12, 12)
  box:SetPoint("LEFT", 0, 0)
  ns.Box(box, { 0, 0, 0, 0.6 }, C.border)
  local fill = box:CreateTexture(nil, "ARTWORK")
  fill:SetColorTexture(unpack(C.accent))
  fill:SetPoint("TOPLEFT", 3, -3)
  fill:SetPoint("BOTTOMRIGHT", -3, 3)
  local t = ns.Text(b, 12, C.text, "LEFT")
  t:SetPoint("LEFT", box, "RIGHT", 8, 0)
  t:SetText(label)
  local function Paint() fill:SetShown(get() and true or false) end
  b:SetScript("OnClick", function() set(not get()); Paint() end)
  b:SetScript("OnEnter", function() ns.SetBoxBorder(box, C.accent); t:SetTextColor(unpack(C.title)) end)
  b:SetScript("OnLeave", function() ns.SetBoxBorder(box, C.border); t:SetTextColor(unpack(C.text)) end)
  b.Paint = Paint
  Paint()
  return b
end

-- live: apply while dragging; otherwise on release.
local function SSlider(parent, label, y, lo, hi, step, fmt, get, set, live)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetPoint("TOPLEFT", 14, -y)
  holder:SetPoint("TOPRIGHT", -14, -y)
  holder:SetHeight(34)
  local t = ns.Text(holder, 12, C.text, "LEFT")
  t:SetPoint("TOPLEFT", 0, 0)
  t:SetText(label)
  local v = ns.Text(holder, 12, C.accent, "RIGHT")
  v:SetPoint("TOPRIGHT", 0, 0)
  local s = CreateFrame("Slider", nil, holder)
  s:SetOrientation("HORIZONTAL")
  s:EnableMouse(true)
  s:SetPoint("BOTTOMLEFT", 0, 2)
  s:SetPoint("BOTTOMRIGHT", 0, 2)
  s:SetHeight(14)
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(1, 1, 1, 0.12)
  track:SetHeight(2)
  track:SetPoint("LEFT"); track:SetPoint("RIGHT")
  local fillT = s:CreateTexture(nil, "BORDER")
  fillT:SetColorTexture(unpack(C.accent))
  fillT:SetHeight(2)
  fillT:SetPoint("LEFT")
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(unpack(C.title))
  thumb:SetSize(6, 14)
  s:SetThumbTexture(thumb)
  local function Show(val)
    v:SetText(fmt(val))
    local w = s:GetWidth()
    fillT:SetWidth(math.max((val - lo) / (hi - lo) * w, 1))
  end
  s:SetScript("OnValueChanged", function(_, val)
    Show(val)
    if live then set(val) end
  end)
  s:SetScript("OnMouseUp", function(self) if not live then set(self:GetValue()) end end)
  s:SetScript("OnSizeChanged", function(self) Show(self:GetValue()) end)
  holder.Refresh = function() s:SetValue(get()); Show(get()) end
  holder.Refresh()
  return holder
end

local settings
local function BuildSettings()
  local W = 360
  local f = ns.CreatePanel("EveUISettings", ns.root, "EveUI", W, 100)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "EveUISettings")

  local sub = ns.Text(f, 11, C.dim, "LEFT")
  sub:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
  sub:SetText("SETTINGS")

  local close = CreateFrame("Button", nil, f)
  close:SetSize(ns.HEADER - 4, ns.HEADER - 4)
  close:SetPoint("TOPRIGHT", -2, -2)
  local x = ns.Text(close, 14, C.dim)
  x:SetPoint("CENTER", 0, 1)
  x:SetText("×")
  close:SetScript("OnEnter", function() x:SetTextColor(unpack(C.hostile)) end)
  close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.dim)) end)
  close:SetScript("OnClick", function() f:Hide() end)

  local y = ns.HEADER + 14
  SHeader(f, "Layout", y)
  y = y + 18
  local unlock = SButton(f, "Unlock layout", (W - 38) / 2, function()
    ns.SetLocked(ns.unlocked)
  end)
  unlock:SetPoint("TOPLEFT", 14, -y)
  local reset = SButton(f, "Reset layout", (W - 38) / 2, function() ns.ResetLayout() end)
  reset:SetPoint("TOPRIGHT", -14, -y)
  y = y + 32
  local hint = ns.Text(f, 11, C.dim, "LEFT")
  hint:SetWordWrap(true)
  hint:SetPoint("TOPLEFT", 14, -y)
  hint:SetWidth(W - 28)
  hint:SetText("Drag any outlined element. Chat: drag to move, corner grip to resize. "
    .. "The Neocom snaps to the nearest screen edge. Saved for this character; "
    .. "locks itself when combat starts.")
  y = y + 46

  SHeader(f, "Display", y)
  y = y + 18
  local scale = SSlider(f, "UI scale", y, 0.5, 2, 0.05, function(v) return ("%d%%"):format(v * 100 + 0.5) end,
    function() return EveUIDB.scale or 1 end,
    function(v)
      EveUIDB.scale = math.floor(v * 20 + 0.5) / 20
      ns.UpdateScale()
      if InCombatLockdown() then ns.Print("scale applies after combat.") end
    end)
  y = y + 42
  local opacity = SSlider(f, "Panel opacity", y, 0.2, 1, 0.05, function(v) return ("%d%%"):format(v * 100 + 0.5) end,
    function() return EveUIDB.opacity or 1 end,
    function(v) EveUIDB.opacity = math.floor(v * 20 + 0.5) / 20; ns.ApplyOpacity() end, true)
  y = y + 48

  -- Faction theme: cycles through ns.THEMES; applies after a reload.
  if ns.THEMES then
    local tl = ns.Text(f, 11, C.text, "LEFT")
    tl:SetPoint("TOPLEFT", 14, -(y + 6))
    tl:SetText("Faction theme")
    local pick = EveUIDB.theme or "caldari"
    local function Label()
      for _, t in ipairs(ns.THEMES) do if t.key == pick then return t.label end end
      return "Caldari"
    end
    local tb
    tb = SButton(f, Label(), 150, function()
      local idx = 1
      for i, t in ipairs(ns.THEMES) do if t.key == pick then idx = i end end
      pick = ns.THEMES[idx % #ns.THEMES + 1].key
      EveUIDB.theme = pick ~= "caldari" and pick or nil
      tb:SetLabel(Label() .. ((pick ~= (ns.appliedTheme or "caldari")) and "  (reload)" or ""))
    end)
    tb:SetPoint("TOPRIGHT", -14, -y)
    y = y + 34
  end

  SHeader(f, "Modules", y)
  y = y + 18
  local reload
  local function Changed() if reload then reload:Show() end end
  local function Off(key)
    return function() return not EveUIDB.off[key] end, function(on)
      EveUIDB.off[key] = (not on) or nil; Changed()
    end
  end
  local toggles = {
    { "Neocom", function() return EveUIDB.neocom end, function(on) EveUIDB.neocom = on; Changed() end },
    { "Overview", Off("overview") },
    { "EVE ring frames", function() return EveUIDB.frameStyle == "eve" end,
      function(on) EveUIDB.frameStyle = on and "eve" or nil; Changed() end },
    { "Unit frames", function() return not (EveUIDB.off.locks or EveUIDB.off.unitframes) end,
      function(on) EveUIDB.off.locks = (not on) or nil; EveUIDB.off.unitframes = (not on) or nil; Changed() end },
    { "Fleet", Off("fleet") },
    { "Damage meter", Off("meter") },
    { "Killmails", Off("killmail") },
    { "Nameplate brackets", Off("brackets") },
    { "D-Scan radar", Off("dscan") },
    { "Star map", Off("starmap") },
    { "Fitting", Off("fitting") },
    { "Skill queue", Off("skillqueue") },
    { "Wallet", Off("wallet") },
    { "Missions", Off("missions") },
    { "Fleet broadcasts", Off("broadcasts") },
    { "Ship voice alerts", Off("voice") },
    { "Fleet comms", Off("comms") },
    { "Combat text", Off("sct") },
    { "Hide Blizzard unit frames", function() return EveUIDB.hideBlizzard end,
      function(on) EveUIDB.hideBlizzard = on; Changed() end },
  }
  local rows = {}
  for i, t in ipairs(toggles) do
    local get, set = t[2], t[3]
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local b = SToggle(f, t[1], y + row * 22, get, set)
    if col == 1 then b:ClearAllPoints(); b:SetPoint("TOPLEFT", 14 + (W - 28) / 2, -(y + row * 22)) end
    rows[#rows + 1] = b
  end
  y = y + math.ceil(#toggles / 2) * 22 + 6
  local note = ns.Text(f, 11, C.dim, "LEFT")
  note:SetPoint("TOPLEFT", 14, -y - 6)
  note:SetText("Module changes apply after a reload.")
  reload = SButton(f, "Reload UI", 100, function() ReloadUI() end)
  reload:SetPoint("TOPRIGHT", -14, -y)
  reload:Hide()
  y = y + 34

  local foot = ns.Text(f, 10, C.dim, "LEFT")
  foot:SetPoint("BOTTOMLEFT", 14, 10)
  foot:SetText(ns.fontLoaded and "FONT  BARLOW SEMI CONDENSED" or
    "FONT  ARIAL NARROW (BARLOW LOADS AFTER A CLIENT RESTART)")
  local cmd = ns.Text(f, 10, C.dim, "RIGHT")
  cmd:SetPoint("BOTTOMRIGHT", -14, 10)
  cmd:SetText("/EVEUI  /EVE")
  f:SetHeight(y + 30)

  local function Refresh()
    unlock:SetLabel(ns.unlocked and "Lock layout" or "Unlock layout")
    if ns.unlocked then ns.SetBoxBorder(unlock, C.accent); unlock.text:SetTextColor(unpack(C.accent))
    else ns.SetBoxBorder(unlock, C.border); unlock.text:SetTextColor(unpack(C.title)) end
  end
  unlock:SetScript("OnLeave", function() Refresh() end)
  ns.OnLockChanged = Refresh
  f:SetScript("OnShow", function()
    Refresh(); scale.Refresh(); opacity.Refresh()
    for _, b in ipairs(rows) do b.Paint() end
  end)
  Refresh()
  f:Hide()
  return f
end

function ns.ToggleSettings()
  if not settings then settings = BuildSettings() end
  settings:SetShown(not settings:IsShown())
end
