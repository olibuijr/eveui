-- Scrolling combat text, EVE combat-log style: incoming hits and heals scroll
-- up on the left of the HUD, damage on your target on the right. Driven by
-- UNIT_COMBAT, whose amounts may be secret; the text widgets display them.
local ADDON, ns = ...
local C = ns.C

local POOL, RISE, LIFE = 40, 150, 1.8

local MISS = { MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", ABSORB = "Absorb",
  IMMUNE = "Immune", RESIST = "Resist", EVADE = "Evade", DEFLECT = "Deflect", REFLECT = "Reflect" }

ns.RegisterModule(function()
  local hud = ns.hud
  local lanes = {}
  -- One movable anchor spans both lanes (incoming left, outgoing right).
  local anchor = CreateFrame("Frame", "EveUICombatTextAnchor", ns.root)
  anchor:SetSize(2 * (150 + 160), RISE + 30)
  ns.Mover(anchor, { key = "sct", label = "Combat text", point = "BOTTOM", rel = hud, relPoint = "CENTER", x = 0, y = 30 })
  for _, side in ipairs({ "left", "right" }) do
    local l = CreateFrame("Frame", nil, ns.root)
    l:SetSize(160, RISE + 30)
    if side == "left" then l:SetPoint("BOTTOMRIGHT", anchor, "BOTTOM", -150, 0)
    else l:SetPoint("BOTTOMLEFT", anchor, "BOTTOM", 150, 0) end
    l.side, l.next = side, 0
    lanes[side] = l
  end

  local free = {}
  for i = 1, POOL do
    local fr = CreateFrame("Frame", nil, ns.root)
    fr:SetSize(160, 24)
    fr.text = ns.Text(fr, 16, C.text, "CENTER")
    fr.text:SetAllPoints()
    local ag = fr:CreateAnimationGroup()
    local move = ag:CreateAnimation("Translation")
    move:SetOffset(0, RISE)
    move:SetDuration(LIFE)
    move:SetSmoothing("OUT")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(LIFE * 0.6)
    fade:SetDuration(LIFE * 0.4)
    ag:SetScript("OnFinished", function() fr:Hide(); free[#free + 1] = fr end)
    fr.ag = ag
    fr:Hide()
    free[#free + 1] = fr
  end

  -- Show one message. fmt/arg go to SetFormattedText so secret amounts work.
  local function Show(side, color, size, fmt, arg)
    local fr = table.remove(free)
    if not fr then return end
    local lane = lanes[side]
    lane.next = (lane.next + 1) % 3
    fr:ClearAllPoints()
    fr:SetPoint("BOTTOM", lane, "BOTTOM", (lane.next - 1) * 28, 0)
    ns.SetFont(fr.text, size, "OUTLINE")
    fr.text:SetTextColor(color[1], color[2], color[3])
    if arg ~= nil then fr.text:SetFormattedText(fmt, arg) else fr.text:SetText(fmt) end
    fr:SetAlpha(1)
    fr:Show()
    fr.ag:Stop()
    fr.ag:Play()
  end

  -- Messages that arrive together are spaced out so they never overlap.
  local GAP = 0.2
  local function Push(side, color, size, fmt, arg)
    local lane = lanes[side]
    lane.queue = lane.queue or {}
    if #lane.queue >= 12 then return end
    lane.queue[#lane.queue + 1] = { color, size, fmt, arg }
  end
  for side, lane in pairs(lanes) do
    lane.wait = 0
    lane:SetScript("OnUpdate", function(self, el)
      self.wait = self.wait - el
      local q = self.queue
      if self.wait <= 0 and q and q[1] then
        local m = table.remove(q, 1)
        Show(side, m[1], m[2], m[3], m[4])
        self.wait = GAP
      end
    end)
  end

  local function OnCombat(unit, action, flag, amount)
    local side = unit == "player" and "left" or "right"
    action, flag = ns.Plain(action), ns.Plain(flag)
    local crit = flag == "CRITICAL" or flag == "CRUSHING"
    local size = crit and 22 or 16
    if action == "HEAL" then
      Push(side, C.heal, size, crit and "+%s!" or "+%s", AbbreviateNumbers(amount))
    elseif action and MISS[action] then
      Push(side, C.dim, 14, MISS[action])
    elseif action == "WOUND" or action == nil then
      local color = side == "left" and C.hostile or (crit and C.cap or C.title)
      Push(side, color, size, crit and "%s!" or "%s", AbbreviateNumbers(amount))
    end
  end

  local ev = CreateFrame("Frame")
  ev:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", ns.Safe("sct", function(_, event, unit, action, flag, amount)
    if event == "UNIT_COMBAT" then
      if unit == "target" and ns.Plain(UnitIsUnit("target", "player")) then return end
      OnCombat(unit, action, flag, amount)
    elseif event == "PLAYER_REGEN_DISABLED" then
      Push("left", C.hostile, 14, "+ COMBAT")
    else
      Push("left", C.dim, 14, "- COMBAT")
    end
  end))

  ns.TestSCT = function()
    OnCombat("player", "WOUND", nil, 412)
    OnCombat("player", "HEAL", "CRITICAL", 980)
    OnCombat("target", "WOUND", "CRITICAL", 1337)
    OnCombat("target", "WOUND", nil, 77)
    OnCombat("target", "DODGE", nil, 0)
  end
end, "sct")
