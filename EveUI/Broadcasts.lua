-- Fleet broadcasts: EVE-style group calls between EveUI users (target, need
-- shield/capacitor, in position, hold, align to, enemy spotted, jump, clear).
--
-- Sent as addon messages (prefix "EveUI") to the party, raid or instance
-- group. A small broadcast bar sends them; incoming ones go to the FLEET
-- BROADCASTS history and a short toast. Targets, enemies and requests for
-- help are kept in ns.fleetTags (by plain unit GUID, 60 s) for other modules.
--
-- Message: "E1^<kind>^<fields...>". Only plain values are ever sent; when the
-- game hides a GUID, name or position (combat, instances) the call is refused.
local ADDON, ns = ...
local C = ns.C

local PREFIX, VERSION, SEP = "EveUI", "E1", "^"
local TAG_TTL, HISTORY_MAX, VISIBLE_ROWS = 60, 20, 8
local ROW_H, BTN_W, BTN_H = 16, 32, 22

local issecret, Plain = ns.issecret, ns.Plain

ns.fleetTags = ns.fleetTags or {}
ns.fleetTagsStamp = ns.fleetTagsStamp or 0

-- code, key, short label, full label, colour key, tag kind
local KINDS = {
  { "T", "target",   "TGT", "Target",              "hostile", "target" },
  { "S", "shield",   "ARM", "Need shield / armor", "shield",  "heal" },
  { "C", "cap",      "CAP", "Need capacitor",      "cap",     "mana" },
  { "P", "position", "POS", "In position",         "friendly" },
  { "H", "hold",     "HLD", "Hold position",       "neutral" },
  { "A", "align",    "ALN", "Align to",            "accent" },
  { "E", "enemy",    "ENY", "Enemy spotted",       "hostile", "enemy" },
  { "J", "jump",     "JMP", "Jump / travel",       "accent" },
  { "X", "clear",    "CLR", "Clear",               "dim" },
}
local byCode, byKey = {}, {}
for _, k in ipairs(KINDS) do
  local d = { code = k[1], key = k[2], short = k[3], label = k[4], color = k[5], tag = k[6] }
  byCode[d.code], byKey[d.key] = d, d
end
local ALIAS = {
  tgt = "target", t = "target", armor = "shield", armour = "shield", heal = "shield", heals = "shield",
  capacitor = "cap", mana = "cap", inposition = "position", pos = "position", ["in position"] = "position",
  holdposition = "hold", ["hold position"] = "hold", alignto = "align", ["align to"] = "align",
  spotted = "enemy", enemyspotted = "enemy", travel = "jump", move = "jump", moving = "jump",
}

local function Color(d) return C[d.color] or C.text end

-- Names and group units ------------------------------------------------------

local function Short(sender)
  if Ambiguate then return Ambiguate(sender, "none") end
  return sender
end

local function MyName()
  return Plain(UnitName("player")) or "?"
end

-- Group unit for a sender name ("Name" or "Name-Realm"), or nil.
local function UnitByName(name)
  if not name then return nil end
  local short = name:match("^[^-]+")
  local function Match(u)
    local n, realm = UnitName(u)
    n, realm = Plain(n), Plain(realm)
    if not n then return false end
    local full = (realm and realm ~= "") and (n .. "-" .. realm) or n
    return full == name or n == name or (n == short and (not realm or realm == ""))
  end
  if Match("player") then return "player" end
  if IsInRaid() then
    for i = 1, 40 do
      local u = "raid" .. i
      if UnitExists(u) and Match(u) then return u end
    end
  else
    for i = 1, 4 do
      local u = "party" .. i
      if UnitExists(u) and Match(u) then return u end
    end
  end
end

local function NameColor(name)
  local u = UnitByName(name)
  return u and ns.ClassColor(u) or C.text
end

local function Hex(c)
  return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Fleet tags -----------------------------------------------------------------

local function Tag(guid, kind, from)
  if type(guid) ~= "string" or guid == "" then return end
  ns.fleetTags[guid] = { kind = kind, from = from, time = GetTime() }
  ns.fleetTagsStamp = ns.fleetTagsStamp + 1
end

