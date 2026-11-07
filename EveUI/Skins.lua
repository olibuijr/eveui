-- Restyles the rest of Blizzard's UI in EVE fashion: tooltips, chat windows,
-- player buffs and debuffs, the objective tracker, the game menu, popups and
-- the main windows (character, spellbook, bags, social, map, ...).
local ADDON, ns = ...
local C = ns.C

local function zap(r) if r then r:SetAlpha(0) end end

-- Generic pieces ---------------------------------------------------------------

local function SkinBox(f, bg, border)
  if not f or (f.IsForbidden and f:IsForbidden()) then return end
  ns.Box(f, bg or C.panel, border or C.border, ns.Px(f))
end

local function SkinButton(b)
  if not b or b.eveSkin or not b.IsObjectType or not b:IsObjectType("Button") then return end
  b.eveSkin = true
  zap(b.Left); zap(b.Middle); zap(b.Right); zap(b.Center)
  zap(b:GetNormalTexture()); zap(b:GetPushedTexture()); zap(b:GetDisabledTexture())
  local px = ns.Px(b)
  ns.Box(b, C.header, C.border, px)
  local hl = b:GetHighlightTexture()
  if hl then hl:SetTexture(ns.WHITE); hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.15); hl:SetAllPoints() end
  local fs = b:GetFontString()
  if fs then fs:SetTextColor(unpack(C.title)) end
end
ns.SkinButton = SkinButton

-- Window frames built on Blizzard's portrait / button-frame templates.
local function SkinWindow(f)
  if not f or f.eveSkin or (f.IsForbidden and f:IsForbidden()) then return end
  f.eveSkin = true
  zap(f.NineSlice); zap(f.Bg); zap(f.Background); zap(f.TopTileStreaks); zap(f.Border)
  if f.PortraitContainer then f.PortraitContainer:SetAlpha(0) end
  zap(f.portrait)
  if f.Inset then zap(f.Inset.NineSlice); zap(f.Inset.Bg); SkinBox(f.Inset, { 0, 0, 0, 0.25 }, C.line) end
  if f.BorderFrame then zap(f.BorderFrame.NineSlice); zap(f.BorderFrame.Bg); zap(f.BorderFrame.TopTileStreaks); zap(f.BorderFrame.PortraitContainer) end
  SkinBox(f, C.panel, C.border)
  -- Title bar strip with accent mark.
  local px = ns.Px(f)
  local hb = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  hb:SetColorTexture(unpack(C.header))
  hb:SetPoint("TOPLEFT", px, -px)
  hb:SetPoint("TOPRIGHT", -px, -px)
  hb:SetHeight(22 * px)
  local mark = f:CreateTexture(nil, "ARTWORK")
  mark:SetColorTexture(unpack(C.accent))
  mark:SetPoint("TOPLEFT", px, -px)
  mark:SetSize(2 * px, 22 * px)
  local title = f.TitleContainer and f.TitleContainer.TitleText or f.TitleText
  if title then title:SetTextColor(unpack(C.title)) end
end
ns.SkinWindow = SkinWindow

-- Tooltips ---------------------------------------------------------------------

local function SkinTooltip(tt)
  if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
  zap(tt.NineSlice)
  if not tt.eveSkin then
    tt.eveSkin = true
    SkinBox(tt, { 0.02, 0.03, 0.04, 0.94 }, C.border)
    local sb = tt.StatusBar or _G[(tt:GetName() or "") .. "StatusBar"]
    if sb then
      sb:SetStatusBarTexture(ns.WHITE)
      local px = ns.Px(sb)
      sb:SetHeight(4 * px)
      sb:ClearAllPoints()
      sb:SetPoint("BOTTOMLEFT", tt, "BOTTOMLEFT", 2 * px, 2 * px)
      sb:SetPoint("BOTTOMRIGHT", tt, "BOTTOMRIGHT", -2 * px, 2 * px)
    end
  end
end

local function Tooltips()
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2,
    ItemRefShoppingTooltip1, ItemRefShoppingTooltip2, EmbeddedItemTooltip, GameSmallHeaderTooltip,
    QuickKeybindTooltip, FriendsTooltip, SettingsTooltip, LibDBIconTooltip }) do
    SkinTooltip(tt)
  end
  if SharedTooltip_SetBackdropStyle then
    hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt) if tt then zap(tt.NineSlice) end end)
  end
  if GameTooltip_SetBackdropStyle then
    hooksecurefunc("GameTooltip_SetBackdropStyle", function(tt) if tt then zap(tt.NineSlice) end end)
  end
  GameTooltip:HookScript("OnShow", function(self) zap(self.NineSlice) end)
  if GameTooltipStatusBar then GameTooltipStatusBar:SetStatusBarTexture(ns.WHITE) end
end

-- Chat ---------------------------------------------------------------------------

local function SkinTab(tab)
  if not tab or tab.eveSkin then return end
  tab.eveSkin = true
  for _, k in ipairs({ "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight" }) do zap(tab[k]) end
  local fs = tab.Text or tab:GetFontString()
  if fs then ns.SetFont(fs, 11, "", tab) end
  -- Labels in capitals, like EVE's channel tabs.
  local busy
  hooksecurefunc(tab, "SetText", function(self, t)
    if busy or type(t) ~= "string" or ns.issecret(t) then return end
    busy = true; self:SetText(t:upper()); busy = false
  end)
  local cur = tab:GetText()
  if type(cur) == "string" and not ns.issecret(cur) then tab:SetText(cur) end
  if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, tab.sizePadding or 0) end
  -- Selected tab: a short accent line under the label.
  local px = ns.Px(tab)
  local line = tab:CreateTexture(nil, "OVERLAY")
  line:SetColorTexture(unpack(C.accent))
  line:SetHeight(2 * px)
  if fs then
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3 * px)
    line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -3 * px)
  else
    line:SetPoint("BOTTOMLEFT", 6 * px, 2 * px); line:SetPoint("BOTTOMRIGHT", -6 * px, 2 * px)
  end
  line:Hide()
  tab.eveLine = line
end

local function SkinChat(i)
  local cf = _G["ChatFrame" .. i]
  if not cf or cf.eveSkin then return end
  cf.eveSkin = true
  local name = cf:GetName()
  for _, r in ipairs({ cf:GetRegions() }) do
    if r:IsObjectType("Texture") then r:SetTexture(nil); r:SetAlpha(0) end
  end
  if cf.Background then zap(cf.Background) end
  local px = ns.Px(cf)
  local back = CreateFrame("Frame", nil, cf)
  back:SetPoint("TOPLEFT", -8 * px, 30 * px)
  back:SetPoint("BOTTOMRIGHT", 8 * px, -6 * px)
  back:SetFrameLevel(math.max(cf:GetFrameLevel() - 1, 0))
  ns.Box(back, C.bg, C.border, px)
  local line = back:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(unpack(C.line))
  line:SetPoint("TOPLEFT", px, -24 * px)
  line:SetPoint("TOPRIGHT", -px, -24 * px)
  line:SetHeight(px)
  cf.eveBack = back

  ns.Hide(_G[name .. "ButtonFrame"])
  if cf.ScrollBar then cf.ScrollBar:SetAlpha(0.35) end
  if cf.ScrollToBottomButton then cf.ScrollToBottomButton:SetAlpha(0.6) end
  SkinTab(_G[name .. "Tab"])

  local eb = _G[name .. "EditBox"]
  if eb then
    for _, k in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
      zap(_G[name .. "EditBox" .. k]); zap(eb[k])
    end
    local epx = ns.Px(eb)
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -8 * px, -10 * px)
    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 8 * px, -10 * px)
    eb:SetHeight(26 * epx)
    ns.Box(eb, C.panel, C.border, epx)
    -- Focus: accent border and a cyan mark on the left edge.
    local mark = eb:CreateTexture(nil, "OVERLAY")
    mark:SetColorTexture(unpack(C.accent))
    mark:SetPoint("TOPLEFT", epx, -epx)
    mark:SetPoint("BOTTOMLEFT", epx, epx)
    mark:SetWidth(2 * epx)
    mark:Hide()
    eb:HookScript("OnEditFocusGained", function(self) ns.SetBoxBorder(self, C.accent); mark:Show() end)
    eb:HookScript("OnEditFocusLost", function(self) ns.SetBoxBorder(self, C.border); mark:Hide() end)
    local header = _G[name .. "EditBoxHeader"] or eb.header
    if header and header.GetFont then
      local _, size = header:GetFont()
      header:SetFont(ns.FONT, size or 14, "")
    end
  end
