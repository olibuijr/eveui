-- Missions: quests as EVE agent missions.
--
-- Agent conversation: when an NPC offers, checks or rewards a quest (or a
-- gossip window lists quests) an EVE agent panel docks beside the Blizzard
-- window: portrait, agent name and corp, mission title, briefing, objectives,
-- rewards and Accept / Decline / Complete buttons. The buttons call the same
-- functions as Blizzard's quest buttons (AcceptQuest, CompleteQuest,
-- GetQuestReward ...); none of them is protected, and they run on the
-- player's own click. The Blizzard window stays usable underneath; in
-- "replace" mode it is only faded to alpha 0 and covered, never hidden.
--
-- Journal (/eve missions): the quest log as a mission list (level, zone,
-- status, objective progress) with the briefing on the right.
--
-- Briefings written by the pilot service (Briefings.lua, EveUIBriefings) are
-- used when present; otherwise the game's own quest text.
local ADDON, ns = ...
local C = ns.C
local issecret = ns.issecret

local function Plain(v)
  if v == nil or issecret(v) then return nil end
  return v
end
local function Str(v) v = Plain(v); return type(v) == "string" and v or nil end
local function Num(v) v = Plain(v); return type(v) == "number" and v or 0 end
local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return ns.Call(fn, ...)
end
local function Shown(f) return f and f.IsShown and f:IsShown() end

local function Tidy(s)
  s = Str(s)
  if not s then return nil end
  s = s:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n[ \t]*\n[%s]*", "\n\n")
  return s ~= "" and s or nil
end

local function Brief(qid)
  local t = type(EveUIBriefings) == "table" and qid and EveUIBriefings[qid]
  return type(t) == "table" and t or nil
end

local function Coins(m)
  if m <= 0 then return nil end
  if GetMoneyString then
    local s = Call(GetMoneyString, m, true)
    if s then return s end
  end
  return ("%dg %ds %dc"):format(math.floor(m / 10000), math.floor(m / 100) % 100, m % 100)
end

local function Big(n)
  return (BreakUpLargeNumbers and Call(BreakUpLargeNumbers, n)) or tostring(n)
end

