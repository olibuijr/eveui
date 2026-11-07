-- Killmails: an EVE-style record of each fight that ended in a kill or a loss.
--
-- The combat log (COMBAT_LOG_EVENT_UNFILTERED) is restricted in this client,
-- so a fight is pieced together from other sources:
--   kills:  PARTY_KILL (attacker, victim GUIDs), UNIT_DIED for units we
--           targeted, the target turning dead (UNIT_HEALTH / UnitIsDead),
--           the "X dies, you gain N experience" message and ENCOUNTER_END
--           (boss kills). Only plain (non-secret) values are used.
--   deaths: PLAYER_DEAD, killer from the death recap (C_DeathRecap, the
--           first event is the killing blow).
--   damage: the game's damage meter (C_DamageMeter, Current session), read
--           after combat when its values are plain. Kills list damage done
--           by our side; losses list who damaged us (Damage Taken spells,
--           grouped by attacker).
-- Mails are kept in EveUIDB.killmails (newest last, 50 at most).
local ADDON, ns = ...
local C = ns.C
local issecret, Plain = ns.issecret, ns.Plain

local E = Enum or {}
local MT = E.DamageMeterType or {}
local ST = E.DamageMeterSessionType or { Overall = 0, Current = 1 }
local DAMAGE_DONE, DAMAGE_TAKEN = MT.DamageDone or 0, MT.DamageTaken or 7
local CAP, TOP_SOURCES, TOP_SPELLS = 50, 5, 8
local SKULL = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

-- Replaced by the module; says why nothing opens when it is off.
function ns.ToggleKillmails() ns.Print("killmails are turned off in the settings.") end

-- Helpers -------------------------------------------------------------------------

local function Str(v)
  v = Plain(v)
  if type(v) == "string" and v ~= "" then return v end
end

local function Num(v)
  v = Plain(v)
  if type(v) == "number" then return v end
end

local function Abbr(v)
  v = Num(v) or 0
  if AbbreviateNumbers then
    local ok, s = pcall(AbbreviateNumbers, v)
    if ok and type(s) == "string" then return s end
  end
  return tostring(math.floor(v + 0.5))
end

local function Clock(sec)
  sec = math.floor(Num(sec) or 0)
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

-- Classes are stored by their display name ("Mage"); the file name ("MAGE")
-- is looked up again for colours and icons.
local classFile = {}
local function ClassName(file)
  file = Str(file)
  if not file then return nil end
  local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]
    or (file:sub(1, 1) .. file:sub(2):lower())
  classFile[n] = file
  return n
end

local function ClassFile(name)
  if type(name) ~= "string" then return nil end
  if classFile[name] then return classFile[name] end
  for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
    for k, v in pairs(t or {}) do
      if v == name then classFile[name] = k return k end
    end
  end
end

local function ClassColor(name, fallback)
  local f = ClassFile(name)
  local c = f and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[f]
  if c then return { c.r, c.g, c.b, 1 } end
  return fallback or C.neutral
end

local function SetIcon(tex, class)
  local f = ClassFile(class)
  local atlas = f and GetClassAtlas and ns.Call(GetClassAtlas, f)
  if atlas then
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAtlas(atlas)
  else
    tex:SetTexture(SKULL)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end

local function SpellName(id)
  if not id or id == 0 then return nil end
  local n = C_Spell and C_Spell.GetSpellName and ns.Call(C_Spell.GetSpellName, id)
  if not n and GetSpellInfo then n = ns.Call(GetSpellInfo, id) end
  return Str(n)
end

local function SpellIcon(id)
  if not id or id == 0 then return 132223 end -- melee: a sword
  local i = C_Spell and C_Spell.GetSpellTexture and ns.Call(C_Spell.GetSpellTexture, id)
  if not i and GetSpellInfo then i = select(3, ns.Call(GetSpellInfo, id)) end
  return Plain(i) or 134400
end

local function MyGUID() return Str(UnitGUID("player")) end

-- Plain facts about a unit right now (nil when the name is secret).
local function Snapshot(unit)
  if Plain(UnitExists(unit)) ~= true then return nil end
  local name = Str(UnitName(unit))
  if not name then return nil end
  local class
  if Plain(UnitIsPlayer(unit)) == true then
    class = Str((UnitClass(unit)))
  else
    class = Str(UnitCreatureType(unit)) or "Creature"
  end
  local cls = Str(UnitClassification(unit))
  return {
    guid = Str(UnitGUID(unit)), name = name, level = Num(UnitLevel(unit)), class = class,
    hostile = Plain(UnitCanAttack("player", unit)) == true, boss = cls == "worldboss",
  }