end

local function Chat()
  for i = 1, NUM_CHAT_WINDOWS or 10 do SkinChat(i) end
  ns.Hide(QuickJoinToastButton)
  ns.Hide(ChatFrameMenuButton)
  ns.Hide(ChatFrameChannelButton)
  ns.Hide(ChatFrameToggleVoiceDeafenButton)
  ns.Hide(ChatFrameToggleVoiceMuteButton)
  ns.Hide(TextToSpeechButtonFrame)
  if FCF_OpenTemporaryWindow then
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
      for i = 1, NUM_CHAT_WINDOWS or 10 do SkinChat(i) end
    end)
  end
  -- Keep tab labels readable when the mouse is away from chat.
  CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 1
  CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0.6
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local cf, tab = _G["ChatFrame" .. i], _G["ChatFrame" .. i .. "Tab"]
    if cf and FCFTab_UpdateAlpha then pcall(FCFTab_UpdateAlpha, cf) end
    if tab and tab:IsShown() then tab:SetAlpha(i == 1 and 1 or 0.6) end
  end
  if FCFTab_UpdateColors then
    hooksecurefunc("FCFTab_UpdateColors", function(tab, selected)
      local fs = tab and (tab.Text or tab:GetFontString())
      if fs then
        if selected then fs:SetTextColor(unpack(C.accent)) else fs:SetTextColor(unpack(C.dim)) end
      end
      if tab and tab.eveLine then tab.eveLine:SetShown(selected and true or false) end
    end)
  end
  -- Position and size: per character in the layout, applied with the plain
  -- C calls (ChatFrame1 is an Edit Mode frame; its Lua SetPoint override
  -- would taint Edit Mode). Moved and resized only while unlocked.
  local cf = ChatFrame1
  if not cf then return end
  function ns.PlaceChatDefault()
    local px = ns.Px(cf)
    local left = (EveUIDB.neocom and ns.NeocomSide() == "left") and 64 or 20
    ns.Move(cf, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * px, 58 * px)
    cf:SetSize(540 * px, 250 * px)
    if FCF_SavePositionAndDimensions then pcall(FCF_SavePositionAndDimensions, cf) end
  end
  local function SaveChat()
    local p, _, rp, x, y = cf:GetPoint()
    if not p then return end
    ns.Layout().chat = { p, rp or p, x, y, cf:GetWidth(), cf:GetHeight() }
    if FCF_SavePositionAndDimensions then pcall(FCF_SavePositionAndDimensions, cf) end
  end
  local function ApplyChat()
    local c = ns.Layout().chat
    if not c or InCombatLockdown() then return end
    ns.Move(cf, c[1], UIParent, c[2], c[3], c[4])
    cf:SetSize(c[5], c[6])
  end
  if not EveUIDB.chatPlaced then
    EveUIDB.chatPlaced = true
    ns.PlaceChatDefault()
  end
  ns.Mover(cf, { key = "chat", label = "Chat", apply = ApplyChat, save = SaveChat, resize = true,
    overlay = cf.eveBack })
  ns.OnLayout(ApplyChat)
end

-- Buffs --------------------------------------------------------------------------

local function SkinAura(a, debuff)
  if not a or a.eveSkin or not a.Icon then return end
  a.eveSkin = true
  local px = ns.Px(a)
  local icon = a.Icon
  if icon.Icon then icon = icon.Icon end
  if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  zap(a.DebuffBorder); zap(a.TempEnchantBorder); zap(a.Symbol)
  local frame = CreateFrame("Frame", nil, a)
  a.eveBorder, a.eveIcon = frame, icon
  frame:SetPoint("TOPLEFT", icon, "TOPLEFT", -px, px)
  frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", px, -px)
  ns.Box(frame, false, debuff and C.hostile or C.border, px)
  local dur = a.Duration
  if dur and not dur.SetFont and dur.Text then dur = dur.Text end
  if dur and dur.SetFont then
    ns.SetFont(dur, 11, "", a)
    dur:SetTextColor(unpack(C.dim))
    -- Blizzard swaps the font object as time runs out; keep the EVE colour.
    hooksecurefunc(dur, "SetFontObject", function(self)
      ns.SetFont(self, 11, "", a)
      self:SetTextColor(unpack(C.dim))
    end)
  end
  if a.Count then ns.SetFont(a.Count, 12, "OUTLINE", a) end
end

local function SkinAuras()
  for _, holder in ipairs({ BuffFrame, DebuffFrame }) do
    if holder then
      for _, a in ipairs(holder.auraFrames or {}) do
        SkinAura(a, holder == DebuffFrame)
        if a.eveBorder then
          local tex = a.eveIcon.GetTexture and a.eveIcon:GetTexture()
          a.eveBorder:SetShown(not ns.issecret(tex) and tex ~= nil or ns.issecret(tex))
        end
      end
    end
  end
end

local function Auras()
  for _, holder in ipairs({ BuffFrame, DebuffFrame }) do
    if holder then
      for _, m in ipairs({ "UpdateAuraButtons", "Update" }) do
        if holder[m] then hooksecurefunc(holder, m, function() ns.Safe("auras", SkinAuras)() end) end
      end
    end
  end
  if BuffFrame and BuffFrame.CollapseAndExpandButton then ns.SteelArt(BuffFrame.CollapseAndExpandButton) end
  SkinAuras()
end

-- Objective tracker --------------------------------------------------------------

local TRACKERS = { "ScenarioObjectiveTracker", "UIWidgetObjectiveTracker", "CampaignQuestObjectiveTracker",
  "QuestObjectiveTracker", "AdventureObjectiveTracker", "AchievementObjectiveTracker",
  "MonthlyActivitiesObjectiveTracker", "ProfessionsRecipeTracker", "BonusObjectiveTracker",
  "WorldQuestObjectiveTracker", "InitiativeTasksObjectiveTracker" }

