-- Ship computer: short spoken alerts ("Shields low", "Target destroyed", ...)
-- plus an EVE-style notification banner, so alerts also work with sound off.
--
-- Clips in media/voice are original TTS recordings (see LICENSE.txt there).
--
-- Secret values: in combat the player's health (and sometimes power) can be
-- secret, and curves only produce more secrets, so thresholds are checked
-- only on plain values. While health is secret, "hull critical" follows the
-- game's own low-health warning (LowHealthFrame, about 35%) and "shields low"
-- stays quiet until the values are plain again.
local ADDON, ns = ...
local Plain = ns.Plain

local PATH = "Interface\\AddOns\\EveUI\\media\\voice\\"
local GAP = 1.5          -- seconds between any two alerts
local QUIET_START = 6    -- no alerts this long after a loading screen

-- key, file, banner text, level (info / warn / danger), cooldown seconds.
local LINES = {
  { "shields", "shields_low", "Shields low", "warn", 30 },
  { "hull", "hull_critical", "Hull integrity critical", "danger", 20 },
  { "caplow", "capacitor_low", "Capacitor low", "warn", 30 },
  { "capempty", "capacitor_empty", "Capacitor empty", "danger", 20 },
  { "kill", "target_destroyed", "Target destroyed", "info", 4 },
  { "warp", "warp_drive_active", "Warp drive active", "info", 20 },
  { "dock", "docking", "Docking request accepted", "info", 60 },
  { "hostile", "hostile_locking", "Hostile ship locking", "danger", 25 },
  { "interrupt", "cycle_interrupted", "Module cycle interrupted", "warn", 8 },
  { "level", "skill_training_complete", "Skill training complete", "info", 5 },
  { "quest", "mission_objective_complete", "Mission objective complete", "info", 3 },
  { "repair", "armor_damaged", "Armor damaged - repair advised", "warn", 600 },
  { "waypoint", "waypoint_reached", "Waypoint reached", "info", 3 },
}
local BY = {}
for _, l in ipairs(LINES) do
  BY[l[1]] = { key = l[1], file = l[2], text = l[3], level = l[4], cd = l[5] }
end
ns.VoiceLines = LINES

local CHANNELS = { master = "Master", sfx = "SFX", dialog = "Dialog", ambience = "Ambience", music = "Music" }

local function DB()
  EveUIDB.voice = EveUIDB.voice or {}
  local v = EveUIDB.voice
  if v.sound == nil then v.sound = true end
  if v.banner == nil then v.banner = true end
  v.channel = v.channel or "Master"
  v.lines = v.lines or {}
  return v
end

local function LineOn(key) return DB().lines[key] ~= false end

-- Banner -----------------------------------------------------------------------

local holder, banner

local function LevelColor(level)
  local C = ns.C
  if level == "danger" then return C.hostile or C.health end
  if level == "warn" then return C.cast or C.cap end
  return C.accent
end