local function ExpireTags()
  local now, changed = GetTime(), false
  for guid, t in pairs(ns.fleetTags) do
    if now - (t.time or 0) > TAG_TTL then ns.fleetTags[guid] = nil; changed = true end
  end
  if changed then ns.fleetTagsStamp = ns.fleetTagsStamp + 1 end
end

local function ClearTagsFrom(from)
  for guid, t in pairs(ns.fleetTags) do
    if t.from == from then ns.fleetTags[guid] = nil end
  end
  ns.fleetTagsStamp = ns.fleetTagsStamp + 1
end

-- Positions ------------------------------------------------------------------

local function MyMapPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = Plain(ns.Call(C_Map.GetBestMapForUnit, "player"))
  if type(map) ~= "number" then return nil end
  local pos = ns.Call(C_Map.GetPlayerMapPosition, map, "player")
  if not pos then return nil end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  x, y = Plain(x), Plain(y)
  if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
  return map, x, y
end

local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Compass direction and distance (yards) from the player to a map point.
local function Bearing(map, x, y)
  if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local pos = ns.Call(C_Map.GetPlayerMapPosition, map, "player")
  if not pos then return nil end
  local px, py = pos.x, pos.y
  if pos.GetXY then px, py = pos:GetXY() end
  px, py = Plain(px), Plain(py)
  if type(px) ~= "number" or type(py) ~= "number" then return nil end
  local w, h = ns.Call(C_Map.GetMapWorldSize, map)
  w, h = Plain(w), Plain(h)
  if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
  local east, north = (x - px) * w, (py - y) * h
  local dist = math.sqrt(east * east + north * north)
  local deg = math.deg(math.atan2(east, north)) % 360
  return DIRS[math.floor((deg + 22.5) / 45) % 8 + 1], dist, deg
end

local function BearingText(map, x, y)
  local dir, dist = Bearing(map, x, y)
  if dir then return ("%s %d yd"):format(dir, math.floor(dist + 0.5)) end
  local info = C_Map and C_Map.GetMapInfo and ns.Call(C_Map.GetMapInfo, map)
  local zone = info and Plain(info.name) or ("map " .. map)
  return ("%s %.1f, %.1f"):format(zone, x * 100, y * 100)
end