local function SkinHeader(h, top)
  if not h or h.eveSkin then return end
  h.eveSkin = true
  zap(h.Background)
  -- Header art is re-applied (and faded in) by Blizzard; keep it empty.
  for _, r in ipairs({ h:GetRegions() }) do
    if r:IsObjectType("Texture") then
      r:SetTexture(nil)
      local busy
      hooksecurefunc(r, "SetAtlas", function(self)
        if busy then return end
        busy = true; self:SetTexture(nil); busy = false
      end)
    end
  end
  if h.MinimizeButton then ns.FlatToggle(h.MinimizeButton) end
  local px = ns.Px(h)
  ns.Box(h, top and C.header or { 0.05, 0.07, 0.08, 0.8 }, false, px)
  local mark = h:CreateTexture(nil, "ARTWORK")
  mark:SetColorTexture(unpack(C.accent))
  mark:SetPoint("TOPLEFT", 0, 0)
  mark:SetPoint("BOTTOMLEFT", 0, 0)
  mark:SetWidth(2 * px)
  local line = h:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(unpack(C.line))
  line:SetPoint("BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(px)
  if h.Text then
    local function Style()
      ns.SetFont(h.Text, top and 13 or 12, "", h)
      h.Text:SetTextColor(unpack(C.title))
    end
    Style()
    if h.SetText then hooksecurefunc(h, "SetText", Style) end
    hooksecurefunc(h.Text, "SetFontObject", Style)
    h:HookScript("OnShow", Style)
  end
end

-- Collapse/expand buttons: Blizzard's rounded art is hidden and a flat
-- "–"/"+" glyph follows the button's current atlas.
function ns.FlatToggle(b)
  if not b or b.eveFlat then return end
  b.eveFlat = true
  local t = ns.Text(b, 15, C.dim)
  t:SetPoint("CENTER", 0, 1)
  local function Sync()
    local n = b.GetNormalTexture and b:GetNormalTexture()
    local a = n and n.GetAtlas and n:GetAtlas()
    a = type(a) == "string" and a:lower() or ""
    t:SetText((a:find("expand") or a:find("plus")) and "+" or "–")
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
      local tex = b[get] and b[get](b)
      if tex then tex:SetAlpha(0) end
    end
  end
  for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
    local tex = b[get] and b[get](b)
    if tex then hooksecurefunc(tex, "SetAtlas", Sync) end
  end
  for _, m in ipairs({ "SetNormalAtlas", "SetNormalTexture", "SetPushedAtlas" }) do
    if b[m] then hooksecurefunc(b, m, Sync) end
  end
  b:HookScript("OnEnter", function() t:SetTextColor(unpack(C.accent)) end)
  b:HookScript("OnLeave", function() t:SetTextColor(unpack(C.dim)) end)
  b:HookScript("OnClick", function() C_Timer.After(0, Sync) end)
  b.eveSync = Sync
  Sync()
end

-- Tracker contents ------------------------------------------------------------------
-- Blocks are pooled and rebuilt as quests change, so the tracker tree is
-- walked after every module update and once a second while shown. Each
-- texture is judged again whenever Blizzard gives it a new atlas.

local function Low(v) return type(v) == "string" and v:lower() or nil end

-- Quest titles: gold becomes EVE white, the gold hover becomes cyan.
local function TrackerText(fs)
  if fs.eveTT then return end
  fs.eveTT = true
  local busy
  local function Fix(self, r, g, b)
    if busy then return end
    if r == nil or type(r) == "table" then r, g, b = self:GetTextColor() end
    if r == nil or ns.issecret(r) then return end
    if r > 0.6 and g > 0.45 and b < 0.3 and r >= g then
      busy = true
      if r >= 0.95 then self:SetTextColor(unpack(C.accent)) else self:SetTextColor(unpack(C.title)) end
      busy = false
    end
  end
  hooksecurefunc(fs, "SetTextColor", Fix)
  Fix(fs)
end

-- Atlas / file words that mark decorative art in the tracker.
local TRACK_HIDE = { "background", "bg$", "%-bg%-", "frame", "border", "glow", "sheen", "starburst", "shine",
  "toast", "header", "titlebar", "bonusobjectives", "scenario", "objfx", "fill%-bg", "barbg", "barframe",
  "parchment", "stone", "spark$" }
local TRACK_KEEP = { "check", "icon", "poi", "quest%-.*mark", "arrow", "dash" }

local function Steelify(tex)
  tex:SetDesaturated(true)
  tex:SetVertexColor(0.62, 0.78, 0.9)
end

local function JudgeTexture(tex, inPOI)
  if tex.eveOwn then return end
  local name = Low(tex.GetAtlas and tex:GetAtlas()) or Low(tex.GetTexture and tex:GetTexture())
  if not name then return end
  if inPOI or name:find("poi") then
    Steelify(tex)
    return
  end
  for _, k in ipairs(TRACK_KEEP) do
    if name:find(k) then
      if name:find("check") then tex:SetDesaturated(true); tex:SetVertexColor(unpack(C.accent)) end
      return
    end
  end
  for _, k in ipairs(TRACK_HIDE) do
    if name:find(k) then tex:SetAlpha(0); tex.eveHid = true; return end
  end
  if tex.eveHid then tex:SetAlpha(1); tex.eveHid = nil end
end

local function WatchTexture(tex, inPOI)
  if tex.eveWatch then return end
  tex.eveWatch = true
  local busy
  local function Again()
    if busy then return end
    busy = true; ns.Safe("tracker art", JudgeTexture)(tex, inPOI); busy = false
  end
  hooksecurefunc(tex, "SetAtlas", Again)
  hooksecurefunc(tex, "SetTexture", Again)
  if inPOI then hooksecurefunc(tex, "SetDesaturated", function(_, d) if not d then Again() end end) end
  JudgeTexture(tex, inPOI)
end

-- Progress and timer bars: flat fill, black hairline box, no Blizzard frame.
local function TrackerBar(bar)
  if bar.eveSkin then return end
  bar.eveSkin = true
  local fill = bar:GetStatusBarTexture()
  bar:SetStatusBarTexture(ns.WHITE)
  fill = bar:GetStatusBarTexture()
  if fill then fill.eveOwn = true end
  local r, g, b = bar:GetStatusBarColor()
  if r and not ns.issecret(r) and ((r > 0.6 and g > 0.4 and b < 0.3) or (r > 0.95 and g > 0.95 and b > 0.95)) then
    bar:SetStatusBarColor(unpack(C.accent))
  end
  hooksecurefunc(bar, "SetStatusBarTexture", function(self, t)
    if t ~= ns.WHITE then self:SetStatusBarTexture(ns.WHITE) end
  end)
  local px = ns.Px(bar)
  local holder = CreateFrame("Frame", nil, bar)
  holder:SetPoint("TOPLEFT", -px, px)
  holder:SetPoint("BOTTOMRIGHT", px, -px)
  holder:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
  ns.Box(holder, { 0, 0, 0, 0.55 }, C.line, px)
  holder.eveBox.bg.eveOwn = true
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do holder.eveBox[side].eveOwn = true end
  if bar.Label then bar.Label:SetShadowOffset(px, -px) end
end

-- Quest item buttons: icon with a 1 px steel frame instead of the slot art.
local function TrackerItem(b)
  if b.eveSkin then return end
  if InCombatLockdown() and b.IsProtected and b:IsProtected() then return end
  b.eveSkin = true
  local icon = b.icon or b.Icon
  if icon and icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); icon.eveOwn = true end
  local n = b.GetNormalTexture and b:GetNormalTexture()
  if n then n:SetAlpha(0); n.eveOwn = true end
  local px = ns.Px(b)
  ns.Box(b, false, C.border, px)
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do b.eveBox[side].eveOwn = true end
  local p = b.GetPushedTexture and b:GetPushedTexture()
  if p then p:SetColorTexture(1, 1, 1, 0.15); p.eveOwn = true end
  local h = b.GetHighlightTexture and b:GetHighlightTexture()
  if h then h:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.25); h.eveOwn = true end
  if b.HotKey then b.HotKey:SetTextColor(unpack(C.dim)) end
end

local function IsPOI(f)
  if f.Display or f.eveIsPOI then return true end
  local n = f.GetNormalTexture and f:GetNormalTexture()
  local a = n and Low(n.GetAtlas and n:GetAtlas())
  return a ~= nil and a:find("poi") ~= nil
end

local function WalkTracker(f, depth, inPOI)
  depth = depth or 0
  if not f or depth > 9 or (f.IsForbidden and f:IsForbidden()) then return end
  if not inPOI and f.IsObjectType and f:IsObjectType("Button") and IsPOI(f) then
    f.eveIsPOI = true
    inPOI = true
  end
  if f.IsObjectType and f:IsObjectType("StatusBar") then TrackerBar(f) end
  if not inPOI and f.IsObjectType and f:IsObjectType("Button") and (f.icon or f.Icon) and f.GetNormalTexture
    and (f.HotKey or f.Count or f.Cooldown) then
    TrackerItem(f)
  end
  for _, r in ipairs({ f:GetRegions() }) do
    if r:IsObjectType("FontString") then TrackerText(r)
    elseif r:IsObjectType("Texture") then WatchTexture(r, inPOI) end
  end
  for _, c in ipairs({ f:GetChildren() }) do
    if c.MinimizeButton then ns.FlatToggle(c.MinimizeButton) end
    WalkTracker(c, depth + 1, inPOI)
  end
end
ns.WalkTracker = WalkTracker

-- Scenario stage / bonus objective banners: an EVE panel behind the text.
local function StageBlocks()
  local sc = ScenarioObjectiveTracker
  local sb = sc and sc.StageBlock
  if sb and not sb.evePanel then
    local px = ns.Px(sb)
    local p = CreateFrame("Frame", nil, sb)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)
    p:SetFrameLevel(math.max(sb:GetFrameLevel() - 1, 0))
    ns.Box(p, { 0.03, 0.05, 0.06, 0.8 }, C.line, px)
    local mark = p:CreateTexture(nil, "ARTWORK")
    mark:SetColorTexture(unpack(C.accent))
    mark:SetPoint("TOPLEFT", px, -px); mark:SetPoint("BOTTOMLEFT", px, px); mark:SetWidth(2 * px)
    sb.evePanel = p
  end
end

local function Tracker()
  if not ObjectiveTrackerFrame then return end
  zap(ObjectiveTrackerFrame.NineSlice)
  SkinHeader(ObjectiveTrackerFrame.Header, true)
  for _, n in ipairs(TRACKERS) do
    local m = _G[n]
    if m and m.Header then SkinHeader(m.Header) end
  end
  StageBlocks()
  WalkTracker(ObjectiveTrackerFrame)
end

-- HUD sweep -------------------------------------------------------------------------
-- Other Blizzard HUD pieces (widgets, toasts, banners, the talking head...):
-- decorative frame/border/parchment art is hidden, status bars go flat, and
-- frames that need a backing get an EVE panel. Icons and portraits stay.
local SWEEP_HIDE = { "border", "frame", "background", "bg$", "_bg", "%-bg", "parchment", "stone", "metal", "bronze",
  "gold", "glow", "shadow", "edge", "corner", "banner", "toast", "dialog", "nineslice", "filigree", "trim",
  "ornament", "header", "divider", "spark$" }
