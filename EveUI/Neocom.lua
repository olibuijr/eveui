-- Neocom: a dark strip down the left edge with the game's menus as icons
-- and the clock at the bottom. Menu buttons click Blizzard's micro buttons
-- through secure "click" actions, so they also work in combat.
local ADDON, ns = ...
local C = ns.C

local ITEMS = {
  { "CharacterMicroButton", "Character", "Interface\\Icons\\INV_Chest_Chain_05" },
  { "SpellbookMicroButton", "Spellbook", "Interface\\Icons\\INV_Misc_Book_09" },
  { "TalentMicroButton", "Talents", "Interface\\Icons\\Ability_Marksmanship" },
  { "PlayerSpellsMicroButton", "Spells & Talents", "Interface\\Icons\\INV_Misc_Book_09", "SpellbookMicroButton" },
  { "ProfessionMicroButton", "Professions", "Interface\\Icons\\Trade_BlackSmithing" },
  { "QuestLogMicroButton", "Quest log", "Interface\\Icons\\INV_Misc_Note_01" },
  { "AchievementMicroButton", "Achievements", "Interface\\Icons\\Achievement_Quests_Completed_08" },
  { "GuildMicroButton", "Guild & Communities", "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
  { "LFDMicroButton", "Group finder", "Interface\\Icons\\INV_Misc_GroupNeedMore" },
  { "CollectionsMicroButton", "Collections", "Interface\\Icons\\MountJournalPortrait" },
  { "EJMicroButton", "Adventure guide", "Interface\\Icons\\INV_Misc_Book_17" },
  { "StoreMicroButton", "Shop", "Interface\\Icons\\INV_Misc_Coin_02" },
  { "MainMenuMicroButton", "Game menu", "Interface\\Icons\\INV_Misc_Gear_01" },
}

local WIDTH, SIZE, STEP = 44, 28, 38

local function Decorate(b, label, icon)
  local ring = ns.Box(b, { 0, 0, 0, 0.5 }, C.line)
  local ic = b:CreateTexture(nil, "ARTWORK")
  ic:SetPoint("TOPLEFT", 2, -2)
  ic:SetPoint("BOTTOMRIGHT", -2, 2)
  ic:SetTexture(icon)
  ic:SetTexCoord(0.1, 0.9, 0.1, 0.9)
  -- Full colour, a little dimmed at rest; full brightness on hover.
  local function Rest() ic:SetVertexColor(0.82, 0.82, 0.82); ic:SetAlpha(0.95) end
  Rest()
  local mark = b:CreateTexture(nil, "OVERLAY")
  mark:SetColorTexture(unpack(C.accent))
  mark:SetPoint("TOPRIGHT", b, "TOPLEFT", -6, 0)
  mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -6, 0)
  mark:SetWidth(2)
  mark:Hide()
  b:HookScript("OnEnter", function(self)
    ic:SetVertexColor(1, 1, 1); ic:SetAlpha(1); mark:Show()
    ns.SetBoxBorder(self, C.accent)
    if ns.NeocomSide() == "right" then GameTooltip:SetOwner(self, "ANCHOR_LEFT", -6, 0)
    else GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 6, 0) end
    GameTooltip:SetText(label, C.title[1], C.title[2], C.title[3])
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function(self)
    Rest(); mark:Hide()
    ns.SetBoxBorder(self, C.line)
    GameTooltip:Hide()
  end)
end

-- Which screen edge the strip sits on (per character).
function ns.NeocomSide()
  return (ns.layout and ns.layout.neocom) or "left"
end