local function QualityRGB(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c and c.r then return c.r, c.g, c.b end
  return C.text[1], C.text[2], C.text[3]
end

-- Quest data ----------------------------------------------------------------------

local function LogObjectives(qid)
  local list = {}
  if not (qid and C_QuestLog and C_QuestLog.GetQuestObjectives) then return list end
  local objs = Call(C_QuestLog.GetQuestObjectives, qid)
  if type(objs) ~= "table" then return list end
  for _, o in ipairs(objs) do
    local t = Str(o.text)
    if t and t ~= "" then
      list[#list + 1] = { text = t, done = Plain(o.finished) == true,
        have = Num(o.numFulfilled), need = Num(o.numRequired) }
    end
  end
  return list
end

local function SplitObjectives(text)
  local list = {}
  text = Tidy(text)
  if not text then return list end
  for line in text:gmatch("[^\n]+") do
    line = line:gsub("^%s*[-*]?%s*", ""):gsub("%s+$", "")
    if line ~= "" then list[#list + 1] = { text = line } end
  end
  return list
end

-- Fraction of objectives done, 0..1.
local function Progress(list, complete)
  if complete then return 1 end
  if #list == 0 then return 0 end
  local sum = 0
  for _, o in ipairs(list) do
    if o.done then sum = sum + 1
    elseif o.need and o.need > 0 then sum = sum + math.min(o.have or 0, o.need) / o.need end
  end
  return sum / #list
end

-- Rewards on the quest dialog (offer / turn-in).
local function OfferRewards()
  local r = { items = {}, choices = {} }
  r.xp = Num(Call(GetRewardXP))
  r.money = Num(Call(GetRewardMoney))
  local function Add(list, kind, i)
    local name, tex, count, quality, usable = Call(GetQuestItemInfo, kind, i)
    if not tex and not name then return end
    list[#list + 1] = { name = Str(name), icon = tex, count = Num(count), quality = Plain(quality),
      usable = Plain(usable) ~= false, choice = kind == "choice", index = i,
      tip = function(tt) tt:SetQuestItem(kind, i) end,
      link = function() return Call(GetQuestItemLink, kind, i) end }
  end
  for i = 1, Num(Call(GetNumQuestChoices)) do Add(r.choices, "choice", i) end
  for i = 1, Num(Call(GetNumQuestRewards)) do Add(r.items, "reward", i) end
  if C_QuestOffer and C_QuestOffer.GetQuestRewardCurrencyInfo then
    for i = 1, Num(Call(GetNumRewardCurrencies)) do
      local info = Call(C_QuestOffer.GetQuestRewardCurrencyInfo, "reward", i)
      if type(info) == "table" then
        r.items[#r.items + 1] = { name = Str(info.name), icon = info.texture, count = Num(info.totalRewardAmount),
          quality = Plain(info.quality), usable = true,
          tip = function(tt) tt:SetQuestCurrency("reward", i) end }
      end
    end
  end
  return r
end

local function RequiredItems()
  local list = {}
  for i = 1, Num(Call(GetNumQuestItems)) do
    local name, tex, count, quality = Call(GetQuestItemInfo, "required", i)
    if tex or name then
      list[#list + 1] = { name = Str(name), icon = tex, count = Num(count), quality = Plain(quality), usable = true,
        tip = function(tt) tt:SetQuestItem("required", i) end,
        link = function() return Call(GetQuestItemLink, "required", i) end }
    end
  end
  return list
end

-- Rewards of a quest in the log (by quest ID, no selection change).
local function LogRewards(qid)
  local r = { items = {}, choices = {} }
  r.xp = Num(Call(GetQuestLogRewardXP, qid))
  r.money = Num(Call(GetQuestLogRewardMoney, qid))
  local function Add(list, kind, i, fn)
    local name, tex, count, quality, usable = Call(fn, i, qid)
    if not tex and not name then return end
    list[#list + 1] = { name = Str(name), icon = tex, count = Num(count), quality = Plain(quality),
      usable = Plain(usable) ~= false,
      tip = function(tt) tt:SetQuestLogItem(kind, i, qid) end,
      link = function() return Call(GetQuestLogItemLink, kind, i, qid) end }
  end
  for i = 1, Num(Call(GetNumQuestLogChoices, qid, true)) do Add(r.choices, "choice", i, GetQuestLogChoiceInfo) end
  for i = 1, Num(Call(GetNumQuestLogRewards, qid)) do Add(r.items, "reward", i, GetQuestLogRewardInfo) end
  return r
end

-- NPC title line from the tooltip ("<Innkeeper>"), used as the agent's corp.
local function NpcTitle(unit)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
  local data = Call(C_TooltipInfo.GetUnit, unit)
  local lines = type(data) == "table" and Plain(data.lines)
  if type(lines) ~= "table" then return nil end
  for i = 2, math.min(#lines, 3) do
    local t = type(lines[i]) == "table" and Str(lines[i].leftText)
    local inner = t and t:match("^<(.+)>$")
    if inner then return inner end
  end
end

local function Location()
  local zone, sub = Str(Call(GetZoneText)), Str(Call(GetSubZoneText))
  if sub and sub ~= "" and sub ~= zone then return sub .. ", " .. (zone or "") end
  return zone or ""
end

-- Widgets -------------------------------------------------------------------------

local function Btn(parent, label, w, onClick, primary)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 24)
  b.primary = primary
  ns.Box(b, primary and { 0.05, 0.13, 0.15, 0.95 } or { 0.06, 0.08, 0.10, 0.95 }, primary and C.accent or C.border)
  b.text = ns.Text(b, 11, primary and C.accent or C.title)
  b.text:SetFont(ns.FONT_BOLD, 11, "")
  b.text:SetPoint("CENTER")
  function b:SetLabel(t) self.text:SetText(t:upper()) end
  function b:SetOn(on)
    self:SetEnabled(on)
    self.text:SetTextColor(unpack(on and (self.primary and C.accent or C.title) or C.dim))
    ns.SetBoxBorder(self, on and (self.primary and C.accent or C.border) or C.line)
  end
  b:SetLabel(label)
  b:SetScript("OnEnter", function(self) if self:IsEnabled() then ns.SetBoxBorder(self, C.title) end end)
  b:SetScript("OnLeave", function(self) ns.SetBoxBorder(self, self:IsEnabled() and (self.primary and C.accent or C.border) or C.line) end)
  b:SetScript("OnClick", function(self, ...) if onClick then ns.Safe("missions button", onClick)(self, ...) end end)
  return b
end

local function CloseX(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(ns.HEADER - 2, ns.HEADER - 2)
  b:SetPoint("TOPRIGHT", -1, -1)
  b.text = ns.Text(b, 13, C.dim)
  b.text:SetPoint("CENTER")
  b.text:SetText("X")
  b:SetScript("OnEnter", function(s) s.text:SetTextColor(unpack(C.hostile)) end)
  b:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(C.dim)) end)
  b:SetScript("OnClick", onClick)
  return b
end

local function HLine(parent, y, x1, x2)
  local l = parent:CreateTexture(nil, "ARTWORK")
  l:SetColorTexture(unpack(C.line))
  l:SetHeight(1)
  l:SetPoint("TOPLEFT", x1 or 1, -y)
  l:SetPoint("TOPRIGHT", x2 or -1, -y)
  return l
end

local function MakeScroll(parent, w)
  local s = CreateFrame("ScrollFrame", nil, parent)
  s:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, s)
  child:SetSize(w, 1)
  s:SetScrollChild(child)
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(unpack(C.accent))
  thumb:SetAlpha(0.6)
  thumb:SetWidth(2)
  local function Thumb()
    local range, h = s:GetVerticalScrollRange() or 0, s:GetHeight() or 0
    if range <= 1 or h <= 0 then thumb:Hide() return end
    local th = math.max(16, h * h / (h + range))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, -(h - th) * (s:GetVerticalScroll() or 0) / range)
    thumb:Show()
  end
  s:SetScript("OnMouseWheel", function(self, d)
    local range = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - d * 40)))
    Thumb()
  end)
  s:SetScript("OnScrollRangeChanged", Thumb)
  s.Thumb = Thumb
  return s, child
end

-- Doc: a vertical stack of text, headers, bullets and reward cells in a scroll
-- child, rebuilt from pools on every render.
local Doc = {}
Doc.__index = Doc

local function NewDoc(scroll, child, w)
  return setmetatable({ s = scroll, f = child, w = w, pools = {}, used = {}, y = 0 }, Doc)
end

function Doc:Take(kind, make)
  local pool = self.pools[kind] or {}
  self.pools[kind] = pool
  local n = (self.used[kind] or 0) + 1
  self.used[kind] = n
  local o = pool[n]
  if not o then o = make(self.f, self); pool[n] = o end
  o:ClearAllPoints()
  o:Show()
  return o
end