local SWEEP_KEEP = { "icon", "portrait", "check", "arrow", "mask", "white8x8", "temportraitalphamask", "circle" }

local function SweepTexture(tex)
  if tex.eveOwn or tex.eveHid or tex.eveFiltered then return end
  local name = Low(tex.GetAtlas and tex:GetAtlas()) or Low(tex.GetTexture and tex:GetTexture())
  if not name or tex.eveSwept == name then return end
  tex.eveSwept = name
  for _, k in ipairs(SWEEP_KEEP) do if name:find(k, 1, true) then return end end
  for _, k in ipairs(SWEEP_HIDE) do
    if name:find(k) then tex:SetAlpha(0); tex.eveHid = true; return end
  end
end

local function Sweep(f, depth)
  depth = depth or 0
  if not f or depth > 8 or (f.IsForbidden and f:IsForbidden()) or f == ns.root then return end
  if f.IsObjectType and f:IsObjectType("StatusBar") then ns.Safe("sweep bar", TrackerBar)(f) end
  for _, r in ipairs({ f:GetRegions() }) do
    if r:IsObjectType("Texture") then SweepTexture(r)
    elseif r:IsObjectType("FontString") then TrackerText(r) end
  end
  for _, c in ipairs({ f:GetChildren() }) do Sweep(c, depth + 1) end
end
ns.Sweep = Sweep

-- frame name -> needs an EVE panel behind it once its art is gone
local HUD_SWEEP = {
  UIWidgetTopCenterContainerFrame = false, UIWidgetBelowMinimapContainerFrame = false,
  UIWidgetPowerBarContainerFrame = false, PlayerPowerBarAlt = false, ZoneAbilityFrame = false,
  TalkingHeadFrame = true, LossOfControlFrame = true, GroupLootContainer = false, QueueStatusFrame = true,
  BNToastFrame = true, EventToastManagerFrame = true, BossBanner = false, LevelUpDisplay = false,
  ObjectiveTrackerBonusBannerFrame = false, ArcheologyDigsiteProgressBar = false, VehicleSeatIndicator = false,
  CompactRaidFrameManager = true, ReadyCheckListenerFrame = true, PlayerChoiceFrame = true,
  TopBannerManager = false, SplashFrame = true, RaidWarningFrame = false, LootHistoryFrame = true,
}
for i = 1, 4 do HUD_SWEEP["GroupLootFrame" .. i] = true end

local function Backing(f)
  if f.evePanel or not f.CreateTexture then return end
  local px = ns.Px(f)
  local p = CreateFrame("Frame", nil, f)
  p:SetAllPoints()
  p:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
  ns.Box(p, C.panel, C.border, px)
  f.evePanel = p
end

-- Whole screen: every other top-level Blizzard frame gets the same pass.
-- Left alone: action bars and spell glows (proc art is "glow"), the world
-- map, chat, tooltips, Edit Mode and anything with its own EveUI skin.
local SCREEN_SKIP = { "ActionBar", "MultiBar", "SpellActivation", "Overlay", "EditMode", "WorldMap", "Minimap",
  "ChatFrame", "Tooltip", "NamePlate", "MainMenuBar", "StanceBar", "PetActionBar", "Settings", "Cinematic",
  "MovieFrame", "GameMenu", "StaticPopup", "DropDown", "Menu", "^EveUI", "GlueParent", "CastingBar",
  "UIErrors", "ZoneText", "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "PetFrame", "Boss",
  "ObjectiveTracker", "BuffFrame", "DebuffFrame" }

local function ScreenPass()
  for _, f in ipairs({ UIParent:GetChildren() }) do
    if f ~= ns.root and not (f.IsForbidden and f:IsForbidden()) and f:IsVisible()
      and not f.eveSkin and not f.eveFilter and not f.eveSweep and f:GetAlpha() > 0 then
      local n = f:GetName() or ""
      local skip = false
      for _, pat in ipairs(SCREEN_SKIP) do if n:find(pat) then skip = true; break end end
      if not skip then ns.Safe("screen " .. (n ~= "" and n or "anon"), Sweep)(f) end
    end
  end
end
ns.ScreenPass = ScreenPass

function ns.SweepHUD()
  for name, panel in pairs(HUD_SWEEP) do
    local f = _G[name]
    if f and not (f.IsForbidden and f:IsForbidden()) then
      if not f.eveSweep then
        f.eveSweep = true
        local run = ns.Safe("sweep " .. name, function()
          Sweep(f)
          if panel and not (InCombatLockdown() and f.IsProtected and f:IsProtected()) then Backing(f) end
        end)
        f:HookScript("OnShow", function() run(); C_Timer.After(0.1, run) end)
        f.eveRun = run
      end
      if f:IsVisible() then f.eveRun() end
    end
  end
end

local trackerHooked
local function HookTracker()
  if trackerHooked or not ObjectiveTrackerFrame then return end
  trackerHooked = true
  local pass
  local function Queue()
    if pass then return end
    pass = true
    C_Timer.After(0, function() pass = nil; ns.Safe("tracker", Tracker)() end)
  end
  for _, n in ipairs(TRACKERS) do
    local m = _G[n]
    if m then
      for _, meth in ipairs({ "Update", "LayoutContents", "MarkDirty" }) do
        if type(m[meth]) == "function" then hooksecurefunc(m, meth, Queue) end
      end
    end
  end
  for _, meth in ipairs({ "Update", "UpdateAll" }) do
    if type(ObjectiveTrackerFrame[meth]) == "function" then hooksecurefunc(ObjectiveTrackerFrame, meth, Queue) end
  end
  ns.Every(1, "tracker art", function() if ObjectiveTrackerFrame:IsVisible() then Tracker() end end)
end
ns.HookTracker = HookTracker

-- Menus, popups, windows ----------------------------------------------------------

local WINDOWS = { "CharacterFrame", "FriendsFrame", "PVEFrame", "MerchantFrame", "MailFrame", "OpenMailFrame",
  "GossipFrame", "QuestFrame", "BankFrame", "TradeFrame", "LootFrame", "ContainerFrameCombinedBags",
  "SettingsPanel", "AddonList", "DressUpFrame", "TaxiFrame", "SpellBookFrame", "QuestLogFrame",
  "WorldMapFrame", "GuildRegistrarFrame", "PetitionFrame", "TabardFrame", "ItemTextFrame",
  "ChannelFrame", "SocialUIFrame", "RaidParentFrame", "HelpFrame", "ReadyCheckFrame", "LFGDungeonReadyDialog" }
for i = 1, 13 do WINDOWS[#WINDOWS + 1] = "ContainerFrame" .. i end

local LOD = {
  Blizzard_PlayerSpells = { "PlayerSpellsFrame" },
  Blizzard_Professions = { "ProfessionsFrame" },
  Blizzard_Collections = { "CollectionsJournal", "WardrobeFrame" },
  Blizzard_EncounterJournal = { "EncounterJournal" },
  Blizzard_AchievementUI = { "AchievementFrame" },
  Blizzard_Communities = { "CommunitiesFrame" },
  Blizzard_InspectUI = { "InspectFrame" },
  Blizzard_MacroUI = { "MacroFrame" },
  Blizzard_AuctionHouseUI = { "AuctionHouseFrame" },
  Blizzard_TalentUI = { "PlayerTalentFrame" },
  Blizzard_ClassTalentUI = { "ClassTalentFrame" },
  Blizzard_TrainerUI = { "ClassTrainerFrame" },
  Blizzard_Calendar = { "CalendarFrame" },
  Blizzard_TimeManager = { "TimeManagerFrame" },
  Blizzard_GuildBankUI = { "GuildBankFrame" },
  Blizzard_ItemSocketingUI = { "ItemSocketingFrame" },
  Blizzard_BindingUI = { "KeyBindingFrame" },
}

local function SkinGameMenu()
  local m = GameMenuFrame
  if not m then return end
  if not m.eveSkin then
    m.eveSkin = true
    zap(m.NineSlice); zap(m.Border)
    if m.Header then for _, r in ipairs({ m.Header:GetRegions() }) do if r:IsObjectType("Texture") then r:SetAlpha(0) end end end
    SkinBox(m, C.panel, C.border)
  end
  for _, child in ipairs({ m:GetChildren() }) do SkinButton(child) end
end

local function SkinPopups()
  for i = 1, 4 do
    local p = _G["StaticPopup" .. i]
    if p and not p.eveSkin then
      p.eveSkin = true
      zap(p.NineSlice); zap(p.Border); zap(p.BG)
      SkinBox(p, C.panel, C.border)
      for b = 1, 4 do SkinButton(p["button" .. b] or _G["StaticPopup" .. i .. "Button" .. b]) end
      if p.ButtonContainer then for _, child in ipairs({ p.ButtonContainer:GetChildren() }) do SkinButton(child) end end
    end
  end
end


-- Flat "x" close button.
local function SkinClose(b)
  if not b or b.eveSkin then return end
  b.eveSkin = true
  zap(b:GetNormalTexture()); zap(b:GetPushedTexture()); zap(b:GetDisabledTexture()); zap(b.Border)
  local px = ns.Px(b)
  b:SetSize(20 * px, 20 * px)
  local hl = b:GetHighlightTexture()
  if hl then hl:SetTexture(ns.WHITE); hl:SetVertexColor(C.hostile[1], C.hostile[2], C.hostile[3], 0.35); hl:SetAllPoints() end
  local x = ns.Text(b, 16, C.dim)
  x:SetPoint("CENTER", 0, px)
  x:SetText("×")
  b:HookScript("OnEnter", function() x:SetTextColor(unpack(C.title)) end)
  b:HookScript("OnLeave", function() x:SetTextColor(unpack(C.dim)) end)
  -- Sit flush in the title strip.
  local parent = b:GetParent()
  if parent then b:ClearAllPoints(); b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2 * px, -2 * px) end