local function SetPin(map, x, y)
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
  if C_Map.CanSetUserWaypointOnMap and not ns.Call(C_Map.CanSetUserWaypointOnMap, map) then return false end
  local point = ns.Call(UiMapPoint.CreateFromCoordinates, map, x, y)
  if not point then return false end
  local ok = ns.Call(C_Map.SetUserWaypoint, point)
  if ok ~= false and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
    ns.Call(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end
  return ok ~= false
end

-- Transport ------------------------------------------------------------------

local function Channel()
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

-- Token bucket: 4 sends in a burst, one more every 1.5 s.
local bucket = { tokens = 4, max = 4, rate = 1 / 1.5, last = 0 }
local function TakeToken()
  local now = GetTime()
  bucket.tokens = math.min(bucket.max, bucket.tokens + (now - bucket.last) * bucket.rate)
  bucket.last = now
  if bucket.tokens < 1 then return false end
  bucket.tokens = bucket.tokens - 1
  return true
end

local resultNames = {}
if Enum and Enum.SendAddonMessageResult then
  for k, v in pairs(Enum.SendAddonMessageResult) do resultNames[v] = k end
end

local registered = false
local function Register()
  if registered then return true end
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return false end
  local r = ns.Call(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  -- 0 = Success, 1 = DuplicatePrefix (also fine); old clients return true.
  registered = r == true or r == 0 or r == 1
  return registered
end

local function SendRaw(msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "no addon messages" end
  if not Register() then return false, "prefix not registered" end
  local chan = Channel()
  if not chan then return false, "not in a fleet" end
  if C_ChatInfo.InChatMessagingLockdown and ns.Call(C_ChatInfo.InChatMessagingLockdown) == true then
    return false, "fleet comms locked here"
  end
  if #msg > 250 then msg = msg:sub(1, 250) end
  if not TakeToken() then return false, "throttled" end
  local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chan)
  if not ok then return false, "send failed" end
  if r == nil or r == true or r == 0 then return true end
  if r == false then return false, "send failed" end
  return false, (resultNames[r] or tostring(r))
end

-- Building and applying broadcasts ------------------------------------------

local function Clean(s)
  s = tostring(s or ""):gsub("[%^|\n\r]", "")
  return s:sub(1, 48)
end

-- Fields for an outgoing broadcast, or nil + reason.
local function Fields(d)
  if d.key == "target" or d.key == "enemy" then
    local unit = "target"
    if d.key == "enemy" and UnitExists("mouseover") then unit = "mouseover" end
    if not UnitExists(unit) then return nil, "no " .. (d.key == "enemy" and "target or mouseover" or "target") end
    local guid, name = Plain(UnitGUID(unit)), Plain(UnitName(unit))
    if type(guid) ~= "string" or type(name) ~= "string" then return nil, "target hidden right now" end
    return { guid, Clean(name) }
  elseif d.key == "align" then
    local map, x, y = MyMapPos()
    if not map then return nil, "position unavailable here" end
    return { tostring(map), ("%.4f"):format(x), ("%.4f"):format(y) }
  end
  return {}
end

local history = {}
local UI = {}

local function Describe(d, f)
  if d.key == "target" or d.key == "enemy" then return d.label .. ": " .. (f[2] or "?") end
  if d.key == "align" then
    local map, x, y = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
    if map and x and y then return "Align to " .. BearingText(map, x, y) end
  end
  return d.label
end

-- Apply a broadcast (incoming or our own) to tags, history and toast.
local function Apply(d, f, from, own)
  if d.tag == "target" or d.tag == "enemy" then
    Tag(f[1], d.tag, from)
  elseif d.tag == "heal" or d.tag == "mana" then
    local u = UnitByName(from)
    local guid = u and Plain(UnitGUID(u))
    if guid then Tag(guid, d.tag, from) end
  elseif d.key == "clear" then
    ClearTagsFrom(from)
  end
  local entry = { d = d, f = f, from = from, own = own, time = time(), text = Describe(d, f) }
  if d.key == "align" and not own then
    local map, x, y = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
    if map and x and y and EveUIDB.broadcasts.pin ~= false then entry.pinned = SetPin(map, x, y) end
  end
  table.insert(history, 1, entry)
  while #history > HISTORY_MAX do table.remove(history) end
  if UI.Refresh then UI.Refresh() end
  if UI.Toast and not own then UI.Toast(entry) end
end

local lastSend = {}
function ns.Broadcast(kind)
  kind = tostring(kind or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local d = byKey[kind] or byKey[ALIAS[kind] or ""] or byCode[kind:upper()]
  if not d then
    ns.Print("broadcasts: target | shield | cap | position | hold | align | enemy | jump | clear")
    return false
  end
  local now = GetTime()
  if lastSend[d.key] and now - lastSend[d.key] < 1 then return false end
  local f, why = Fields(d)
  if not f then ns.Print("broadcast " .. d.label .. ": " .. why); return false end
  local parts = { VERSION, d.code }
  for _, v in ipairs(f) do parts[#parts + 1] = v end
  local ok, err = SendRaw(table.concat(parts, SEP))
  if not ok then ns.Print("broadcast " .. d.label .. ": " .. err); return false end
  lastSend[d.key] = now
  Apply(d, f, MyName(), true)
  return true
end

-- "/eve bc [kind]": no kind toggles the history list.
function ns.BroadcastCommand(arg)
  if not arg or arg == "" then
    if UI.ToggleHistory then UI.ToggleHistory() end
  else
    ns.Broadcast(arg)
  end
end

local function Split(s)
  local out = {}
  for part in (s .. SEP):gmatch("(.-)%" .. SEP) do out[#out + 1] = part end
  return out
end

local lastFrom = {}
local function OnAddonMessage(prefix, text, channel, sender)
  if issecret(prefix) or issecret(text) or issecret(sender) then return end
  if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
  if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
  local from = Short(sender)
  if from == MyName() or sender == MyName() then return end
  local parts = Split(text)
  if parts[1] ~= VERSION then return end
  local d = byCode[parts[2] or ""]
  if not d then return end
  -- Flood guard: one message per sender per 0.3 s.
  local now = GetTime()
  if lastFrom[from] and now - lastFrom[from] < 0.3 then return end
  lastFrom[from] = now
  local f = {}
  for i = 3, #parts do f[#f + 1] = parts[i] end
  if (d.key == "target" or d.key == "enemy") and not (f[1] and f[1]:match("^%a[%w%-]+$")) then return end
  Apply(d, f, from, false)
end

-- UI -------------------------------------------------------------------------

ns.RegisterModule(function()
  EveUIDB.broadcasts = EveUIDB.broadcasts or {}
  local cfg = EveUIDB.broadcasts
  if cfg.pin == nil then cfg.pin = true end

  Register()

  local n = #KINDS
  local bar = ns.CreatePanel("EveUIBroadcasts", ns.root, nil, n * (BTN_W + 2) + 2, BTN_H + 4)
  bar:EnableMouse(true)
  bar:SetFrameStrata("MEDIUM")
  ns.broadcastBar = bar

  for i, k in ipairs(KINDS) do
    local d = byCode[k[1]]
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(BTN_W, BTN_H)
    b:SetPoint("LEFT", 2 + (i - 1) * (BTN_W + 2), 0)
    ns.Box(b, C.header, C.line)
    local tick = b:CreateTexture(nil, "ARTWORK")
    tick:SetColorTexture(unpack(Color(d)))
    tick:SetPoint("BOTTOMLEFT", 1, 1); tick:SetPoint("BOTTOMRIGHT", -1, 1)
    tick:SetHeight(2)
    b.text = ns.Text(b, 10, C.text, "CENTER")
    b.text:SetFont(ns.FONT_BOLD, 10, "")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText(d.short)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() ns.Broadcast(d.key) end)
    b:SetScript("OnEnter", function(s)
      ns.SetBoxBorder(s, C.accent)
      GameTooltip:SetOwner(s, "ANCHOR_TOP")
      GameTooltip:AddLine(d.label:upper(), unpack(Color(d)))
      if d.key == "target" then GameTooltip:AddLine("Broadcast your current target.", 1, 1, 1)
      elseif d.key == "enemy" then GameTooltip:AddLine("Broadcast your mouseover or target.", 1, 1, 1)
      elseif d.key == "align" then GameTooltip:AddLine("Broadcast your position.", 1, 1, 1) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(s) ns.SetBoxBorder(s, C.line); GameTooltip:Hide() end)
  end

  -- History list, hanging above the bar.
  local W = math.max(bar:GetWidth(), 280)
  local hist = ns.CreatePanel("EveUIBroadcastHistory", bar, "Fleet broadcasts", W, ns.HEADER + VISIBLE_ROWS * ROW_H + 6)
  hist:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
  hist:EnableMouse(true)
  hist:EnableMouseWheel(true)
  local offset = 0
  local rows = {}
  for i = 1, VISIBLE_ROWS do
    local r = CreateFrame("Button", nil, hist)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 4, -(ns.HEADER + 3 + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", -4, -(ns.HEADER + 3 + (i - 1) * ROW_H))
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0)
    r.tick = r:CreateTexture(nil, "ARTWORK")
    r.tick:SetPoint("TOPLEFT", 0, -2); r.tick:SetPoint("BOTTOMLEFT", 0, 2); r.tick:SetWidth(2)
    r.time = ns.Text(r, 10, C.dim, "LEFT")
    r.time:SetPoint("LEFT", 5, 0); r.time:SetWidth(46)
    r.from = ns.Text(r, 11, C.text, "LEFT")
    r.from:SetPoint("LEFT", 52, 0); r.from:SetWidth(78)
    r.text = ns.Text(r, 11, C.text, "LEFT")
    r.text:SetPoint("LEFT", 132, 0); r.text:SetPoint("RIGHT", -2, 0)
    r:SetScript("OnEnter", function(s)
      if s.entry then s.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10) end
    end)
    r:SetScript("OnLeave", function(s)
      if not s.flash then s.hl:SetColorTexture(1, 1, 1, 0) end
    end)
    r:SetScript("OnClick", function(s)
      local e = s.entry
      if not e then return end
      if e.d.tag == "target" or e.d.tag == "enemy" then
        -- Highlight only: refresh the tag so brackets show it again.
        ns.fleetHighlight = e.f[1]
        Tag(e.f[1], e.d.tag, e.from)
      elseif e.d.key == "align" then
        local map, x, y = tonumber(e.f[1]), tonumber(e.f[2]), tonumber(e.f[3])
        if map and x and y then
          SetPin(map, x, y)
          ns.Print("align: " .. BearingText(map, x, y))
        end
      end
      s.flash = GetTime()
      s.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.25)
      C_Timer.After(0.6, function()
        if s.flash and GetTime() - s.flash >= 0.55 then s.flash = nil; s.hl:SetColorTexture(1, 1, 1, 0) end
      end)
    end)
    rows[i] = r
  end
  local empty = ns.Text(hist, 11, C.dim, "CENTER")
  empty:SetPoint("CENTER", 0, -ns.HEADER / 2)
  empty:SetText("No broadcasts")

  function UI.Refresh()
    offset = math.max(0, math.min(offset, #history - VISIBLE_ROWS))
    for i, r in ipairs(rows) do
      local e = history[i + offset]
      r.entry = e
      if e then
        r:Show()
        r.time:SetText(date("%H:%M:%S", e.time))
        local fc = e.own and ns.ClassColor("player") or NameColor(e.from)
        r.from:SetText(e.from)
        r.from:SetTextColor(unpack(fc))
        r.text:SetText(e.text)
        r.text:SetTextColor(unpack(Color(e.d)))
        r.tick:SetColorTexture(unpack(Color(e.d)))
      else
        r:Hide()
      end
    end
    empty:SetShown(#history == 0)
  end
  hist:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta
    UI.Refresh()
  end)

  function UI.ToggleHistory()
    cfg.collapsed = not cfg.collapsed
    hist:SetShown(not cfg.collapsed)
  end
  local collapse = CreateFrame("Button", nil, hist)
  collapse:SetSize(ns.HEADER, ns.HEADER)
  collapse:SetPoint("TOPRIGHT", 0, 0)
  collapse.text = ns.Text(collapse, 12, C.dim, "CENTER")
  collapse.text:SetAllPoints()
  collapse.text:SetText("-")
  collapse:SetScript("OnClick", UI.ToggleHistory)
  hist:SetShown(not cfg.collapsed)

  -- Right-click the bar to bring the history back.
  bar:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then UI.ToggleHistory() end end)

  -- Toast.
  local toast = CreateFrame("Frame", "EveUIBroadcastToast", ns.root)
  toast:SetSize(360, 30)
  toast:SetPoint("TOP", ns.root, "TOP", 0, -170)
  toast:SetFrameStrata("HIGH")
  ns.Box(toast, C.panel, C.border)
  toast.mark = toast:CreateTexture(nil, "ARTWORK")
  toast.mark:SetPoint("TOPLEFT", 1, -1); toast.mark:SetPoint("BOTTOMLEFT", 1, 1); toast.mark:SetWidth(3)
  toast.text = ns.Text(toast, 13, C.title, "CENTER")
  toast.text:SetFont(ns.FONT_BOLD, 13, "")
  toast.text:SetPoint("LEFT", 10, 0); toast.text:SetPoint("RIGHT", -10, 0)
  toast:Hide()
  local shownAt = 0
  toast:SetScript("OnUpdate", function(s)
    local age = GetTime() - shownAt
    if age > 4 then s:Hide() elseif age > 3 then s:SetAlpha(4 - age) else s:SetAlpha(1) end
  end)
  function UI.Toast(e)
    local c = Color(e.d)
    toast.mark:SetColorTexture(unpack(c))
    toast.text:SetText(Hex(NameColor(e.from)) .. e.from .. "|r  " .. Hex(c) .. e.text:upper() .. "|r")
    shownAt = GetTime()
    toast:SetAlpha(1)
    toast:Show()
  end

  -- Shown in groups, or while frames are unlocked.
  local unlocked = false
  local function UpdateShown()
    bar:SetShown(unlocked or IsInGroup())
  end
  ns.Mover(bar, { key = "broadcasts", label = "Broadcasts", point = "BOTTOMLEFT", x = 16, y = 260,
    onUnlock = function(u) unlocked = u; UpdateShown() end })

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("CHAT_MSG_ADDON")
  ev:RegisterEvent("GROUP_ROSTER_UPDATE")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:SetScript("OnEvent", ns.Safe("broadcasts", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
      OnAddonMessage(...)
    else
      UpdateShown()
      UI.Refresh()
    end
  end))

  ns.Every(5, "broadcast tags", ExpireTags)
  UpdateShown()
  UI.Refresh()
end, "broadcasts")