local function BuildBanner()
  local C = ns.C
  holder = CreateFrame("Frame", "EveUIVoiceBanner", ns.root)
  holder:SetSize(360, 40)
  holder:SetFrameStrata("HIGH")

  banner = CreateFrame("Frame", nil, holder)
  banner:SetAllPoints()
  ns.Box(banner, C.panel, C.border)
  banner:Hide()

  banner.mark = banner:CreateTexture(nil, "ARTWORK")
  banner.mark:SetPoint("TOPLEFT", 1, -1)
  banner.mark:SetPoint("BOTTOMLEFT", 1, 1)
  banner.mark:SetWidth(3)

  banner.glow = banner:CreateTexture(nil, "BACKGROUND", nil, -6)
  banner.glow:SetPoint("TOPLEFT", 4, -1)
  banner.glow:SetPoint("BOTTOMRIGHT", -1, 1)
  banner.glow:SetTexture(ns.WHITE)

  banner.head = ns.Text(banner, 9, C.dim, "LEFT")
  banner.head:SetPoint("TOPLEFT", 12, -5)
  banner.head:SetText("SHIP COMPUTER")

  banner.text = ns.Text(banner, 14, C.title, "LEFT")
  banner.text:SetPoint("BOTTOMLEFT", 12, 6)
  banner.text:SetPoint("RIGHT", -10, 0)

  banner:SetScript("OnUpdate", function(self)
    if self.sticky then self:SetAlpha(1); return end
    local t = GetTime() - (self.start or 0)
    local a
    if t < 0.15 then a = t / 0.15
    elseif t < 3.2 then a = 1
    elseif t < 3.8 then a = 1 - (t - 3.2) / 0.6
    else self:Hide(); return end
    self:SetAlpha(a)
  end)

  ns.Mover(holder, {
    key = "voice", label = "Ship alerts", point = "TOP", y = -150,
    onUnlock = function(unlocked)
      banner.sticky = unlocked or nil
      if unlocked then ns.VoiceBanner("Ship computer alerts", "info") elseif banner:IsShown() then banner.start = GetTime() - 3 end
    end,
  })
end

function ns.VoiceBanner(text, level)
  if not banner then return end
  local c = LevelColor(level)
  banner.mark:SetColorTexture(c[1], c[2], c[3], 1)
  ns.Gradient(banner.glow, { c[1], c[2], c[3], 0.16 }, { c[1], c[2], c[3], 0 }, "HORIZONTAL")
  ns.SetBoxBorder(banner, { c[1], c[2], c[3], 0.55 })
  banner.text:SetTextColor(c[1], c[2], c[3], 1)
  banner.text:SetText(string.upper(text))
  banner.start = GetTime()
  banner:SetAlpha(0)
  banner:Show()
end

-- Queue and throttle -----------------------------------------------------------

local last, lastAny, queue, quietUntil = {}, 0, {}, 0
local pump

local function Play(line)
  local v = DB()
  lastAny = GetTime()
  if v.banner then ns.VoiceBanner(line.text, line.level) end
  if v.sound then ns.Call(PlaySoundFile, PATH .. line.file .. ".ogg", v.channel) end
end

pump = function()
  if #queue == 0 then return end
  local wait = lastAny + GAP - GetTime()
  if wait > 0 then C_Timer.After(wait + 0.01, pump); return end
  Play(table.remove(queue, 1))
  if #queue > 0 then C_Timer.After(GAP + 0.01, pump) end
end