end
ns.SkinClose = SkinClose

-- Square item slot: cropped icon, 1px border, quality border kept as a tint.
local function SkinItem(b, strip)
  if not b or b.eveSkin or (b.IsForbidden and b:IsForbidden()) then return end
  b.eveSkin = true
  local name = b.GetName and b:GetName()
  local icon0 = b.icon or b.Icon or (name and _G[name .. "IconTexture"])
  if strip then
    -- Paper-doll slots carry unnamed frame art; keep only the functional layers.
    local keep = { [icon0 or 0] = true, [b.IconBorder or 0] = true, [b.IconOverlay or 0] = true,
      [b.IconOverlay2 or 0] = true, [b.searchOverlay or 0] = true, [b.ItemContextOverlay or 0] = true }
    for _, r in ipairs({ b:GetRegions() }) do
      if r:IsObjectType("Texture") and not keep[r] then r:SetAlpha(0) end
    end
  end
  if b.BorderFrame then b.BorderFrame:SetAlpha(0) end
  for _, r in ipairs({ b:GetRegions() }) do
    if r:IsObjectType("Texture") and r:GetTexture() == 7349174 then r:SetAlpha(0) end  -- bag slot backdrop
  end
  if icon0 and b.Mask and icon0.RemoveMaskTexture then pcall(icon0.RemoveMaskTexture, icon0, b.Mask) end
  -- Empty bag slots use a dark slot atlas; show the plain socket instead.
  if icon0 and icon0.SetAtlas and not strip then
    hooksecurefunc(icon0, "SetAtlas", function(self) self:SetAlpha(0) end)
    hooksecurefunc(icon0, "SetTexture", function(self) self:SetAlpha(1) end)
    if icon0.GetAtlas and icon0:GetAtlas() then icon0:SetAlpha(0) end
  end
  zap(b:GetNormalTexture()); zap(b.NormalTexture); zap(b.SlotBackground); zap(b.ItemSlotBackground)
  if name then zap(_G[name .. "Frame"]); zap(_G[name .. "NormalTexture"]) end
  local icon = b.icon or b.Icon or (name and _G[name .. "IconTexture"])
  if icon and icon.SetTexCoord then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:ClearAllPoints()
    local px = ns.Px(b)
    icon:SetPoint("TOPLEFT", px, -px)
    icon:SetPoint("BOTTOMRIGHT", -px, px)
  end
  ns.Box(b, { 0, 0, 0, 0.35 }, C.line, ns.Px(b))
  -- Item quality shows as the 1px border colour instead of Blizzard's glow.
  local ib = b.IconBorder
  if ib then
    ib:SetAlpha(0)
    local box = b.eveBox
    local function Quality()
      local r, g, bl = ib:GetVertexColor()
      if ib:IsShown() and r and not (r > 0.99 and g > 0.99 and bl > 0.99) then
        for _, k in ipairs({ "top", "bottom", "left", "right" }) do box[k]:SetColorTexture(r, g, bl, 0.9) end
      else
        for _, k in ipairs({ "top", "bottom", "left", "right" }) do box[k]:SetColorTexture(unpack(C.line)) end
      end
    end
    hooksecurefunc(ib, "SetVertexColor", Quality)
    hooksecurefunc(ib, "Show", Quality)
    hooksecurefunc(ib, "Hide", Quality)
    if ib.SetShown then hooksecurefunc(ib, "SetShown", Quality) end
    hooksecurefunc(ib, "SetAtlas", function() ib:SetAlpha(0); Quality() end)
    Quality()
  end
  local hl = b.GetHighlightTexture and b:GetHighlightTexture()
  if hl then hl:SetTexture(ns.WHITE); hl:SetVertexColor(1, 1, 1, 0.12); hl:SetAllPoints(icon or b) end
  local pushed = b.GetPushedTexture and b:GetPushedTexture()
  if pushed then pushed:SetTexture(ns.WHITE); pushed:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25); pushed:SetAllPoints(icon or b) end
  if b.Count then ns.SetFont(b.Count, 12, "OUTLINE", b) end
end
ns.SkinItem = SkinItem

-- Bottom tabs (CharacterFrameTab1..) and similar.
local function SkinTabButton(t)
  if not t or t.eveSkin then return end
  t.eveSkin = true
  for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
    zap(t[k])
  end
  if t.GetHighlightTexture then zap(t:GetHighlightTexture()) end
  local px = ns.Px(t)
  local box = CreateFrame("Frame", nil, t)
  box:SetPoint("TOPLEFT", 3 * px, -5 * px)
  box:SetPoint("BOTTOMRIGHT", -3 * px, 3 * px)
  box:SetFrameLevel(math.max(t:GetFrameLevel() - 1, 0))
  ns.Box(box, C.header, C.border, px)
  local fs = t.Text or (t.GetFontString and t:GetFontString())
  if fs then fs:SetTextColor(unpack(C.title)) end
end

local function SkinScrollBar(sb)
  if not sb or sb.eveSkin then return end
  sb.eveSkin = true
  zap(sb.Background)
  if sb.Track then
    for _, r in ipairs({ sb.Track:GetRegions() }) do zap(r) end
    local thumb = sb.Track.Thumb
    if thumb then
      for _, r in ipairs({ thumb:GetRegions() }) do zap(r) end
      ns.Box(thumb, { C.border[1], C.border[2], C.border[3], 0.8 }, false, ns.Px(thumb))
    end
  end
  for _, k in ipairs({ "Back", "Forward" }) do
    local b = sb[k]
    if b then for _, r in ipairs({ b:GetRegions() }) do zap(r) end end
  end
end

local function SkinWindowParts(f)
  if not f or (f.IsForbidden and f:IsForbidden()) then return end
  local name = f:GetName()
  SkinClose(f.CloseButton or f.ClosePanelButton or (name and _G[name .. "CloseButton"]))
  for i = 1, 8 do SkinTabButton(name and _G[name .. "Tab" .. i]) end
  if f.ScrollBar then SkinScrollBar(f.ScrollBar) end
end

local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
  "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }

local function SkinCharacter()
  for _, s in ipairs(SLOTS) do SkinItem(_G["Character" .. s .. "Slot"], true) end
  -- Stat pane headers.
  local pane = CharacterStatsPane
  if pane then
    for _, child in ipairs({ pane:GetChildren() }) do
      if child.Background and not child.eveSkin then
        child.eveSkin = true
        zap(child.Background)
        ns.Box(child, C.header, C.line, ns.Px(child))
        if child.Title then child.Title:SetTextColor(unpack(C.accent)) end
      end
    end
    if pane.ScrollBar then SkinScrollBar(pane.ScrollBar) end
  end
  if PaperDollSidebarTabs then
    zap(PaperDollSidebarTabs.DecorLeft); zap(PaperDollSidebarTabs.DecorRight)
    for i = 1, 4 do
      local t = _G["PaperDollSidebarTab" .. i]
      if t and not t.eveSkin then
        t.eveSkin = true
        zap(t.TabBg)
        ns.Box(t, { 0, 0, 0, 0.4 }, C.border, ns.Px(t))
      end
    end
  end
  for _, n in ipairs({ "CharacterFrameInsetRight", "CharacterFrameInset" }) do
    local i = _G[n]
    if i and not i.eveSkin then
      i.eveSkin = true
      zap(i.NineSlice); zap(i.Bg)
      SkinBox(i, { 0, 0, 0, 0.25 }, C.line)
    end
  end