function Doc:Clear()
  for _, pool in pairs(self.pools) do
    for _, o in ipairs(pool) do o:Hide() end
  end
  self.used = {}
  self.y = 2
end

function Doc:Finish(keepScroll)
  self.f:SetHeight(math.max(1, self.y + 8))
  if not keepScroll then self.s:SetVerticalScroll(0) end
  C_Timer.After(0, self.s.Thumb)
end

local function MakeText(p)
  local fs = p:CreateFontString(nil, "OVERLAY")
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  return fs
end

-- o: size, color, bold, x, gap
function Doc:Text(text, o)
  o = o or {}
  local fs = self:Take("text", MakeText)
  local x = o.x or 0
  ns.SetFont(fs, o.size or 12)
  if o.bold then fs:SetFont(ns.FONT_BOLD, o.size or 12, "") end
  fs:SetTextColor(unpack(o.color or C.text))
  fs:SetWidth(self.w - x - 10)
  fs:SetPoint("TOPLEFT", x, -self.y)
  fs:SetText(text or "")
  self.y = self.y + math.ceil(fs:GetStringHeight() or 12) + (o.gap or 6)
  return fs
end

function Doc:Header(label)
  self.y = self.y + 6
  local h = self:Take("head", function(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(14)
    f.text = ns.Text(f, 10, C.dim, "LEFT")
    f.text:SetFont(ns.FONT_BOLD, 10, "")
    f.text:SetPoint("LEFT")
    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetColorTexture(unpack(C.line))
    f.line:SetHeight(1)
    f.line:SetPoint("LEFT", f.text, "RIGHT", 8, 0)
    f.line:SetPoint("RIGHT", -10, 0)
    return f
  end)
  h:SetWidth(self.w)
  h:SetPoint("TOPLEFT", 0, -self.y)
  h.text:SetText(label:upper())
  self.y = self.y + 20
end

function Doc:Bullet(o)
  local b = self:Take("bullet", function(p)
    local f = CreateFrame("Frame", nil, p)
    f.mark = f:CreateTexture(nil, "ARTWORK")
    f.mark:SetSize(5, 5)
    f.mark:SetPoint("TOPLEFT", 3, -5)
    f.text = MakeText(f)
    f.text:SetPoint("TOPLEFT", 14, 0)
    return f
  end)
  ns.SetFont(b.text, 12)
  b.text:SetWidth(self.w - 24)
  b.text:SetText(o.text)
  b.text:SetTextColor(unpack(o.done and C.dim or C.text))
  b.mark:SetColorTexture(unpack(o.done and C.heal or C.accent))
  local h = math.ceil(b.text:GetStringHeight() or 12)
  b:SetSize(self.w, h)
  b:SetPoint("TOPLEFT", 0, -self.y)
  self.y = self.y + h + 4
end

function Doc:KV(label, value, color)
  local r = self:Take("kv", function(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(16)
    f.k = ns.Text(f, 10, C.dim, "LEFT")
    f.k:SetPoint("LEFT")
    f.v = ns.Text(f, 12, C.text, "LEFT")
    f.v:SetPoint("LEFT", 90, 0)
    return f
  end)
  r:SetWidth(self.w)
  r:SetPoint("TOPLEFT", 0, -self.y)
  r.k:SetText(label:upper())
  r.v:SetText(value)
  r.v:SetTextColor(unpack(color or C.text))
  self.y = self.y + 18
end

-- A clickable row (missions offered in a gossip / greeting window).
function Doc:Action(label, sub, color, onClick)
  local b = self:Take("action", function(p)
    local f = CreateFrame("Button", nil, p)
    f:SetHeight(26)
    ns.Box(f, { 0.05, 0.07, 0.09, 0.9 }, C.line)
    f.mark = f:CreateTexture(nil, "ARTWORK")
    f.mark:SetPoint("TOPLEFT", 1, -1)
    f.mark:SetPoint("BOTTOMLEFT", 1, 1)
    f.mark:SetWidth(2)
    f.text = ns.Text(f, 12, C.title, "LEFT")
    f.text:SetPoint("LEFT", 10, 0)
    f.sub = ns.Text(f, 10, C.dim, "RIGHT")
    f.sub:SetPoint("RIGHT", -8, 0)
    f.text:SetPoint("RIGHT", f.sub, "LEFT", -6, 0)
    f:SetScript("OnEnter", function(s) ns.SetBoxBorder(s, C.accent) end)
    f:SetScript("OnLeave", function(s) ns.SetBoxBorder(s, C.line) end)
    f:SetScript("OnClick", function(s) if s.fn then ns.Safe("mission select", s.fn)() end end)
    return f
  end)
  b:SetWidth(self.w - 10)
  b:SetPoint("TOPLEFT", 0, -self.y)
  b.mark:SetColorTexture(unpack(color or C.accent))
  b.text:SetText(label)
  b.sub:SetText((sub or ""):upper())
  b.fn = onClick
  self.y = self.y + 30
end

local function MakeCell(p)
  local c = CreateFrame("Button", nil, p)
  c:SetHeight(36)
  ns.Box(c, { 0.04, 0.06, 0.07, 0.9 }, C.line)
  c.iconFrame = CreateFrame("Frame", nil, c)
  c.iconFrame:SetSize(32, 32)
  c.iconFrame:SetPoint("LEFT", 2, 0)
  ns.Box(c.iconFrame, C.black, C.border)
  c.icon = c.iconFrame:CreateTexture(nil, "ARTWORK")
  c.icon:SetPoint("TOPLEFT", 1, -1)
  c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.count = ns.Text(c.iconFrame, 10, C.title, "RIGHT", "OUTLINE")
  c.count:SetPoint("BOTTOMRIGHT", -2, 2)
  c.name = MakeText(c)
  ns.SetFont(c.name, 11)
  c.name:SetJustifyV("MIDDLE")
  c.name:SetPoint("LEFT", c.iconFrame, "RIGHT", 6, 0)
  c.name:SetPoint("RIGHT", -4, 0)
  c.name:SetHeight(32)
  c:SetScript("OnEnter", function(s)
    if not s.item or not s.item.tip then return end
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    pcall(s.item.tip, GameTooltip)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  c:SetScript("OnClick", function(s)
    local it = s.item
    if not it then return end
    if IsModifiedClick and IsModifiedClick() and it.link and HandleModifiedItemClick then
      local link = it.link()
      if link then HandleModifiedItemClick(link) end
      return
    end
    if it.choice and s.onChoose then s.onChoose(it.index) end
  end)
  return c
end

function Doc:Items(list, onChoose, chosen)
  local cw = math.floor((self.w - 10) / 2)
  for i, it in ipairs(list) do
    local c = self:Take("cell", MakeCell)
    c:SetWidth(cw - 4)
    c:SetPoint("TOPLEFT", ((i - 1) % 2) * cw, -(self.y + math.floor((i - 1) / 2) * 40))
    c.item, c.onChoose = it, onChoose
    c.icon:SetTexture(it.icon or 134400)
    if it.usable then c.icon:SetVertexColor(1, 1, 1) else c.icon:SetVertexColor(0.9, 0.2, 0.2) end
    c.count:SetText((it.count or 0) > 1 and it.count or "")
    c.name:SetText(it.name or "")
    c.name:SetTextColor(QualityRGB(it.quality))
    local sel = it.choice and chosen == it.index
    ns.SetBoxBorder(c, sel and C.accent or C.line)
    ns.SetBoxBorder(c.iconFrame, sel and C.accent or C.border)
  end
  self.y = self.y + math.ceil(#list / 2) * 40 + 2
end

function Doc:Rewards(r, onChoose, chosen)
  local any = #r.items > 0 or #r.choices > 0 or r.xp > 0 or r.money > 0
  if not any then return end
  self:Header("Rewards")
  if r.money > 0 then self:KV("Payment", Coins(r.money) or "", C.title) end
  if r.xp > 0 then self:KV("Experience", Big(r.xp) .. " XP", C.accent) end
  if #r.items > 0 then
    self.y = self.y + 2
    self:Items(r.items)
  end
  if #r.choices > 0 then
    self:Header(#r.choices > 1 and (onChoose and "Choose one reward" or "One of these") or "Bonus")
    self:Items(r.choices, onChoose, chosen)
  end
end

-- Mission body shared by the agent panel and the journal.
local function RenderBody(doc, m)
  if m.text then
    doc:Header("Briefing")
    doc:Text(m.text)
  end
  if m.objective then
    doc:Header("Objective")
    doc:Text(m.objective, { color = C.title })
  end
  if m.objectives and #m.objectives > 0 then
    doc:Header("Objectives")
    for _, o in ipairs(m.objectives) do doc:Bullet(o) end
  end
  if m.required and #m.required > 0 then
    doc:Header("Required items")
    doc:Items(m.required)
  end
  if m.tip then
    doc:Header("Agent's note")
    doc:Text(m.tip, { color = C.cap or C.neutral })
  end
end

-- Agent conversation --------------------------------------------------------------

local cfg
local A -- agent panel
local state = { choice = 0 }

local function QuestMode()
  if Shown(QuestFrame) then
    if Shown(QuestFrameDetailPanel) then return "detail" end
    if Shown(QuestFrameProgressPanel) then return "progress" end
    if Shown(QuestFrameRewardPanel) then return "reward" end
    if Shown(QuestFrameGreetingPanel) then return "greeting" end
    return nil
  end
  if Shown(GossipFrame) and C_GossipInfo then
    local n = Num(Call(C_GossipInfo.GetNumAvailableQuests)) + Num(Call(C_GossipInfo.GetNumActiveQuests))
    if n > 0 then return "gossip" end
  end
end

local function Fade(on)
  if not QuestFrame then return end
  if on then
    QuestFrame:SetAlpha(0)
    A.faded = true
  elseif A.faded then
    QuestFrame:SetAlpha(1)
    A.faded = nil
  end
end

local function CloseDialog()
  if state.mode == "gossip" then
    if C_GossipInfo and C_GossipInfo.CloseGossip then C_GossipInfo.CloseGossip() end
  elseif Shown(QuestFrame) and HideUIPanel then
    HideUIPanel(QuestFrame) -- what Blizzard's Decline / Goodbye buttons do
  elseif CloseQuest then
    CloseQuest()
  end
end

local function Accept()
  if QuestFlagsPVP and QuestFlagsPVP() and StaticPopup_Show then
    StaticPopup_Show("CONFIRM_ACCEPT_PVP_QUEST")
  elseif QuestFrame and QuestFrame.autoQuest and AcknowledgeAutoAcceptQuest then
    AcknowledgeAutoAcceptQuest()
  else
    AcceptQuest()
  end
end

local Refresh

local function Complete()
  if state.mode == "progress" then
    CompleteQuest()
    return
  end
  local n = Num(Call(GetNumQuestChoices))
  if n == 1 then state.choice = 1 end
  if n > 1 and state.choice == 0 then
    if QuestChooseRewardError then QuestChooseRewardError()
    elseif UIErrorsFrame then UIErrorsFrame:AddMessage("Choose a reward first.", 1, 0.3, 0.3) end
    return
  end
  local cost = Num(Call(GetQuestMoneyToGet))
  if cost > 0 and not state.confirm then
    -- Quests that take money: the second click confirms.
    state.confirm = true
    A.primary:SetLabel("Confirm  " .. (Coins(cost) or ""))
    return
  end
  GetQuestReward(state.choice)
end

local function BuildAgent()
  local W, H = 380, 520
  local f = ns.CreatePanel("EveUIAgent", ns.root, "Agent conversation", W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:Hide()
  A = f
  CloseX(f, function() CloseDialog() end)

  local top = ns.HEADER + 10
  local pf = CreateFrame("Frame", nil, f)
  pf:SetSize(66, 66)
  pf:SetPoint("TOPLEFT", 10, -top)
  ns.Box(pf, C.black, C.border)
  f.portrait = pf:CreateTexture(nil, "ARTWORK")
  f.portrait:SetPoint("TOPLEFT", 1, -1)
  f.portrait:SetPoint("BOTTOMRIGHT", -1, 1)
  local mark = pf:CreateTexture(nil, "OVERLAY")
  mark:SetColorTexture(unpack(C.accent))
  mark:SetPoint("BOTTOMLEFT", 1, 1)
  mark:SetPoint("BOTTOMRIGHT", -1, 1)
  mark:SetHeight(2)

  f.name = ns.Text(f, 15, C.title, "LEFT")
  f.name:SetFont(ns.FONT_BOLD, 15, "")
  f.name:SetPoint("TOPLEFT", pf, "TOPRIGHT", 10, -2)
  f.name:SetPoint("RIGHT", -10, 0)
  f.corp = ns.Text(f, 11, C.accent, "LEFT")
  f.corp:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
  f.corp:SetPoint("RIGHT", -10, 0)
  f.loc = ns.Text(f, 11, C.dim, "LEFT")
  f.loc:SetPoint("TOPLEFT", f.corp, "BOTTOMLEFT", 0, -4)
  f.loc:SetPoint("RIGHT", -10, 0)
  f.kind = ns.Text(f, 10, C.dim, "LEFT")
  f.kind:SetFont(ns.FONT_BOLD, 10, "")
  f.kind:SetPoint("TOPLEFT", f.loc, "BOTTOMLEFT", 0, -6)

  local bodyTop = top + 66 + 10
  HLine(f, bodyTop - 5)
  local scroll, child = MakeScroll(f, W - 26)
  scroll:SetPoint("TOPLEFT", 12, -bodyTop)
  scroll:SetPoint("BOTTOMRIGHT", -6, 44)
  f.doc = NewDoc(scroll, child, W - 26)

  local foot = f:CreateTexture(nil, "ARTWORK")
  foot:SetColorTexture(unpack(C.line))
  foot:SetHeight(1)
  foot:SetPoint("BOTTOMLEFT", 1, 38)
  foot:SetPoint("BOTTOMRIGHT", -1, 38)
  f.primary = Btn(f, "Accept", 150, function()
    if state.mode == "detail" then Accept() else Complete() end
  end, true)
  f.primary:SetPoint("BOTTOMRIGHT", -10, 8)
  f.secondary = Btn(f, "Decline", 110, function() CloseDialog() end)
  f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -8, 0)
  f.journal = Btn(f, "Journal", 80, function() if ns.ToggleMissions then ns.ToggleMissions() end end)
  f.journal:SetPoint("BOTTOMLEFT", 10, 8)

  f:SetScript("OnHide", function() Fade(false) end)
end

local KIND = {
  detail = "MISSION OFFER", progress = "MISSION IN PROGRESS", reward = "MISSION COMPLETE",
  greeting = "AVAILABLE MISSIONS", gossip = "AVAILABLE MISSIONS",
}

local function MissionList(doc, mode)
  local any
  local function Row(title, sub, color, fn)
    any = true
    doc:Action(title or "?", sub, color, fn)
  end
  if mode == "gossip" then
    for _, q in ipairs(Call(C_GossipInfo.GetActiveQuests) or {}) do
      local id = Plain(q.questID)
      local done = Plain(q.isComplete) == true
      Row(Str(q.title), done and "Report" or "In progress", done and C.heal or C.dim,
        function() C_GossipInfo.SelectActiveQuest(id) end)
    end
    for _, q in ipairs(Call(C_GossipInfo.GetAvailableQuests) or {}) do
      local id, lvl = Plain(q.questID), Num(q.questLevel)
      Row(Str(q.title), lvl > 0 and ("Level " .. lvl) or "New", C.accent,
        function() C_GossipInfo.SelectAvailableQuest(id) end)
    end
  else
    for i = 1, Num(Call(GetNumActiveQuests)) do
      local title, done = Call(GetActiveTitle, i)
      done = Plain(done) and true or false
      Row(Str(title), done and "Report" or "In progress", done and C.heal or C.dim,
        function() SelectActiveQuest(i) end)
    end
    for i = 1, Num(Call(GetNumAvailableQuests)) do
      local title = Call(GetAvailableTitle, i)
      local lvl = Num(Call(GetAvailableLevel, i))
      Row(Str(title), lvl > 0 and ("Level " .. lvl) or "New", C.accent,
        function() SelectAvailableQuest(i) end)
    end
  end
  return any
end

local function Dock(mode)
  local host = mode == "gossip" and GossipFrame or QuestFrame
  local s = A:GetEffectiveScale()
  local hw = host:GetWidth() * host:GetEffectiveScale() / s
  local hh = host:GetHeight() * host:GetEffectiveScale() / s
  A:ClearAllPoints()
  if cfg.replace and mode ~= "gossip" then
    A:SetSize(math.max(380, hw), math.max(420, hh))
    A:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    Fade(true)
  else
    A:SetSize(380, math.max(420, hh))
    A:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, 0)
    Fade(false)
  end
  -- The doc width follows the panel width.
  A.doc.w = A:GetWidth() - 26
  A.doc.f:SetWidth(A.doc.w)
end

function Refresh()
  if not A then return end
  local mode = cfg.agent and QuestMode() or nil
  if not mode then
    if A:IsShown() then A:Hide() end
    state.mode, state.qid = nil, nil
    return
  end
  local unit = (mode == "gossip" or not UnitExists("questnpc")) and "npc" or "questnpc"
  local qid = (mode == "detail" or mode == "progress" or mode == "reward") and Plain(Call(GetQuestID)) or nil
  if qid == 0 then qid = nil end
  local same = qid == state.qid and mode == state.mode
  if not same then state.choice, state.confirm = 0, nil end
  state.mode, state.qid = mode, qid
  local b = Brief(qid)

  -- Agent identity.
  local name, corp
  local agent = b and Str(b.agent)
  if agent then
    name, corp = agent:match("^(.-),%s*(.+)$")
    name = name or agent
  end
  name = name or Str(UnitName(unit)) or "Agent"
  corp = corp or NpcTitle(unit) or Str(Call(UnitFactionGroup, unit)) or "Independent agent"
  A.name:SetText(name)
  A.corp:SetText(corp:upper())
  A.loc:SetText(Location())
  A.kind:SetText(KIND[mode] or "")
  A.kind:SetTextColor(unpack(mode == "reward" and C.heal or C.accent))
  if UnitExists(unit) and SetPortraitTexture then
    SetPortraitTexture(A.portrait, unit)
    A.portrait:SetTexCoord(0, 1, 0, 1)
  else
    A.portrait:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
  end

  Dock(mode)
  local doc = A.doc
  doc:Clear()
  A.primary:Show()
  A.secondary:SetLabel("Close")

  if mode == "gossip" or mode == "greeting" then
    local text = mode == "gossip" and Tidy(Call(C_GossipInfo.GetText)) or Tidy(Call(GetGreetingText))
    if text then doc:Text(text) end
    doc:Header("Missions")
    MissionList(doc, mode)
    A.primary:Hide()
  else
    local title = Str(Call(GetTitleText)) or (qid and Str(Call(C_QuestLog.GetTitleForQuestID, qid))) or "Mission"
    doc:Text(title, { size = 16, bold = true, color = C.title, gap = 4 })
    local m = { objective = b and Str(b.objective), tip = b and Str(b.tip) }
    if mode == "detail" then
      m.text = (b and Str(b.text)) or Tidy(Call(GetQuestText))
      m.objectives = LogObjectives(qid)
      if #m.objectives == 0 then m.objectives = SplitObjectives(Call(GetObjectiveText)) end
      RenderBody(doc, m)
      doc:Rewards(OfferRewards())
      A.primary:SetLabel("Accept")
      A.primary:SetOn(true)
      A.secondary:SetLabel("Decline")
    elseif mode == "progress" then
      local progress = Tidy(Call(GetProgressText))
      if progress then doc:Header("Agent"); doc:Text(progress) end
      m.objectives = LogObjectives(qid)
      m.required = RequiredItems()
      RenderBody(doc, m)
      A.primary:SetLabel("Complete")
      A.primary:SetOn(Call(IsQuestCompletable) and true or false)
    else -- reward
      local text = Tidy(Call(GetRewardText))
      if text then doc:Header("Agent"); doc:Text(text) end
      if m.tip then doc:Header("Agent's note"); doc:Text(m.tip, { color = C.cap or C.neutral }) end
      doc:Rewards(OfferRewards(), function(i)
        state.choice, state.confirm = i, nil
        Refresh()
      end, state.choice)
      A.primary:SetLabel(state.confirm and A.primary.text:GetText() or "Complete mission")
      A.primary:SetOn(true)
    end
  end
  doc:Finish(same)
  if not A:IsShown() then A:Show() end
end

-- Journal ---------------------------------------------------------------------------

local J

local function ReadLog()
  local out = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
  local zone
  for i = 1, Num(Call(C_QuestLog.GetNumQuestLogEntries)) do
    local info = Call(C_QuestLog.GetInfo, i)
    if type(info) == "table" then
      local title = Str(info.title)
      if Plain(info.isHeader) then
        zone = title
        out[#out + 1] = { header = true, title = title or "" }
      elseif title and not Plain(info.isHidden) then
        local qid = Plain(info.questID)
        local objs = LogObjectives(qid)
        local failed = Call(C_QuestLog.IsFailed, qid) and true or false
        local complete = not failed and (Call(C_QuestLog.IsComplete, qid) or Call(C_QuestLog.ReadyForTurnIn, qid)) and true or false
        out[#out + 1] = { title = title, qid = qid, index = Plain(info.questLogIndex) or i,
          level = Num(info.level), zone = zone, objectives = objs, failed = failed, complete = complete,
          pct = Progress(objs, complete) }
      end
    end
  end
  return out
end

local function LevelColor(level)
  local c = level > 0 and Call(GetQuestDifficultyColor, level)
  if type(c) == "table" and c.r then return { c.r, c.g, c.b, 1 } end
  return C.text
end

local function StatusText(e)
  if e.failed then return "FAILED", C.hostile end
  if e.complete then return "COMPLETE", C.heal end
  return math.floor(e.pct * 100 + 0.5) .. "%", C.accent
end

local function RenderEntry()
  local e
  for _, x in ipairs(J.entries) do if not x.header and x.qid == J.sel then e = x end end
  local doc = J.doc
  doc:Clear()
  if not e then
    J.qtitle:SetText("No missions")
    J.meta:SetText("")
    J.bar:SetValue(0)
    J.pct:SetText("")
    J.track:Hide()
    doc:Text("Your journal is empty. Talk to agents to take on missions.", { color = C.dim })
    doc:Finish()
    return
  end
  local b = Brief(e.qid)
  local status, scol = StatusText(e)
  J.qtitle:SetText(e.title)
  J.meta:SetText(("LEVEL %d  ·  %s"):format(e.level, (e.zone or "Unknown"):upper()))
  J.bar:SetValue(e.pct)
  ns.SetBarColor(J.bar, scol)
  J.pct:SetText(status)
  J.pct:SetTextColor(unpack(scol))

  local desc, objText = Call(GetQuestLogQuestText, e.index)
  local m = {
    text = (b and Str(b.text)) or Tidy(desc),
    objective = (b and Str(b.objective)) or Tidy(objText),
    tip = b and Str(b.tip),
    objectives = e.objectives,
  }
  if b and Str(b.agent) then
    doc:Header("Agent")
    doc:Text(b.agent, { color = C.accent })
  end
  RenderBody(doc, m)
  doc:Rewards(LogRewards(e.qid))
  doc:Finish(J.lastSel == e.qid)
  J.lastSel = e.qid

  local watched = C_QuestLog.GetQuestWatchType and Call(C_QuestLog.GetQuestWatchType, e.qid) ~= nil
  J.track:SetLabel(watched and "Untrack" or "Track")
  J.track:Show()
end

local ROW_H = 20

local function MakeRow(p)
  local r = CreateFrame("Button", nil, p)
  r:SetHeight(ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(1, 1, 1, 0)
  r.sel = r:CreateTexture(nil, "ARTWORK")
  r.sel:SetColorTexture(unpack(C.accent))
  r.sel:SetPoint("TOPLEFT")
  r.sel:SetPoint("BOTTOMLEFT")
  r.sel:SetWidth(2)
  r.lvl = ns.Text(r, 11, C.text, "CENTER")
  r.lvl:SetPoint("LEFT", 4, 0)
  r.lvl:SetWidth(24)
  r.status = ns.Text(r, 10, C.accent, "RIGHT")
  r.status:SetPoint("RIGHT", -6, 0)
  r.status:SetWidth(60)
  r.title = ns.Text(r, 12, C.text, "LEFT")
  r.title:SetPoint("LEFT", 30, 0)
  r.title:SetPoint("RIGHT", r.status, "LEFT", -4, 0)
  r.head = ns.Text(r, 10, C.dim, "LEFT")
  r.head:SetFont(ns.FONT_BOLD, 10, "")
  r.head:SetPoint("LEFT", 4, -2)
  r:SetScript("OnEnter", function(s) if not s.isHeader then s.bg:SetColorTexture(1, 1, 1, 0.05) end end)
  r:SetScript("OnLeave", function(s) s.bg:SetColorTexture(1, 1, 1, s.qid == J.sel and 0.06 or 0) end)
  r:SetScript("OnClick", function(s)
    if s.isHeader or not s.qid then return end
    J.sel = s.qid
    ns.Safe("journal select", function() J.Render() end)()
  end)
  return r
end

local function RenderList()
  local rows, child = J.rows, J.listChild
  for _, r in ipairs(rows) do r:Hide() end
  local y, n, quests = 0, 0, 0
  for _, e in ipairs(J.entries) do
    n = n + 1
    local r = rows[n] or MakeRow(child)
    rows[n] = r
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetPoint("RIGHT", child, "RIGHT", -6, 0)
    r.isHeader, r.qid = e.header, e.qid
    r.lvl:SetShown(not e.header)
    r.title:SetShown(not e.header)
    r.status:SetShown(not e.header)
    r.head:SetShown(e.header and true or false)
    if e.header then
      r.head:SetText((e.title or ""):upper())
      r.sel:Hide()
      r.bg:SetColorTexture(1, 1, 1, 0)
      y = y + (n > 1 and 4 or 0)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      r:SetPoint("RIGHT", child, "RIGHT", -6, 0)
    else
      quests = quests + 1
      r.lvl:SetText(e.level > 0 and e.level or "")
      r.lvl:SetTextColor(unpack(LevelColor(e.level)))
      r.title:SetText(e.title)
      local s, c = StatusText(e)
      r.status:SetText(s)
      r.status:SetTextColor(unpack(c))
      local on = e.qid == J.sel
      r.sel:SetShown(on)
      r.bg:SetColorTexture(1, 1, 1, on and 0.06 or 0)
      r.title:SetTextColor(unpack(on and C.title or C.text))
    end
    r:Show()
    y = y + ROW_H
  end
  child:SetHeight(math.max(1, y))
  local max = Num(Call(C_QuestLog.GetMaxNumQuestsCanAccept))
  if max <= 0 then max = 25 end
  J.count:SetText(("%d / %d"):format(quests, max))
  C_Timer.After(0, J.listScroll.Thumb)
end

local function BuildJournal()
  local W, H, LW = 720, 470, 270
  local f = ns.CreatePanel("EveUIMissions", ns.root, "Journal", W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:Hide()
  J = f
  tinsert(UISpecialFrames, "EveUIMissions")
  ns.Mover(f, { key = "missions", label = "Mission journal", point = "CENTER", x = 0, y = 60 })
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); ns.SavePos(s) end)
  CloseX(f, function() f:Hide() end)

  local sub = ns.Text(f, 11, C.dim, "LEFT")
  sub:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
  sub:SetText("AGENT MISSIONS")
  f.count = ns.Text(f, 11, C.accent, "RIGHT")
  f.count:SetPoint("TOPRIGHT", -30, -6)

  local top = ns.HEADER + 8
  local ls, lc = MakeScroll(f, LW)
  ls:SetPoint("TOPLEFT", 8, -top)
  ls:SetPoint("BOTTOMLEFT", 8, 8)
  ls:SetWidth(LW)
  f.listScroll, f.listChild, f.rows = ls, lc, {}

  local div = f:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(unpack(C.line))
  div:SetWidth(1)
  div:SetPoint("TOPLEFT", LW + 14, -(ns.HEADER + 1))
  div:SetPoint("BOTTOMLEFT", LW + 14, 1)

  local x = LW + 26
  local RW = W - x - 8
  f.qtitle = ns.Text(f, 16, C.title, "LEFT")
  f.qtitle:SetFont(ns.FONT_BOLD, 16, "")
  f.qtitle:SetPoint("TOPLEFT", x, -(top + 2))
  f.qtitle:SetPoint("RIGHT", -12, 0)
  f.meta = ns.Text(f, 10, C.dim, "LEFT")
  f.meta:SetPoint("TOPLEFT", f.qtitle, "BOTTOMLEFT", 0, -5)
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture(ns.WHITE)
  bar:SetMinMaxValues(0, 1)
  bar:SetHeight(4)
  bar:SetPoint("TOPLEFT", x, -(top + 44))
  bar:SetPoint("RIGHT", -80, 0)
  local bbg = bar:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints()
  bbg:SetColorTexture(unpack(C.off))
  f.bar = bar
  f.pct = ns.Text(f, 10, C.accent, "RIGHT")
  f.pct:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  f.pct:SetPoint("TOP", bar, "TOP", 0, 4)

  local bodyTop = top + 56
  HLine(f, bodyTop - 4, x - 10, -1)
  local scroll, child = MakeScroll(f, RW - 6)
  scroll:SetPoint("TOPLEFT", x, -bodyTop)
  scroll:SetPoint("BOTTOMRIGHT", -6, 40)
  f.doc = NewDoc(scroll, child, RW - 6)

  f.track = Btn(f, "Track", 100, function()
    local q = J.sel
    if not q then return end
    if Call(C_QuestLog.GetQuestWatchType, q) ~= nil then
      Call(C_QuestLog.RemoveQuestWatch, q)
    else
      Call(C_QuestLog.AddQuestWatch, q)
    end
    C_Timer.After(0.1, function() if J:IsShown() then J.Render() end end)
  end)
  f.track:SetPoint("BOTTOMRIGHT", -10, 8)

  function f.Render()
    J.entries = ReadLog()
    local found, first
    for _, e in ipairs(J.entries) do
      if not e.header then
        first = first or e.qid
        if e.qid == J.sel then found = true end
      end
    end
    if not found then J.sel = first end
    RenderList()
    RenderEntry()
  end
  f:SetScript("OnShow", function() ns.Safe("journal", f.Render)() end)
end

function ns.ToggleMissions(arg)
  if not cfg then ns.Print("missions module is off (settings).") return end
  arg = arg and arg:lower() or ""
  if arg == "agent" then
    cfg.agent = not cfg.agent
    ns.Print("agent conversation " .. (cfg.agent and "on" or "off"))
    Refresh()
    return
  elseif arg == "replace" then
    cfg.replace = not cfg.replace
    ns.Print("agent panel " .. (cfg.replace and "covers the quest window" or "docks beside the quest window"))
    Refresh()
    return
  end
  if not J then BuildJournal() end
  J:SetShown(not J:IsShown())
end

ns.RegisterModule(function()
  EveUIDB.missions = EveUIDB.missions or {}
  cfg = EveUIDB.missions
  if cfg.agent == nil then cfg.agent = true end
  BuildAgent()

  local pending
  local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = nil
      ns.Safe("agent", Refresh)()
    end)
  end
  local dirty
  local function QueueJournal()
    if not (J and J:IsShown()) or dirty then return end
    dirty = true
    C_Timer.After(0.3, function()
      dirty = nil
      if J:IsShown() then ns.Safe("journal", J.Render)() end
    end)
  end

  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "QUEST_FINISHED",
    "QUEST_ITEM_UPDATE", "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_LOG_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, event)
    if event == "QUEST_LOG_UPDATE" then
      QueueJournal()
      if A:IsShown() and state.mode == "progress" then Queue() end
      return
    end
    Queue()
  end)
  for _, host in ipairs({ QuestFrame, GossipFrame, QuestFrameDetailPanel, QuestFrameProgressPanel,
    QuestFrameRewardPanel, QuestFrameGreetingPanel }) do
    if host and host.HookScript then
      host:HookScript("OnShow", Queue)
      host:HookScript("OnHide", Queue)
    end
  end
end, "missions")