-- force: skip toggles, cooldowns and the start-up quiet time (tests).
local function Alert(key, force)
  local line = BY[key]
  if not line then return end
  local now = GetTime()
  if not force then
    if DB().off or not LineOn(key) or now < quietUntil then return end
    if last[key] and now - last[key] < line.cd then return end
  end
  last[key] = now
  for _, q in ipairs(queue) do if q == line then return end end
  if #queue >= 3 then table.remove(queue) end
  -- Danger lines jump the queue.
  if line.level == "danger" then table.insert(queue, 1, line) else queue[#queue + 1] = line end
  pump()
end
ns.VoiceAlert = Alert

-- Detection --------------------------------------------------------------------

local state = {}

-- Hysteresis: alert once when the value drops below `low`, re-arm above `high`.
local function Threshold(key, pct, low, high)
  if pct < low then
    if not state[key] then state[key] = true; Alert(key) end
  elseif pct >= high then
    state[key] = nil
  end
end

local function Dead() return Plain(UnitIsDeadOrGhost("player")) == true end

local function CheckHealth()
  if Dead() then state.shields, state.hull = true, true; return end
  local h, m = Plain(UnitHealth("player")), Plain(UnitHealthMax("player"))
  if type(h) ~= "number" or type(m) ~= "number" or m <= 0 then return end -- secret: see LowHealth()
  local pct = h / m * 100
  Threshold("hull", pct, 25, 35)
  if pct >= 25 then Threshold("shields", pct, 50, 60) end
end

local function CheckPower()
  if Dead() or Plain(UnitPowerType("player")) ~= 0 then return end -- mana users only
  local p, m = Plain(UnitPower("player", 0)), Plain(UnitPowerMax("player", 0))
  if type(p) ~= "number" or type(m) ~= "number" or m <= 0 then return end
  local pct = p / m * 100
  if p <= 0 then
    if not state.capempty then state.capempty = true; Alert("capempty") end
  elseif pct >= 5 then
    state.capempty = nil
  end
  if p > 0 then Threshold("caplow", pct, 15, 25) end
end

-- The game's own low-health flash, read while our health numbers are secret.
local function LowHealth()
  local f = LowHealthFrame
  if not f or Dead() then return end
  local h = UnitHealth("player")
  if not ns.issecret(h) then return end -- plain values are handled by CheckHealth
  if GetUIPanel and ns.Call(GetUIPanel, "fullscreen") then return end -- flash means "can't see"
  local on = f:IsShown() and f.pulseAnim and f.pulseAnim:IsPlaying()
  if on then
    if not state.flash then state.flash = true; state.hull = true; Alert("hull") end
  else
    state.flash = nil
  end
end

local function CheckDurability()
  if not GetInventoryItemDurability then return end
  local low = false
  for slot = 1, 19 do
    local cur, max = ns.Call(GetInventoryItemDurability, slot)
    cur, max = Plain(cur), Plain(max)
    if type(cur) == "number" and type(max) == "number" and max > 0 and cur / max < 0.25 then low = true; break end
  end
  if low then
    if not state.repair then state.repair = true; Alert("repair") end
  else
    state.repair = nil
  end
end

-- Target destroyed: the hostile target we had locked dies.
local function CheckTarget()
  if not Plain(UnitExists("target")) then state.targetLive = nil; return end
  local dead = Plain(UnitIsDead("target"))
  if dead == true then
    if state.targetLive then state.targetLive = nil; Alert("kill") end
  elseif dead == false then
    state.targetLive = Plain(UnitCanAttack("player", "target")) == true or nil
  end
end

local function Mounted()
  return (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) or false
end

local function CheckWarp()
  local m = Mounted() and true or false
  if m and not state.mounted then Alert("warp") end
  state.mounted = m
end

local function CheckResting()
  local r = IsResting and IsResting() or false
  if r and not state.resting then Alert("dock") end
  state.resting = r
end

-- An enemy nameplate turns to us out of combat.
local function CheckLock(unit)
  if InCombatLockdown() or type(unit) ~= "string" or not unit:find("^nameplate") then return end
  if Plain(UnitCanAttack(unit, "player")) ~= true then return end
  if Plain(UnitIsUnit(unit .. "target", "player")) == true then Alert("hostile") end
end

-- Autopilot: Pilot.lua has no callback; its step index moving forward on the
-- same guide means the current step was reached.
local function CheckPilot()
  local P = ns.pilot
  if not P then return end
  local g = EveUI_GUIDE and EveUI_GUIDE.id
  local i = P.stepIndex
  if g == state.guide and type(i) == "number" and type(state.step) == "number" and i > state.step then
    Alert("waypoint")
  end
  state.guide, state.step = g, i
end

-- Module -----------------------------------------------------------------------

ns.RegisterModule(function()
  local v = DB()
  BuildBanner()

  local ev = CreateFrame("Frame")
  local function Reg(e, ...)
    if select("#", ...) > 0 then pcall(ev.RegisterUnitEvent, ev, e, ...) else pcall(ev.RegisterEvent, ev, e) end
  end
  Reg("PLAYER_ENTERING_WORLD")
  Reg("UNIT_HEALTH", "player", "target")
  Reg("UNIT_MAXHEALTH", "player")
  Reg("UNIT_POWER_UPDATE", "player")
  Reg("UNIT_SPELLCAST_INTERRUPTED", "player")
  Reg("PLAYER_TARGET_CHANGED")
  Reg("PLAYER_REGEN_DISABLED")
  Reg("UNIT_TARGET")
  Reg("PLAYER_MOUNT_DISPLAY_CHANGED")
  Reg("PLAYER_CONTROL_LOST")
  Reg("PLAYER_UPDATE_RESTING")
  Reg("PLAYER_LEVEL_UP")
  Reg("QUEST_TURNED_IN")
  Reg("UPDATE_INVENTORY_DURABILITY")

  ev:SetScript("OnEvent", ns.Safe("voice", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
      quietUntil = GetTime() + QUIET_START
      state.mounted, state.resting = Mounted() and true or false, IsResting and IsResting() or false
      state.targetLive = nil
      C_Timer.After(QUIET_START, function() CheckHealth(); CheckPower(); CheckDurability() end)
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
      if unit == "target" then CheckTarget() else CheckHealth() end
    elseif event == "UNIT_POWER_UPDATE" then
      CheckPower()
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
      Alert("interrupt")
    elseif event == "PLAYER_TARGET_CHANGED" then
      state.targetLive = nil
      CheckTarget()
    elseif event == "PLAYER_REGEN_DISABLED" then
      Alert("hostile")
    elseif event == "UNIT_TARGET" then
      CheckLock(Plain(unit))
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_CONTROL_LOST" then
      C_Timer.After(0.3, CheckWarp)
    elseif event == "PLAYER_UPDATE_RESTING" then
      CheckResting()
    elseif event == "PLAYER_LEVEL_UP" then
      Alert("level")
    elseif event == "QUEST_TURNED_IN" then
      Alert("quest")
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
      CheckDurability()
    end
  end))

  if LowHealthFrame and LowHealthFrame.EvaluateVisibleState then
    hooksecurefunc(LowHealthFrame, "EvaluateVisibleState", ns.Safe("voice lowhealth", LowHealth))
  end
  ns.Every(1, "voice pilot", CheckPilot)
  if v.channel and not CHANNELS[v.channel:lower()] then v.channel = "Master" end
end, "voice")

-- /eve voice [line | all | on | off | mute | sound | banner | channel <master|sfx|dialog>]
function ns.VoiceTest(arg)
  if not EveUIDB then return end
  local v = DB()
  local cmd, rest = (arg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "all" then
    if cmd == "" then
      Alert("shields", true)
      ns.Print("voice: playing a sample. /eve voice all | <line> | on | off | sound | banner | channel <master|sfx|dialog>")
      return
    end
    for i, l in ipairs(LINES) do
      C_Timer.After((i - 1) * 3.2, function() Play(BY[l[1]]) end)
    end
  elseif BY[cmd] then
    Alert(cmd, true)
  elseif cmd == "on" or cmd == "off" then
    v.off = (cmd == "off") or nil
    ns.Print("voice alerts " .. cmd)
  elseif cmd == "sound" or cmd == "mute" then
    v.sound = cmd == "sound" and not v.sound or false
    ns.Print("voice sound " .. (v.sound and "on" or "off") .. " (banners " .. (v.banner and "on" or "off") .. ")")
  elseif cmd == "banner" then
    v.banner = not v.banner
    ns.Print("voice banners " .. (v.banner and "on" or "off"))
  elseif cmd == "channel" and CHANNELS[rest] then
    v.channel = CHANNELS[rest]
    ns.Print("voice channel " .. v.channel)
    Alert("kill", true)
  elseif cmd == "toggle" and BY[rest] then
    if LineOn(rest) then v.lines[rest] = false else v.lines[rest] = nil end
    ns.Print("voice line " .. rest .. " " .. (LineOn(rest) and "on" or "off"))
  else
    local keys = {}
    for _, l in ipairs(LINES) do keys[#keys + 1] = l[1] end
    ns.Print("voice lines: " .. table.concat(keys, ", ") .. "  (/eve voice <line> | toggle <line>)")
  end
end