end

local function SkinBagFrame(f)
  if not f or not f.EnumerateValidItems then return end
  for _, b in f:EnumerateValidItems() do SkinItem(b) end
  local money = f.MoneyFrame
  if money and not money.eveSkin then
    money.eveSkin = true
    local border = money.Border or (money.GetParent and money:GetParent().MoneyFrameBorder)
    local holder = border or money
    if border then for _, r in ipairs({ border:GetRegions() }) do zap(r) end end
    ns.Box(holder, { 0, 0, 0, 0.35 }, C.line, ns.Px(holder))
  end
  local sbox = f.SearchBox or BagItemSearchBox
  if sbox and not sbox.eveSkin then
    sbox.eveSkin = true
    for _, r in ipairs({ sbox:GetRegions() }) do
      if r:IsObjectType("Texture") and r ~= sbox.searchIcon and r:GetDrawLayer() == "BACKGROUND" then zap(r) end
    end
    local name = sbox:GetName()
    if name then zap(_G[name .. "Left"]); zap(_G[name .. "Middle"]); zap(_G[name .. "Right"]) end
    ns.Box(sbox, { 0, 0, 0, 0.4 }, C.line, ns.Px(sbox))
  end
end

local function Bags()
  local frames = { ContainerFrameCombinedBags }
  for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
  for _, f in ipairs(frames) do
    if f and f.UpdateItems then
      hooksecurefunc(f, "UpdateItems", function(self) ns.Safe("bag items", SkinBagFrame)(self) end)
    end
    if f then f:HookScript("OnShow", function(self) ns.Safe("bag items", SkinBagFrame)(self) end) end
  end
end

-- Atlas filter: walks a window and strips or recolours Blizzard's stone and
-- bronze art by atlas name, so pooled rows and new panes get the same look.
local HIDE = { "^UI%-Character%-Info%-.*BG$", "StoneBG", "ScrollLine", "GearSlot", "^common%-insideframe",
  "InnerTopTile", "Metal%-Corner", "Metal%-Edge", "StatTab", "^common%-sidetab$", "^common%-sidetab%-mask",
  "^minimal%-scrollbar%-track", "^minimal%-scrollbar%-arrow", "^UI%-Frame%-DiamondMetal", "^QuestLog%-.*BG",
  "^bags%-item%-slot%-blank$", "^bag%-border", "^bags%-roundhighlight",
  "^spellbook%-Page", "^spellbook%-Tab%-Frame", "^spellbook%-item%-backplate", "^spellbook%-list%-backplate",
  "^spellbook%-item%-iconframe$", "^common%-search%-border", "^QuestLog%-main%-background", "^QuestLog%-frame",
  "^QuestLog%-Frame%-Gradient", "UI%-Frame%-Inner", "^MapCornerShadow", "^gamepad%-mapquestlog",
  "^talents%-node%-circle%-gray$", "^UI%-Character%-Info%-RaceBG%-Overlay",
  "^collections%-background", "^uiframe%-activetab", "^uiframe%-tab", "^communities%-widebackground",
  "^Professions%-.*[Bb]ackground", "^professions%-.*bg", "^achievement%-.*background", "^UI%-EJ%-.*Background",
  "^groupfinder%-background", "^PVE%-.*Background", "^talents%-background", "^spec%-background",
  "^UI%-Frame%-Neutral", "^UI%-Frame%-Metal", "^ui%-frame%-portraitmetal", "^MerchantFrame%-", "^Merchant%-",
  "^QuestDetailsBackground", "^QuestBG", "^questlog%-.*bg", "^GossipFrame%-.*Background", "^Gossip%-",
  "^loottoast%-bg", "^LootBanner", "^Garr_", "^mail%-", "^Mail%-",
  "^friends%-frame%-.*BG$", "minimal%-scrollbar%-track", "^common%-searchbar%-a$" }
-- Red and gold controls: keep the glyph, recolour to steel.
local STEEL = { "RedButton", "^common%-dropdown", "^QuestCollapse", "^common%-button%-square", "^common%-icon%-",
  "^QuestLog%-icon%-setting", "^common%-button%-tertiary", "^common%-button%-list%-minus", "^common%-button%-list%-plus",
  "^friends%-icon%-" }
local HIDE_FILES = { [374155] = true, [7349174] = true, [516764] = true, [374154] = true,
  [593917] = true, [593918] = true, [593919] = true, [413583] = true }  -- top strip; bag slot backdrop; map nav bar
local TINT = {
  { "^UI%-Character%-Info%-Title", C.header },
  { "Line%-Bounce", { 1, 1, 1, 0.03 } },
  { "^minimal%-scrollbar%-small%-thumb", C.border },
  { "^minimal%-scrollbar%-thumb", C.border },
  { "^common%-framedivider", C.line },
  { "^spellbook%-divider", C.line, 1 },
  { "^common%-sidetab%-selected", { C.accent[1], C.accent[2], C.accent[3], 0.35 } },
  { "^common%-sidetab%-hover", { 1, 1, 1, 0.12 } },
  { "^perks%-divider", C.line, 1 },
  { "^common%-button%-list%-collapseExpand", C.header },
  { "^friends%-card%-disabled", { 1, 1, 1, 0.03 } },
  { "^friends%-card%-selected", { C.accent[1], C.accent[2], C.accent[3], 0.15 } },
  { "^transmog%-nav%-slot%-selected", { C.accent[1], C.accent[2], C.accent[3], 0.35 } },
}

local function FilterTexture(r)
  if r.eveFiltered then return end
  local atlas = r.GetAtlas and r:GetAtlas()
  local file = not atlas and r.GetTexture and r:GetTexture()
  if type(atlas) == "string" then
    for _, pat in ipairs(HIDE) do
      if atlas:find(pat) then r:SetAlpha(0); r.eveFiltered = true; return end
    end
    for _, pat in ipairs(STEEL) do
      if atlas:find(pat) then
        r:SetDesaturated(true)
        r:SetVertexColor(0.62, 0.78, 0.9)
        r.eveFiltered = true
        return
      end
    end
    for _, t in ipairs(TINT) do
      if atlas:find(t[1]) then
        r:SetColorTexture(t[2][1], t[2][2], t[2][3], t[2][4] or 1)
        if t[3] then r:SetHeight(t[3] * ns.Px(r:GetParent())) end
        r.eveFiltered = true
        return
      end
    end
  elseif type(file) == "number" and HIDE_FILES[file] then
    r:SetAlpha(0); r.eveFiltered = true
  end
end

local function Steel(f, depth)
  depth = depth or 0
  if not f or depth > 4 then return end
  for _, r in ipairs({ f:GetRegions() }) do
    if r:IsObjectType("Texture") then r:SetDesaturated(true); r:SetVertexColor(0.55, 0.68, 0.78) end
  end
  for _, c in ipairs({ f:GetChildren() }) do Steel(c, depth + 1) end
end
ns.SteelArt = Steel

local function Filter(f, depth)
  depth = depth or 0
  if not f or depth > 10 or (f.IsForbidden and f:IsForbidden()) then return end
  for _, r in ipairs({ f:GetRegions() }) do
    if r:IsObjectType("FontString") then
      -- Text coloured for parchment (dark brown) becomes light on the dark panels.
      local cr, cg, cb = r:GetTextColor()
      if cr and not ns.issecret(cr) and (0.3 * cr + 0.59 * cg + 0.11 * cb) < 0.32 then
        if cr > cb + 0.05 and r:GetStringHeight() < 13 then r:SetTextColor(unpack(C.dim)) else r:SetTextColor(unpack(C.title)) end
      elseif cr and not ns.issecret(cr) and cr > 0.95 and cg > 0.7 and cg < 0.9 and cb < 0.2 then
        -- Blizzard gold labels become EVE white.
        r:SetTextColor(unpack(C.title))
      end
    elseif r:IsObjectType("Texture") then
      local atlas = r.GetAtlas and r:GetAtlas()
      FilterTexture(r)
      -- Search boxes lose their border art; give them a flat box.
      if type(atlas) == "string" and (atlas:find("^common%-search%-border") or atlas:find("^common%-searchbar%-a$")) and not f.eveBox then
        ns.Box(f, { 0, 0, 0, 0.4 }, C.line, ns.Px(f))
      end
    end
  end
  for _, c in ipairs({ f:GetChildren() }) do
    -- Standard red panel buttons (Left/Middle/Right art) get the flat button.
    if not c.eveSkin and c.Left and c.Middle and c.Right and c.IsObjectType and c:IsObjectType("Button") then
      SkinButton(c)
    end
    Filter(c, depth + 1)
  end