ns.RegisterModule(function()
  if not EveUIDB.neocom then return end

  local bar = CreateFrame("Frame", "EveUINeocom", ns.root)
  bar:SetWidth(WIDTH)
  bar:SetFrameStrata("LOW")
  ns.Box(bar, { 0.02, 0.03, 0.04, 0.9 }, false)
  local edge = bar:CreateTexture(nil, "BORDER")
  edge:SetColorTexture(unpack(C.border))
  edge:SetWidth(1)

  -- Full height on the left or right edge. Dragging it while unlocked
  -- snaps it to the edge nearest the cursor on release.
  local function Place()
    local P = ns.NeocomSide() == "right" and "RIGHT" or "LEFT"
    local Q = P == "RIGHT" and "LEFT" or "RIGHT"
    bar:ClearAllPoints()
    bar:SetPoint("TOP" .. P, UIParent, "TOP" .. P, 0, 0)
    bar:SetPoint("BOTTOM" .. P, UIParent, "BOTTOM" .. P, 0, 0)
    edge:ClearAllPoints()
    edge:SetPoint("TOP" .. Q)
    edge:SetPoint("BOTTOM" .. Q)
  end
  ns.Mover(bar, { key = "neocom", label = "Neocom", apply = Place, drag = {
    start = function() end,
    stop = function()
      local x = GetCursorPosition() / UIParent:GetEffectiveScale()
      ns.Layout().neocom = x > UIParent:GetWidth() / 2 and "right" or nil
      for _, m in ipairs(ns.movers) do ns.Safe("place " .. m.eveKey, ns.ApplyPos)(m) end
      ns.RunLayout()
    end } })

  local logo = bar:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ns.WHITE)
  logo:SetVertexColor(unpack(C.accent))
  logo:SetSize(12, 12)
  logo:SetPoint("TOP", 0, -14)
  logo:SetRotation(math.pi / 4)
  local logoLine = bar:CreateTexture(nil, "ARTWORK")
  logoLine:SetColorTexture(unpack(C.line))
  logoLine:SetPoint("TOPLEFT", 8, -38)
  logoLine:SetPoint("TOPRIGHT", -8, -38)
  logoLine:SetHeight(1)

  local y = 48
  local function Plain(label, icon, onClick)
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(SIZE, SIZE)
    b:SetPoint("TOP", 0, -y)
    b:SetScript("OnClick", onClick)
    Decorate(b, label, icon)
    y = y + STEP
  end

  Plain("Inventory", "Interface\\Icons\\INV_Misc_Bag_08", function() ToggleAllBags() end)
  Plain("World map", "Interface\\Icons\\INV_Misc_Map_01", function() ToggleWorldMap() end)
  Plain("EveUI settings", "Interface\\Icons\\Trade_Engineering", function() ns.ToggleSettings() end)

  -- EveUI windows (their modules load after this one, so look them up on click).
  local WINDOWS = {
    { "starmap", "Star map", "Interface\\Icons\\INV_Misc_Map02", "ToggleStarMap" },
    { "fitting", "Fitting", "Interface\\Icons\\INV_Gizmo_02", "ToggleFitting" },
    { "skillqueue", "Skill queue", "Interface\\Icons\\INV_Misc_Book_11", "ToggleSkillQueue" },
    { "wallet", "Wallet", "Interface\\Icons\\INV_Misc_Coin_01", "ToggleWallet" },
    { "missions", "Missions", "Interface\\Icons\\INV_Misc_Note_02", "ToggleMissions" },
    { "killmail", "Killmails", "Interface\\Icons\\Ability_Rogue_FeignDeath", "ToggleKillmails" },
  }
  for _, w in ipairs(WINDOWS) do
    if ns.ModuleOn(w[1]) then
      Plain(w[2], w[3], function() if ns[w[4]] then ns[w[4]]() end end)
    end
  end

  local seen = {}
  for _, item in ipairs(ITEMS) do
    local target = _G[item[1]]
    -- Skip duplicates (Spells & Talents only when the classic pair is absent).
    if target and not (item[4] and _G[item[4]]) and not seen[item[1]] then
      seen[item[1]] = true
      local b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
      b:SetSize(SIZE, SIZE)
      b:SetPoint("TOP", 0, -y)
      b:RegisterForClicks("AnyUp", "AnyDown")
      b:SetAttribute("type", "click")
      b:SetAttribute("clickbutton", target)
      Decorate(b, item[2], item[3])
      y = y + STEP
    end
  end

  local clock = ns.Text(bar, 13, C.title)
  clock:SetPoint("BOTTOM", 0, 12)
  local clockLabel = ns.Text(bar, 9, C.dim)
  clockLabel:SetPoint("BOTTOM", clock, "TOP", 0, 2)
  clockLabel:SetText("LOCAL")
  ns.Every(5, "clock", function() clock:SetText(date("%H:%M")) end)
end)