end

-- Player name/class/level from a GUID (players only).
local function PlayerByGUID(guid)
  if not guid or not GetPlayerInfoByGUID then return nil end
  local lclass, _, _, _, _, name, _, level = ns.Call(GetPlayerInfoByGUID, guid)
  name = Str(name)
  if not name then return nil end
  return { guid = guid, name = name, class = Str(lclass), level = Num(level) }
end

-- Fight tracking ------------------------------------------------------------------

local fight
local function Fight()
  if not fight then
    fight = { start = time(), seen = {}, byName = {}, kills = {} }
  end
  return fight
end

local function Remember(s)
  if not s then return end
  local f = Fight()
  if s.guid then f.seen[s.guid] = s end
  f.byName[s.name] = s
end

-- One entry per victim: a GUID kill replaces a name-only one for the same name.
local function AddKill(s, killer)
  if not s or not s.name then return end
  local f = Fight()
  local now = GetTime()
  for _, k in ipairs(f.kills) do
    local same = (s.guid and k.victim.guid == s.guid)
      or (k.victim.name == s.name and (not s.guid or not k.victim.guid) and now - k.at < 5)
    if same then
      if s.guid and not k.victim.guid then k.victim = s end
      k.killer = k.killer or killer
      k.boss = k.boss or s.boss
      return
    end
  end
  f.kills[#f.kills + 1] = { victim = s, killer = killer, boss = s.boss, at = now }
end

local function Who(guid)
  if not guid then return nil end
  if guid == MyGUID() then
    return { name = Str(UnitName("player")) or "You", class = Str((UnitClass("player"))) }
  end
  local p = PlayerByGUID(guid)
  if p then return { name = p.name, class = p.class } end
  local tok = Str(ns.Call(UnitTokenFromGUID, guid))
  local s = tok and Snapshot(tok)
  if s then return { name = s.name, class = s.class } end
end

-- XP message pattern from the game's own string ("%s dies, you gain %d experience.").
local xpPattern
local function XPPattern()
  if xpPattern then return xpPattern end
  local fmt = type(COMBATLOG_XPGAIN_FIRSTPERSON) == "string" and COMBATLOG_XPGAIN_FIRSTPERSON
    or "%s dies, you gain %d experience."
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
  xpPattern = "^" .. p
  return xpPattern
end

-- Building a mail -----------------------------------------------------------------

local function SourceClass(src)
  local n = ClassName(src.classFilename)
  if n then return n end
  return Plain(src.sourceDisplayType) == 2 and "NPC" or "Pet"
end

local function SpellsOf(sessionType, mtype, src)
  local out = {}
  local guid, cid = src.sourceGUID, src.sourceCreatureID
  if issecret(guid) or issecret(cid) then return out end
  local sd = ns.Call(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, mtype, guid, cid)
  for _, sp in ipairs(sd and sd.combatSpells or {}) do
    local id, amt = Num(sp.spellID), Num(sp.totalAmount)
    if amt and amt > 0 then
      out[#out + 1] = { spellID = id or 0, name = SpellName(id) or "Melee", amount = math.floor(amt + 0.5) }
    end
  end
  table.sort(out, function(a, b) return a.amount > b.amount end)
  for i = #out, TOP_SPELLS + 1, -1 do out[i] = nil end
  return out
end

-- Damage done by everyone in the fight (our side for kills).
local function DamageDone()
  local out = {}
  local s = ns.Call(C_DamageMeter.GetCombatSessionFromType, ST.Current, DAMAGE_DONE)
  local srcs = {}
  for _, src in ipairs(s and s.combatSources or {}) do
    local name, amt = Str(src.name), Num(src.totalAmount)
    if name and amt and amt > 0 then srcs[#srcs + 1] = { src = src, name = name, amount = amt } end
  end
  table.sort(srcs, function(a, b) return a.amount > b.amount end)
  for i, e in ipairs(srcs) do
    out[i] = { name = e.name, class = SourceClass(e.src), amount = math.floor(e.amount + 0.5),
      spells = i <= TOP_SOURCES and SpellsOf(ST.Current, DAMAGE_DONE, e.src) or {} }
  end
  return out
end

-- Who damaged the player: Damage Taken spells grouped by the attacker's name.
local function DamageOnMe(byName)
  local s = ns.Call(C_DamageMeter.GetCombatSessionFromType, ST.Current, DAMAGE_TAKEN)
  local me
  for _, src in ipairs(s and s.combatSources or {}) do
    if src.isLocalPlayer == true then me = src break end
  end
  if not me or issecret(me.sourceGUID) then return {} end
  local sd = ns.Call(C_DamageMeter.GetCombatSessionSourceFromType, ST.Current, DAMAGE_TAKEN,
    me.sourceGUID, me.sourceCreatureID)
  local by, list = {}, {}
  for _, sp in ipairs(sd and sd.combatSpells or {}) do
    local amt, id = Num(sp.totalAmount), Num(sp.spellID)
    local who = Str(sp.creatureName) or "Unknown"
    if amt and amt > 0 then
      local e = by[who]
      if not e then
        local p = byName[who]
        e = { name = who, class = p and p.class or "NPC", amount = 0, spells = {} }
        by[who] = e
        list[#list + 1] = e
      end
      e.amount = e.amount + math.floor(amt + 0.5)
      e.spells[#e.spells + 1] = { spellID = id or 0, name = SpellName(id) or "Melee", amount = math.floor(amt + 0.5) }
    end
  end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  for i, e in ipairs(list) do
    table.sort(e.spells, function(a, b) return a.amount > b.amount end)
    for j = #e.spells, (i <= TOP_SOURCES and TOP_SPELLS or 0) + 1, -1 do e.spells[j] = nil end
  end
  return list
end

-- Killing blow from the death recap (newest death), plus a damage list
-- from the recap when the meter has nothing.
local function Recap()
  if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil, {} end
  local events = ns.Call(C_DeathRecap.GetRecapEvents) or {}
  local killer, by, list = nil, {}, {}
  for i, ev in ipairs(events) do
    local name = Str(ev.sourceName)
    if not name and Str(ev.event) == "ENVIRONMENTAL_DAMAGE" then
      local t = Str(ev.environmentalType)
      name = t and (t:sub(1, 1):upper() .. t:sub(2):lower()) or "Environment"
    end
    name = name or "Unknown"
    local guid = Str(ev.sourceGUID)
    local p = guid and PlayerByGUID(guid)
    local class = p and p.class or (Str(ev.event) == "ENVIRONMENTAL_DAMAGE" and "Environment") or "NPC"
    if i == 1 then killer = { name = name, class = class } end
    local amt = Num(ev.amount)
    if amt and amt > 0 then
      local e = by[name]
      if not e then e = { name = name, class = class, amount = 0, spells = {} }; by[name] = e; list[#list + 1] = e end
      e.amount = e.amount + amt
      local id = Num(ev.spellId)
      e.spells[#e.spells + 1] = { spellID = id or 0, name = Str(ev.spellName) or SpellName(id) or "Melee", amount = amt }
    end
  end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  return killer, list
end

local function Zone()
  return Str(GetRealZoneText and GetRealZoneText()) or Str(GetZoneText and GetZoneText()) or "Unknown"
end

local function Duration(f)
  return math.floor((Num(ns.Call(C_DamageMeter.GetSessionDurationSeconds, ST.Current)) or (time() - f.start)) + 0.5)
end

local function Save(mail)
  EveUIDB.killmails = EveUIDB.killmails or {}
  local list = EveUIDB.killmails
  list[#list + 1] = mail
  while #list > CAP do table.remove(list, 1) end
end

local OnNewMail -- set by the UI
local pending

local function Build()
  pending = nil
  if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED schedules again
  local f = fight
  fight = nil
  if not f or (#f.kills == 0 and not f.died) then return end
  local zone, dur = Zone(), Duration(f)
  local made = {}

  if f.died then
    local killer, recapList = Recap()
    local dmg = DamageOnMe(f.byName)
    if #dmg == 0 then dmg = recapList end
    if not killer and dmg[1] then killer = { name = dmg[1].name, class = dmg[1].class } end
    made[#made + 1] = {
      time = time(), kind = "death", zone = zone, duration = dur,
      victim = { name = Str(UnitName("player")) or "You", level = Num(UnitLevel("player")),
        class = Str((UnitClass("player"))) },
      killer = killer, damage = dmg,
    }
  end

  if #f.kills > 0 then
    local k = f.kills[#f.kills]
    for _, x in ipairs(f.kills) do if x.boss then k = x end end
    local v = k.victim
    made[#made + 1] = {
      time = time(), kind = "kill", zone = zone, duration = dur,
      victim = { name = v.name, level = v.level, class = v.class },
      killer = k.killer and { name = k.killer.name, class = k.killer.class } or nil,
      damage = DamageDone(),
    }
  end

  for _, m in ipairs(made) do
    Save(m)
    if OnNewMail then OnNewMail(m) end
  end
end

local function ScheduleBuild(delay)
  if pending or InCombatLockdown() then return end
  pending = true
  C_Timer.After(delay or 1, ns.Safe("killmail", Build))
end

-- Events --------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local function OnEvent(_, event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    if not pending then fight = nil end
    Fight()
    local t = Snapshot("target")
    Remember(t)
    if t and t.hostile then fight.target = t end
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- Wait a moment: the XP message and late deaths arrive just after.
    ScheduleBuild(1)
  elseif event == "PLAYER_TARGET_CHANGED" then
    local t = Snapshot("target")
    if t and t.hostile and (fight or InCombatLockdown()) then
      Remember(t)
      Fight().target = t
    end
  elseif event == "UNIT_HEALTH" then
    local unit = ...
    if unit ~= "target" or not fight or not fight.target then return end
    if Plain(UnitIsDead("target")) == true then
      local now = Snapshot("target")
      local t = fight.target
      if not now or (now.guid and now.guid == t.guid) or (not now.guid and now.name == t.name) then
        AddKill(t)
        ScheduleBuild(1)
      end
    end
  elseif event == "UNIT_DIED" then
    local guid = Str(...)
    local s = guid and fight and fight.seen[guid]
    if s then AddKill(s); ScheduleBuild(1) end
  elseif event == "PARTY_KILL" then
    local a, t = Str((...)), Str((select(2, ...)))
    if not t then return end
    local v = (fight and fight.seen[t]) or PlayerByGUID(t)
    if not v then
      local tok = Str(ns.Call(UnitTokenFromGUID, t))
      v = tok and Snapshot(tok)
    end
    if v then
      Remember(v)
      AddKill(v, Who(a))
      ScheduleBuild(1)
    end
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local text = Str(...)
    local name = text and text:match(XPPattern())
    if name then
      AddKill(Fight().byName[name] or { name = name, class = "Creature" })
      ScheduleBuild(1)
    end
  elseif event == "ENCOUNTER_END" then
    local _, name, _, _, success = ...
    name = Str(name)
    if Plain(success) == 1 and name then
      AddKill({ name = name, level = -1, class = "Boss", boss = true })
      ScheduleBuild(1)
    end
  elseif event == "PLAYER_DEAD" then
    Fight().died = true
    ScheduleBuild(1)
  end
end

-- UI ------------------------------------------------------------------------------

local W, H, LIST_W, ROW = 760, 460, 230, 20
local win, Select, Refresh

local function Button(parent, label, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 60, ns.HEADER - 5)
  b.text = ns.Text(b, 11, C.dim, "CENTER")
  b.text:SetAllPoints()
  b.text:SetText(label)
  b:SetScript("OnEnter", function(s) s.text:SetTextColor(unpack(C.accent)) end)
  b:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(C.dim)) end)
  return b
end

local menu
local function OpenMenu(owner, items)
  if not menu then
    menu = ns.CreatePanel("EveUIKillmailMenu", ns.root, nil, 150, 20)
    menu:SetFrameStrata("DIALOG")
    menu:EnableMouse(true)
    menu.items = {}
    pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function(m)
      if m:IsShown() and not m:IsMouseOver() and not (m.owner and m.owner:IsMouseOver()) then m:Hide() end
    end)
  end
  if menu:IsShown() and menu.owner == owner then menu:Hide() return end
  menu.owner = owner
  for i, it in ipairs(items) do
    local b = menu.items[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(18)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints(); hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
      b.text = ns.Text(b, 11, C.text, "LEFT")
      b.text:SetPoint("LEFT", 10, 0); b.text:SetPoint("RIGHT", -8, 0)
      menu.items[i] = b
    end
    b:SetPoint("TOPLEFT", 1, -(4 + (i - 1) * 18)); b:SetPoint("TOPRIGHT", -1, -(4 + (i - 1) * 18))
    b.text:SetText(it.text)
    b:SetScript("OnClick", function() menu:Hide(); it.func() end)
    b:Show()
  end
  for i = #items + 1, #menu.items do menu.items[i]:Hide() end
  menu:SetSize(150, #items * 18 + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
  menu:SetClampedToScreen(true)
  menu:Show()
end

local function Mails() return EveUIDB.killmails or {} end

local function Summary(m)
  local v = m.victim or {}
  local s = ("Killmail [%s] %s (%s %s) - %s, %s."):format(m.kind == "kill" and "KILL" or "LOSS",
    v.name or "?", v.level == -1 and "??" or tostring(v.level or "?"), v.class or "", m.zone or "?",
    Clock(m.duration))
  if m.killer then s = s .. (" Final blow: %s."):format(m.killer.name or "?") end
  local total = 0
  for _, d in ipairs(m.damage or {}) do total = total + (d.amount or 0) end
  local top = {}
  for i = 1, math.min(3, #(m.damage or {})) do
    local d = m.damage[i]
    top[#top + 1] = ("%s %s (%d%%)"):format(d.name, Abbr(d.amount), total > 0 and math.floor(d.amount / total * 100 + 0.5) or 0)
  end
  if #top > 0 then s = s .. " Top: " .. table.concat(top, ", ") .. "." end
  if #s > 250 then s = s:sub(1, 247) .. "..." end
  return s
end

local function Post(m, channel)
  if InCombatLockdown() then return ns.Print("killmails can be posted after combat.") end
  local s = Summary(m)
  if channel == "SELF" then return ns.Print(s) end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send then send(s, channel) end
end

local function BuildWindow()
  local f = ns.CreatePanel("EveUIKillmails", ns.root, "Killmails", W, H)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "EveUIKillmails") end
  ns.Mover(f, { key = "killmails", label = "Killmails", point = "CENTER", x = 0, y = 60 })

  -- Drag by the title bar.
  local drag = CreateFrame("Frame", nil, f)
  drag:SetPoint("TOPLEFT", 1, -1); drag:SetPoint("TOPRIGHT", -200, -1)
  drag:SetHeight(ns.HEADER - 1)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() f:StartMoving() end)
  drag:SetScript("OnDragStop", function() f:StopMovingOrSizing(); ns.SavePos(f) end)

  local close = Button(f, "X", 20)
  close:SetPoint("TOPRIGHT", -4, -2)
  close:SetScript("OnClick", function() f:Hide() end)
  local del = Button(f, "DELETE", 54)
  del:SetPoint("RIGHT", close, "LEFT", -6, 0)
  local copy = Button(f, "COPY TO CHAT", 90)
  copy:SetPoint("RIGHT", del, "LEFT", -6, 0)

  local count = ns.Text(f, 11, C.dim, "LEFT")
  count:SetPoint("LEFT", f.title, "RIGHT", 10, 0)

  -- Left: list -------------------------------------------------------------------
  local div = f:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(unpack(C.line))
  div:SetPoint("TOPLEFT", LIST_W, -ns.HEADER - 1); div:SetPoint("BOTTOMLEFT", LIST_W, 1)
  div:SetWidth(1)

  local listTop = ns.HEADER + 4
  local visible = math.floor((H - listTop - 6) / ROW)
  local rows, offset, sel = {}, 0, nil
  local empty = ns.Text(f, 11, C.dim, "LEFT")
  empty:SetPoint("TOPLEFT", 10, -(listTop + 6))
  empty:SetText("No killmails yet.")

  for i = 1, visible do
    local r = CreateFrame("Button", nil, f)
    r:SetPoint("TOPLEFT", 2, -(listTop + (i - 1) * ROW))
    r:SetSize(LIST_W - 4, ROW - 1)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints(); r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.14)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    r.time = ns.Text(r, 10, C.dim, "LEFT")
    r.time:SetPoint("LEFT", 6, 0); r.time:SetWidth(66)
    r.tag = ns.Text(r, 10, C.heal, "CENTER")
    r.tag:SetFont(ns.FONT_BOLD, 10, "")
    r.tag:SetPoint("LEFT", r.time, "RIGHT", 2, 0); r.tag:SetWidth(34)
    r.name = ns.Text(r, 11, C.text, "LEFT")
    r.name:SetPoint("LEFT", r.tag, "RIGHT", 4, 0); r.name:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnClick", function(s) if s.index then Select(s.index) end end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, d) offset = math.max(0, offset - d); Refresh() end)
    rows[i] = r
  end

  -- Right: detail ----------------------------------------------------------------
  local d = CreateFrame("Frame", nil, f)
  d:SetPoint("TOPLEFT", LIST_W + 10, -(ns.HEADER + 10))
  d:SetPoint("BOTTOMRIGHT", -10, 10)
  local dw = W - LIST_W - 20

  local vbox = CreateFrame("Frame", nil, d)
  vbox:SetPoint("TOPLEFT"); vbox:SetPoint("TOPRIGHT")
  vbox:SetHeight(78)
  ns.Box(vbox, C.bg, C.border)
  local stripe = vbox:CreateTexture(nil, "ARTWORK")
  stripe:SetPoint("TOPLEFT", 1, -1); stripe:SetPoint("BOTTOMLEFT", 1, 1); stripe:SetWidth(3)
  local iconFrame = CreateFrame("Frame", nil, vbox)
  iconFrame:SetSize(62, 62)
  iconFrame:SetPoint("LEFT", 10, 0)
  ns.Box(iconFrame, C.black, C.border)
  local icon = iconFrame:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
  local vname = ns.Text(vbox, 17, C.title, "LEFT")
  vname:SetFont(ns.FONT_BOLD, 17, "")
  vname:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 12, -2); vname:SetPoint("RIGHT", -70, 0)
  local vline = ns.Text(vbox, 11, C.text, "LEFT")
  vline:SetPoint("TOPLEFT", vname, "BOTTOMLEFT", 0, -4)
  local vzone = ns.Text(vbox, 11, C.dim, "LEFT")
  vzone:SetPoint("TOPLEFT", vline, "BOTTOMLEFT", 0, -3)
  local vstats = ns.Text(vbox, 11, C.dim, "LEFT")
  vstats:SetPoint("TOPLEFT", vzone, "BOTTOMLEFT", 0, -3)
  local vtag = ns.Text(vbox, 13, C.heal, "RIGHT")
  vtag:SetFont(ns.FONT_BOLD, 13, "")
  vtag:SetPoint("TOPRIGHT", -10, -8)

  local function InfoBox(label, anchor, x)
    local b = CreateFrame("Frame", nil, d)
    b:SetSize((dw - 8) / 2, 42)
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -8)
    ns.Box(b, C.bg, C.border)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 6, 0)
    local h = ns.Text(b, 9, C.accent, "LEFT")
    h:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 0)
    h:SetText(label)
    b.name = ns.Text(b, 12, C.title, "LEFT")
    b.name:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2); b.name:SetPoint("RIGHT", -6, 0)
    b.sub = ns.Text(b, 10, C.dim, "LEFT")
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
    return b
  end
  local finalBox = InfoBox("FINAL BLOW", vbox, 0)
  local topBox = InfoBox("TOP DAMAGE", vbox, (dw - 8) / 2 + 8)

  local partHead = ns.Text(d, 10, C.dim, "LEFT")
  partHead:SetPoint("TOPLEFT", finalBox, "BOTTOMLEFT", 0, -10)
  local hline = d:CreateTexture(nil, "ARTWORK")
  hline:SetColorTexture(unpack(C.line))
  hline:SetPoint("TOPLEFT", partHead, "BOTTOMLEFT", 0, -3); hline:SetPoint("RIGHT", d, "RIGHT")
  hline:SetHeight(1)

  local partTop = 78 + 8 + 42 + 10 + 18
  local partLines = math.floor((H - ns.HEADER - 20 - partTop) / 18)
  local lines, lineData, lineOffset = {}, {}, 0
  local nothing = ns.Text(d, 11, C.dim, "LEFT")
  nothing:SetPoint("TOPLEFT", 0, -(partTop + 4))
  nothing:SetText("No damage recorded.")

  for i = 1, partLines do
    local l = CreateFrame("Frame", nil, d)
    l:SetPoint("TOPLEFT", 0, -(partTop + (i - 1) * 18))
    l:SetPoint("RIGHT", d, "RIGHT")
    l:SetHeight(17)
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetSize(16, 16)
    l.bar = CreateFrame("StatusBar", nil, l)
    l.bar:SetStatusBarTexture(ns.WHITE)
    l.bar:SetMinMaxValues(0, 1)
    l.bar:SetPoint("TOPLEFT", l.icon, "TOPRIGHT", 3, 0)
    l.bar:SetPoint("BOTTOMRIGHT")
    local bg = l.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(unpack(C.off))
    l.name = ns.Text(l.bar, 11, C.title, "LEFT")
    l.name:SetPoint("LEFT", 5, 0)
    l.value = ns.Text(l.bar, 11, C.title, "RIGHT")
    l.value:SetPoint("RIGHT", -5, 0)
    l.name:SetPoint("RIGHT", l.value, "LEFT", -6, 0)
    l:EnableMouseWheel(true)
    l:SetScript("OnMouseWheel", function(_, dd)
      lineOffset = math.max(0, math.min(lineOffset - dd * 2, #lineData - partLines))
      Refresh()
    end)
    lines[i] = l
  end

  local function DrawLine(l, e)
    l.icon:ClearAllPoints()
    if e.spell then
      l.icon:SetPoint("LEFT", 22, 0)
      l.icon:SetSize(14, 14)
      l.icon:SetTexture(SpellIcon(e.spell.spellID))
      l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      ns.SetBarColor(l.bar, { e.color[1], e.color[2], e.color[3], 0.45 })
      l.bar:SetValue(e.frac)
      l.name:SetText(e.spell.name or "Melee")
      l.name:SetTextColor(unpack(C.text))
      l.value:SetFormattedText("%s  %.0f%%", Abbr(e.spell.amount), e.frac * 100)
      l.value:SetTextColor(unpack(C.dim))
    else
      local p = e.party
      l.icon:SetPoint("LEFT", 0, 0)
      l.icon:SetSize(16, 16)
      SetIcon(l.icon, p.class)
      ns.SetBarColor(l.bar, e.color)
      l.bar:SetValue(e.frac)
      l.name:SetFormattedText("%s  |cff8090a0%s|r", p.name or "?", p.class or "")
      l.name:SetTextColor(unpack(C.title))
      l.value:SetFormattedText("%s  %.1f%%", Abbr(p.amount), e.frac * 100)
      l.value:SetTextColor(unpack(C.title))
    end
    l:Show()
  end

  local function ShowMail(m)
    local kill = m.kind == "kill"
    local tc = kill and C.heal or C.hostile
    stripe:SetColorTexture(unpack(tc))
    vtag:SetText(kill and "KILL" or "LOSS")
    vtag:SetTextColor(unpack(tc))
    local v = m.victim or {}
    SetIcon(icon, v.class)
    vname:SetText(v.name or "?")
    vline:SetFormattedText("Level %s  %s", v.level == -1 and "??" or tostring(v.level or "?"), v.class or "")
    vzone:SetFormattedText("%s  -  %s", m.zone or "?", date("%Y-%m-%d %H:%M", m.time or 0))

    local total = 0
    for _, p in ipairs(m.damage or {}) do total = total + (p.amount or 0) end
    vstats:SetFormattedText("Duration %s   Total damage %s   Involved %d", Clock(m.duration), Abbr(total), #(m.damage or {}))

    local k = m.killer
    if k then
      SetIcon(finalBox.icon, k.class)
      finalBox.name:SetText(k.name or "?"); finalBox.sub:SetText(k.class or "")
    else
      finalBox.icon:SetTexture(SKULL); finalBox.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      finalBox.name:SetText("Unknown"); finalBox.sub:SetText(kill and "not seen" or "")
    end
    local t = m.damage and m.damage[1]
    if t then
      SetIcon(topBox.icon, t.class)
      topBox.name:SetText(t.name or "?")
      topBox.sub:SetFormattedText("%s  (%.1f%%)", Abbr(t.amount), total > 0 and t.amount / total * 100 or 0)
    else
      topBox.icon:SetTexture(SKULL); topBox.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      topBox.name:SetText("-"); topBox.sub:SetText("")
    end
    partHead:SetFormattedText("INVOLVED PARTIES  (%d)", #(m.damage or {}))

    wipe(lineData)
    for _, p in ipairs(m.damage or {}) do
      local color = ClassColor(p.class, kill and C.friendly or C.hostile)
      lineData[#lineData + 1] = { party = p, color = color, frac = total > 0 and (p.amount or 0) / total or 0 }
      for _, sp in ipairs(p.spells or {}) do
        lineData[#lineData + 1] = { spell = sp, color = color,
          frac = (p.amount or 0) > 0 and (sp.amount or 0) / p.amount or 0 }
      end
    end
    lineOffset = math.max(0, math.min(lineOffset, #lineData - partLines))
    for i = 1, partLines do
      local e = lineData[lineOffset + i]
      if e then DrawLine(lines[i], e) else lines[i]:Hide() end
    end
    nothing:SetShown(#lineData == 0)
  end

  function Refresh()
    local list = Mails()
    local n = #list
    count:SetFormattedText("%d", n)
    if sel and not list[sel] then sel = n > 0 and n or nil end
    offset = math.max(0, math.min(offset, n - visible))
    for i = 1, visible do
      local idx = n - offset - i + 1 -- newest first
      local r, m = rows[i], list[idx]
      if m then
        r.index = idx
        r.time:SetText(date("%m-%d %H:%M", m.time or 0))
        local kill = m.kind == "kill"
        r.tag:SetText(kill and "KILL" or "LOSS")
        r.tag:SetTextColor(unpack(kill and C.heal or C.hostile))
        r.name:SetText(m.victim and m.victim.name or "?")
        r.sel:SetShown(idx == sel)
        r:Show()
      else
        r.index = nil
        r:Hide()
      end
    end
    empty:SetShown(n == 0)
    d:SetShown(sel ~= nil)
    copy:SetShown(sel ~= nil); del:SetShown(sel ~= nil)
    if sel then ShowMail(list[sel]) end
  end

  function Select(idx)
    if idx ~= sel then lineOffset = 0 end
    sel = idx
    Refresh()
  end

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, dd) offset = math.max(0, offset - dd); Refresh() end)
  f:SetScript("OnShow", function()
    if not sel and #Mails() > 0 then sel = #Mails() end
    Refresh()
  end)

  copy:SetScript("OnClick", function(s)
    local m = sel and Mails()[sel]
    if not m then return end
    local items = { { text = "Chat (only you)", func = function() Post(m, "SELF") end } }
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
      items[#items + 1] = { text = "Instance", func = function() Post(m, "INSTANCE_CHAT") end }
    end
    if IsInRaid() then items[#items + 1] = { text = "Raid", func = function() Post(m, "RAID") end }
    elseif IsInGroup() then items[#items + 1] = { text = "Party", func = function() Post(m, "PARTY") end } end
    if IsInGuild() then items[#items + 1] = { text = "Guild", func = function() Post(m, "GUILD") end } end
    items[#items + 1] = { text = "Say", func = function() Post(m, "SAY") end }
    OpenMenu(s, items)
  end)

  local armed
  del:SetScript("OnClick", function(s)
    if not sel then return end
    if not armed then
      armed = true
      s.text:SetText("CONFIRM")
      C_Timer.After(3, function() armed = nil; s.text:SetText("DELETE") end)
      return
    end
    armed = nil
    s.text:SetText("DELETE")
    table.remove(Mails(), sel)
    sel = #Mails() > 0 and math.min(sel, #Mails()) or nil
    Refresh()
  end)

  f.Select = Select
  return f
end

local function Open(idx)
  if not win then win = BuildWindow() end
  win:Show()
  if idx then win.Select(idx) end
end

-- Toast ---------------------------------------------------------------------------

local toast, toastSerial = nil, 0
local function Toast(m, idx)
  if not toast then
    toast = CreateFrame("Button", "EveUIKillmailToast", ns.root)
    toast:SetSize(280, 46)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -150)
    toast:SetFrameStrata("HIGH")
    ns.Box(toast, C.panel, C.border)
    toast.stripe = toast:CreateTexture(nil, "ARTWORK")
    toast.stripe:SetPoint("TOPLEFT", 1, -1); toast.stripe:SetPoint("BOTTOMLEFT", 1, 1); toast.stripe:SetWidth(3)
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(34, 34); toast.icon:SetPoint("LEFT", 10, 0)
    toast.head = ns.Text(toast, 10, C.accent, "LEFT")
    toast.head:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 8, -1)
    toast.text = ns.Text(toast, 13, C.title, "LEFT")
    toast.text:SetPoint("TOPLEFT", toast.head, "BOTTOMLEFT", 0, -3)
    toast.text:SetPoint("RIGHT", -8, 0)
    local hl = toast:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    toast:SetScript("OnClick", function(s) s:Hide(); Open(s.index) end)
    toast:Hide()
  end
  local kill = m.kind == "kill"
  toast.stripe:SetColorTexture(unpack(kill and C.heal or C.hostile))
  SetIcon(toast.icon, m.victim and m.victim.class)
  toast.head:SetFormattedText("%s  -  %s", kill and "KILL" or "LOSS", m.zone or "")
  toast.head:SetTextColor(unpack(kill and C.heal or C.hostile))
  toast.text:SetFormattedText("KILLMAIL: %s", m.victim and m.victim.name or "?")
  toast.index = idx
  toast:Show()
  toastSerial = toastSerial + 1
  local mine = toastSerial
  C_Timer.After(8, function() if toastSerial == mine and toast then toast:Hide() end end)
end

-- Module --------------------------------------------------------------------------

ns.RegisterModule(function()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end
  EveUIDB.killmails = EveUIDB.killmails or {}

  OnNewMail = function(m)
    local idx = #Mails()
    Toast(m, idx)
    if win and win:IsShown() then win.Select(idx) end
  end

  function ns.ToggleKillmails()
    if win and win:IsShown() then win:Hide() else Open() end
  end

  for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
    "UNIT_DIED", "PARTY_KILL", "CHAT_MSG_COMBAT_XP_GAIN", "ENCOUNTER_END", "PLAYER_DEAD" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target")
  ev:SetScript("OnEvent", ns.Safe("killmail events", OnEvent))
end, "killmail")