end
ns.FilterArt = Filter

-- Hook a window so the filter runs whenever it opens or its lists refresh.
-- Windows whose contents are rebuilt while open (pages, gossip, quests) get
-- re-filtered a few times a second while shown.
local LIVE = { PlayerSpellsFrame = true, SpellBookFrame = true, GossipFrame = true, QuestFrame = true,
  ItemTextFrame = true, MerchantFrame = true, QuestLogFrame = true, ClassTrainerFrame = true }

local function FilterOnShow(f)
  if not f or f.eveFilter then return end
  f.eveFilter = true
  local name = f:GetName() or "?"
  local run = ns.Safe("filter " .. name, function() Filter(f) end)
  f:HookScript("OnShow", function() run(); C_Timer.After(0, run) end)
  if LIVE[name] then
    local t = 0
    f:HookScript("OnUpdate", function(_, el)
      t = t + el
      if t > 0.4 then t = 0; run() end
    end)
  end
  if f:IsShown() then run() end
end

-- Small dialogs (DialogBorderTemplate and friends): no title strip.
local DIALOGS = { "AddFriendFrame", "FriendsFriendsFrame", "BattleTagInviteFrame", "ReportFrame",
  "ReportPlayerNameDialog", "ColorPickerFrame", "OpacityFrame", "GuildInviteFrame" }

local function SkinDialog(f)
  if not f or f.eveSkin or (f.IsForbidden and f:IsForbidden()) then return end
  f.eveSkin = true
  zap(f.NineSlice); zap(f.Border); zap(f.BG); zap(f.Bg); zap(f.Background)
  for _, k in ipairs({ "BorderTopLeft", "BorderTopRight", "BorderBottomLeft", "BorderBottomRight", "BorderTop",
    "BorderBottom", "BorderLeft", "BorderRight" }) do zap(f[k]) end
  SkinBox(f, C.panel, C.border)
  -- Child panels drawn as their own dialogs (e.g. AddFriendInfoFrame).
  for _, c in ipairs({ f:GetChildren() }) do
    if (c.NineSlice or c.Border) and not c.eveSkin then
      zap(c.NineSlice); zap(c.Border); zap(c.BG); zap(c.Bg)
      if c:GetWidth() > 100 then SkinBox(c, C.panel, C.border) end
      c.eveSkin = true
    end
  end
end

local function Windows()
  for _, n in ipairs(DIALOGS) do
    ns.Safe("dialog " .. n, SkinDialog)(_G[n])
    FilterOnShow(_G[n])
  end
  for _, n in ipairs(WINDOWS) do
    ns.Safe("skin " .. n, SkinWindow)(_G[n])
    ns.Safe("parts " .. n, SkinWindowParts)(_G[n])
    FilterOnShow(_G[n])
  end
  if WorldMapFrame and WorldMapFrame.NavBar then
    local nav = WorldMapFrame.NavBar
    local run = ns.Safe("map nav", function() Steel(nav) end)
    WorldMapFrame:HookScript("OnShow", run)
    if NavBar_AddButton then hooksecurefunc("NavBar_AddButton", run) end
  end
  if CharacterStatsPaneScrollBox and CharacterStatsPaneScrollBox.ScrollBox then
    local sb = CharacterStatsPaneScrollBox.ScrollBox
    if sb.Update then hooksecurefunc(sb, "Update", function() ns.Safe("filter stats", Filter)(CharacterStatsPaneScrollBox) end) end
  end
  if CharacterFrame then CharacterFrame:HookScript("OnShow", ns.Safe("character", SkinCharacter)) end
  ns.Safe("character", SkinCharacter)()
  ns.Safe("bags", Bags)()
  if GameMenuFrame then GameMenuFrame:HookScript("OnShow", ns.Safe("game menu", SkinGameMenu)) end
  SkinPopups()
  if StaticPopup_Show then hooksecurefunc("StaticPopup_Show", ns.Safe("popups", SkinPopups)) end
  local lod = CreateFrame("Frame")
  lod:RegisterEvent("ADDON_LOADED")
  lod:SetScript("OnEvent", function(_, _, name)
    for _, n in ipairs(DIALOGS) do
      local w = _G[n]
      if w and not w.eveSkin then ns.Safe("dialog " .. n, SkinDialog)(w); FilterOnShow(w) end
    end
    -- Windows created late (by any addon) get picked up here.
    for _, n in ipairs(WINDOWS) do
      local w = _G[n]
      if w and not w.eveSkin then
        ns.Safe("skin " .. n, SkinWindow)(w)
        ns.Safe("parts " .. n, SkinWindowParts)(w)
        FilterOnShow(w)
      end
    end
    for _, n in ipairs(LOD[name] or {}) do
      ns.Safe("skin " .. n, SkinWindow)(_G[n])
      ns.Safe("parts " .. n, SkinWindowParts)(_G[n])
      FilterOnShow(_G[n])
    end
    if name == "Blizzard_HybridMinimap" and HybridMinimap and HybridMinimap.CircleMask then
      HybridMinimap.CircleMask:SetTexture(ns.WHITE)
    end
  end)
  for name, list in pairs(LOD) do
    if C_AddOns and C_AddOns.IsAddOnLoaded(name) then
      for _, n in ipairs(list) do
        ns.Safe("skin " .. n, SkinWindow)(_G[n])
        ns.Safe("parts " .. n, SkinWindowParts)(_G[n])
        FilterOnShow(_G[n])
      end
    end
  end
end

-- Misc ------------------------------------------------------------------------

local function Misc()
  if UIErrorsFrame then
    local _, size = UIErrorsFrame:GetFont()
    UIErrorsFrame:SetFont(ns.FONT, size or 16, "")
  end
end

ns.RegisterModule(function()
  ns.Safe("tooltips", Tooltips)()
  ns.Safe("chat", Chat)()
  ns.Safe("auras", Auras)()
  ns.Safe("tracker", Tracker)()
  ns.Safe("tracker hooks", HookTracker)()
  ns.Safe("hud sweep", ns.SweepHUD)()
  ns.Every(2, "hud sweep", function() if not InCombatLockdown() then ns.SweepHUD() end end)
  ns.Every(5, "screen sweep", function() if not InCombatLockdown() then ScreenPass() end end)
  ns.Safe("windows", Windows)()
  ns.Safe("misc", Misc)()
  ns.OnLayout(function()
    Tracker()
    SkinAuras()
  end)
end)

-- Nameplates -------------------------------------------------------------------



local SkinPlateCast
ns.plateTrace = {}

local function HealthBar(uf)
  return uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
end

local function SkinBar(bar, h)
  if not bar or bar.eveSkin then return end
  bar.eveSkin = true
  bar:SetStatusBarTexture(ns.WHITE)
  zap(bar.border); zap(bar.Border); zap(bar.background); zap(bar.bgTexture)
  for _, r in ipairs({ bar:GetRegions() }) do
    if r:IsObjectType("Texture") and r ~= bar:GetStatusBarTexture() then
      local layer = r:GetDrawLayer()
      if layer == "BORDER" or layer == "OVERLAY" or layer == "BACKGROUND" then
        if not (bar.eveBox and (r == bar.eveBox.bg or r == bar.eveBox.top)) then r:SetAlpha(0) end
      end
    end
  end
  local holder = CreateFrame("Frame", nil, bar)
  local px = ns.Px(bar)
  holder:SetPoint("TOPLEFT", -px, px)
  holder:SetPoint("BOTTOMRIGHT", px, -px)
  holder:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
  ns.Box(holder, { 0, 0, 0, 0.6 }, { 0, 0, 0, 1 }, px)
end

-- Nameplate cast bars: same palette as the cycle rings. Blizzard swaps the
-- fill art per state (barType); each swap is turned back into a flat colour.
local PLATE_CAST = {
  standard = C.cast, channel = C.accent, uninterruptable = { 0.62, 0.70, 0.76, 1 },
  interrupted = C.hostile, empowered = C.cap,
}
SkinPlateCast = function(cb)
  if not cb or cb.eveCast then return end
  cb.eveCast = true
  SkinBar(cb)
  zap(cb.Border); zap(cb.BorderShield); zap(cb.TextBorder); zap(cb.Shine)
  local busy
  local function Paint(self)
    if busy then return end
    busy = true
    local c = PLATE_CAST[self.barType or "standard"] or C.cast
    if self.barType == "interrupted" or self.failed then c = C.hostile end
    self:SetStatusBarTexture(ns.WHITE)
    self:SetStatusBarColor(c[1], c[2], c[3])
    busy = false
  end
  hooksecurefunc(cb, "SetStatusBarTexture", Paint)
  hooksecurefunc(cb, "SetStatusBarColor", Paint)
  Paint(cb)
  local px = ns.Px(cb)
  if cb.Spark then
    cb.Spark:SetTexture(ns.WHITE)
    cb.Spark:SetVertexColor(1, 1, 1, 0.95)
    cb.Spark:SetSize(px, cb:GetHeight())
    cb.Spark:SetAlpha(1)
  end
  -- Success / interrupt flash: tinted white, Blizzard's own animation fades it.
  if cb.Flash then
    cb.Flash:SetTexture(ns.WHITE)
    cb.Flash:ClearAllPoints()
    cb.Flash:SetAllPoints(cb)
    cb.Flash:SetVertexColor(0.8, 0.97, 1, 0.8)
    cb.Flash:SetBlendMode("ADD")
  end
  if cb.Icon then
    cb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cb.Icon:SetAlpha(1)
    if not cb.Icon.eveBox then
      local holder = CreateFrame("Frame", nil, cb)
      holder:SetPoint("TOPLEFT", cb.Icon, "TOPLEFT", -px, px)
      holder:SetPoint("BOTTOMRIGHT", cb.Icon, "BOTTOMRIGHT", px, -px)
      ns.Box(holder, false, { 0, 0, 0, 1 }, px)
      cb.Icon.eveBox = holder
    end
  end
  -- Remaining time, right-aligned under the bar like the cycle rings. Cast
  -- values can be secret for other units; then the figure stays hidden.
  local tm = cb:CreateFontString(nil, "OVERLAY")
  ns.SetFont(tm, 9, "OUTLINE", cb)
  tm:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  tm:SetPoint("TOPRIGHT", cb, "BOTTOMRIGHT", 0, -2)
  cb.eveTime = tm
  -- Fill direction: casts fill left to right, channels drain. Undo any
  -- reverse fill or count-down timer Blizzard sets for a normal cast.
  local function IsChannel(self) return self.channeling or self.barType == "channel" end
  if cb.SetReverseFill then
    cb:SetReverseFill(false)
    local busyR
    hooksecurefunc(cb, "SetReverseFill", function(self, on)
      if busyR or not on then return end
      busyR = true; self:SetReverseFill(false); busyR = false
    end)
  end
  local DIR = Enum and Enum.StatusBarTimerDirection
  if cb.SetTimerDuration and DIR then
    local busyD
    hooksecurefunc(cb, "SetTimerDuration", function(self, dur, interp, dir)
      if busyD or self.barType == "empowered" then return end
      local want = IsChannel(self) and DIR.RemainingTime or DIR.ElapsedTime
      if (dir or DIR.ElapsedTime) == want then return end
      busyD = true; pcall(self.SetTimerDuration, self, dur, interp, want); busyD = false
    end)
  end
  -- Trace: first and last plain value of each cast, kept in EveUIDB.plateTrace.
  local rec
  cb:HookScript("OnShow", function(self)
    rec = { type = tostring(self.barType), channel = IsChannel(self) and true or false, values = {} }
    local t = ns.plateTrace
    t[#t + 1] = rec
    if #t > 12 then table.remove(t, 1) end
    if EveUIDB then EveUIDB.plateTrace = t end
  end)
  cb:HookScript("OnHide", function()
    if rec and #rec.values >= 2 then
      local a, b = rec.values[1], rec.values[#rec.values]
      if a ~= b then rec.reversed = (b < a) ~= rec.channel end
    end
    rec = nil
  end)
  local acc = 0
  local Tick = ns.Safe("plate timer", function(self)
    local left
    if self.barType ~= "interrupted" and not self.failed then
      local v = self:GetValue()
      local mn, mx = self:GetMinMaxValues()
      if not (ns.issecret(v) or ns.issecret(mx) or ns.issecret(mn)) and v and mx then
        left = IsChannel(self) and v or (mx - v)
        if rec and #rec.values < 8 and mx > (mn or 0) then
          rec.values[#rec.values + 1] = math.floor(((v - (mn or 0)) / (mx - (mn or 0))) * 100 + 0.5) / 100
        end
      end
    end
    if left and left > 0 then tm:SetFormattedText("%.1f", left); tm:Show() else tm:Hide() end
  end)
  cb:HookScript("OnUpdate", function(self, el)
    acc = acc + el
    if acc < 0.05 then return end
    acc = 0
    Tick(self)
  end)
  if cb.Text then
    ns.SetFont(cb.Text, 9, "OUTLINE", cb)
    cb.Text:SetTextColor(unpack(C.title))
    local busyT
    hooksecurefunc(cb.Text, "SetText", function(self, t)
      if busyT or t == nil or ns.issecret(t) then return end
      busyT = true; self:SetText(t:upper()); busyT = false
    end)
  end
end

-- /eve preview plate: show each visible nameplate's cast bar in one state
-- (cast, channel, locked, interrupted) so the styling can be checked.
function ns.PreviewPlateCast()
  local kinds = { "standard", "channel", "uninterruptable", "interrupted" }
  local labels = { "Shadow Bolt", "Drain Life", "Holy Fire", "Interrupted" }
  ns.plateStep = (ns.plateStep or 0) + 1
  local i = ns.plateStep - 1
  for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local uf = p.UnitFrame
    local cb = uf and (uf.castBar or uf.CastBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar))
    if cb then
      i = i % #kinds + 1
      SkinPlateCast(cb)
      cb.barType = kinds[i]
      cb:SetMinMaxValues(0, 2.5)
      cb:SetValue(i == 4 and 2.5 or 0.4 * i + 0.3)
      cb:SetStatusBarColor(1, 1, 1)
      if cb.Text then cb.Text:SetText(labels[i]) end
      if cb.Icon then cb.Icon:SetTexture(136197); cb.Icon:Show() end
      if cb.Spark then cb.Spark:SetShown(i ~= 4) end
      cb:SetAlpha(1)
      cb:Show()
      C_Timer.After(6, function() cb:Hide() end)
    end
  end
  ns.Print("plate cast preview: " .. kinds[(ns.plateStep - 1) % #kinds + 1])
end

local function Skin(plate)
  local uf = plate and plate.UnitFrame
  if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
  SkinBar(HealthBar(uf))
  if uf.HealthBarsContainer and uf.HealthBarsContainer.border then zap(uf.HealthBarsContainer.border) end
  SkinPlateCast(uf.castBar or uf.CastBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar))
  -- Level badge: plain outlined number instead of the gold disc.
  local lv = uf.PlayerLevelDiffFrame
  if lv and not lv.eveSkin then
    lv.eveSkin = true
    for _, r in ipairs({ lv:GetRegions() }) do
      if r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    if lv.playerLevelDiffText then
      ns.SetFont(lv.playerLevelDiffText, 10, "OUTLINE", lv)
      local hb = HealthBar(uf)
      if hb then
        lv.playerLevelDiffText:ClearAllPoints()
        lv.playerLevelDiffText:SetPoint("LEFT", hb, "RIGHT", 4, 0)
      end
    end
  end
  if uf.LevelFrame and uf.LevelFrame.LevelText then ns.SetFont(uf.LevelFrame.LevelText, 10, "OUTLINE", uf.LevelFrame) end
  if uf.name and not uf.name.eveSkin then
    uf.name.eveSkin = true
    ns.SetFont(uf.name, 11, "OUTLINE", uf)
  end
  if uf.selectionHighlight then
    uf.selectionHighlight:SetTexture(ns.WHITE)
    uf.selectionHighlight:SetVertexColor(1, 1, 1, 0.18)
  end
  zap(uf.LevelFrame and uf.LevelFrame.Background)
end

ns.RegisterModule(function()
  local f = CreateFrame("Frame")
  f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  f:SetScript("OnEvent", ns.Safe("nameplates", function(_, _, unit)
    Skin(C_NamePlate.GetNamePlateForUnit(unit))
  end))
  for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do ns.Safe("nameplates", Skin)(p) end
end)
