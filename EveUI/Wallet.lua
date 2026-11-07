local ADDON, ns = ...
-- Wallet window: gold history as an EVE wallet. Money is sampled on every
-- change into EveUIDB.chars[...].wallet (about 2000 points; old points are
-- thinned out), drawn as a line graph over 24 hours, 7 days or all time.
-- Changes are tagged with a source from what was open or just happened
-- (loot, quest, vendor, repairs, mail, auction, trainer, flight, other) and
-- summed for this session and all time. Amounts show as "12g 34s 56c" or,
-- toggled, as a copper total in "1,234,567 ISK" style.

local C = ns.C
local Plain = ns.Plain

local W, H = 480, 470
local GRAPH_H, BUCKETS = 150, 120
local MAX_POINTS = 2000
local RANGES = { { "24H", 86400 }, { "7D", 7 * 86400 }, { "ALL", nil } }
local SOURCES = {
  { "loot", "Loot" }, { "quest", "Quests" }, { "vendor", "Vendor" }, { "repair", "Repairs" },
  { "mail", "Mail" }, { "auction", "Auction" }, { "trainer", "Trainer" }, { "taxi", "Flights" },
  { "trade", "Trade" }, { "other", "Other" },
}

local function Commas(n)
  local s = tostring(math.floor(math.abs(n)))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end

ns.RegisterModule(function()
  local l = ns.Layout()
  l.wallet = l.wallet or {}
  local db = l.wallet
  db.points = db.points or {}  -- { time(), copper }
  db.src = db.src or {}        -- all time: [key] = { in, out }
  db.range = db.range or 1

  local function Money(c, sign)
    c = Plain(c)
    if type(c) ~= "number" then return "-" end
    local neg = c < 0
    c = math.abs(math.floor(c + 0.5))
    local pre = neg and "-" or (sign and c > 0 and "+" or "")
    if db.isk then return pre .. Commas(c) .. " ISK" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local dim = "|cff808a90"
    if g > 0 then return ("%s%s%sg|r %d%ss|r %d%sc|r"):format(pre, Commas(g), dim, s, dim, cp, dim) end
    if s > 0 then return ("%s%d%ss|r %d%sc|r"):format(pre, s, dim, cp, dim) end
    return ("%s%d%sc|r"):format(pre, cp, dim)
  end

  -- Sampling -------------------------------------------------------------------
  local function Thin()
    local p = db.points
    if #p <= MAX_POINTS then return end
    -- Keep every other point among the oldest half.
    local keep, half = {}, math.floor(#p / 2)
    for i = 1, half do if i % 2 == 1 or i == half then keep[#keep + 1] = p[i] end end
    for i = half + 1, #p do keep[#keep + 1] = p[i] end
    db.points = keep
  end

  local function Add(money)
    local p = db.points
    local tail = p[#p]
    if tail and tail[2] == money then return end
    p[#p + 1] = { time(), money }
    Thin()
  end

  local money = Plain(GetMoney())
  if money then Add(money) end

  -- Sources ------------------------------------------------------------------------
  local session = {}
  local sIn, sOut = 0, 0
  local open = {}              -- window context: merchant, mail, ...
  local pending = {}           -- [key] = GetTime() of a hint (loot, quest)
  local lastChange             -- { delta, key, t }
  local repairCost = 0

  local function Book(key, delta, sign)
    local t = session[key] or { 0, 0 }
    session[key] = t
    local a = db.src[key] or { 0, 0 }
    db.src[key] = a
    local i = delta > 0 and 1 or 2
    t[i] = t[i] + sign * math.abs(delta)
    a[i] = a[i] + sign * math.abs(delta)
  end

  local function Recent(key) return pending[key] and GetTime() - pending[key] < 2 end

  local function Classify(delta)
    if Recent("quest") and delta > 0 then return "quest" end
    if (Recent("loot") or open.loot) and delta > 0 then return "loot" end
    if open.merchant then
      if delta < 0 then
        local now = Plain(ns.Call(GetRepairAllCost)) or 0
        if -delta == repairCost or (repairCost > 0 and now < repairCost) then return "repair" end
      end
      return "vendor"
    end
    for _, k in ipairs({ "mail", "auction", "trainer", "taxi", "trade" }) do
      if open[k] then return k end
    end
    return "other"
  end

  local dirty = true
  local function OnMoney()
    local now = Plain(GetMoney())
    if not now then return end
    if money then
      local delta = now - money
      if delta ~= 0 then
        local key = Classify(delta)
        Book(key, delta, 1)
        if delta > 0 then sIn = sIn + delta else sOut = sOut - delta end
        lastChange = { delta, key, GetTime() }
        if open.merchant then
          C_Timer.After(1, function() repairCost = Plain(ns.Call(GetRepairAllCost)) or 0 end)
        end
      end
    end
    money = now
    Add(now)
    dirty = true
  end

  -- A late hint (loot or quest message after the money change) moves the last
  -- untagged change to that source.
  local function Retag(key)
    local c = lastChange
    if c and c[2] == "other" and c[1] > 0 and GetTime() - c[3] < 2 then
      Book("other", c[1], -1)
      Book(key, c[1], 1)
      c[2] = key
      dirty = true
    else
      pending[key] = GetTime()
    end
  end

  local OPEN = {
    MERCHANT_SHOW = "merchant", MERCHANT_CLOSED = "merchant", MAIL_SHOW = "mail", MAIL_CLOSED = "mail",
    AUCTION_HOUSE_SHOW = "auction", AUCTION_HOUSE_CLOSED = "auction", TRAINER_SHOW = "trainer",
    TRAINER_CLOSED = "trainer", TAXIMAP_OPENED = "taxi", TAXIMAP_CLOSED = "taxi", TRADE_SHOW = "trade",
    TRADE_CLOSED = "trade", LOOT_OPENED = "loot", LOOT_CLOSED = "loot",
  }
  local ev = CreateFrame("Frame")
  pcall(ev.RegisterEvent, ev, "PLAYER_MONEY")
  pcall(ev.RegisterEvent, ev, "CHAT_MSG_MONEY")
  pcall(ev.RegisterEvent, ev, "QUEST_TURNED_IN")
  for e in pairs(OPEN) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript("OnEvent", ns.Safe("wallet", function(_, e, a1, a2, a3)
    if e == "PLAYER_MONEY" then
      OnMoney()
    elseif e == "CHAT_MSG_MONEY" then
      Retag("loot")
    elseif e == "QUEST_TURNED_IN" then
      local m = Plain(a3)
      if type(m) == "number" and m > 0 then Retag("quest") end
    elseif OPEN[e] then
      local k = OPEN[e]
      local opening = e:find("SHOW", 1, true) or e:find("OPENED", 1, true)
      if k == "loot" and not opening then
        -- Auto-loot money can land just after the window closes.
        open.loot = nil
        pending.loot = GetTime()
      else
        open[k] = opening and true or nil
      end
      if e == "MERCHANT_SHOW" then repairCost = Plain(ns.Call(GetRepairAllCost)) or 0 end
    end
  end))

  -- Window ---------------------------------------------------------------------------
  local f = ns.CreatePanel("EveUIWallet", ns.root, "Wallet", W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); ns.SavePos(s) end)
  f:Hide()
  tinsert(UISpecialFrames, "EveUIWallet")

  local close = CreateFrame("Button", nil, f)
  close:SetSize(ns.HEADER - 4, ns.HEADER - 4)
  close:SetPoint("TOPRIGHT", -2, -2)
  local x = ns.Text(close, 14, C.dim)
  x:SetPoint("CENTER", 0, 1)
  x:SetText("×")
  close:SetScript("OnEnter", function() x:SetTextColor(unpack(C.hostile)) end)
  close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.dim)) end)
  close:SetScript("OnClick", function() f:Hide() end)

  local function TextButton(text, w)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(w, 16)
    b.text = ns.Text(b, 10, C.dim)
    b.text:SetAllPoints()
    b.text:SetText(text)
    ns.Box(b, { 0.05, 0.07, 0.09, 0.8 }, C.line)
    b:SetScript("OnEnter", function(s) s.text:SetTextColor(unpack(C.accent)) end)
    b:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(s.on and C.title or C.dim)) end)
    function b:SetOn(on)
      self.on = on
      self.text:SetTextColor(unpack(on and C.title or C.dim))
      ns.SetBoxBorder(self, on and C.accent or C.line)
    end
    return b
  end

  local iskB = TextButton("ISK", 36)
  iskB:SetPoint("TOPRIGHT", -26, -3)
  iskB:SetScript("OnClick", function(s) db.isk = not db.isk or nil; s:SetOn(db.isk); dirty = true end)
  iskB:SetOn(db.isk)

  local balLabel = ns.Text(f, 10, C.accent, "LEFT")
  balLabel:SetPoint("TOPLEFT", 12, -(ns.HEADER + 10))
  balLabel:SetText("BALANCE")
  local balance = ns.Text(f, 20, C.title, "LEFT")
  balance:SetFont(ns.FONT_BOLD, 20, "")
  balance:SetPoint("TOPLEFT", balLabel, "BOTTOMLEFT", 0, -3)

  local rangeB = {}
  for i = #RANGES, 1, -1 do
    local b = TextButton(RANGES[i][1], 38)
    if i == #RANGES then b:SetPoint("TOPRIGHT", -12, -(ns.HEADER + 26))
    else b:SetPoint("RIGHT", rangeB[i + 1], "LEFT", -4, 0) end
    b:SetScript("OnClick", function() db.range = i; dirty = true end)
    rangeB[i] = b
  end

  -- Graph.
  local g = CreateFrame("Frame", nil, f)
  g:SetPoint("TOPLEFT", 12, -(ns.HEADER + 50))
  g:SetPoint("TOPRIGHT", -12, -(ns.HEADER + 50))
  g:SetHeight(GRAPH_H)
  ns.Box(g, { 0.02, 0.03, 0.04, 0.85 }, C.line)
  for i = 1, 3 do
    local t = g:CreateTexture(nil, "BORDER")
    t:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.18)
    t:SetPoint("TOPLEFT", 1, -GRAPH_H * i / 4)
    t:SetPoint("TOPRIGHT", -1, -GRAPH_H * i / 4)
    t:SetHeight(1)
  end
  local yMax = ns.Text(g, 10, C.dim, "LEFT")
  yMax:SetPoint("TOPLEFT", 4, -3)
  local yMin = ns.Text(g, 10, C.dim, "LEFT")
  yMin:SetPoint("BOTTOMLEFT", 4, 3)
  local xFrom = ns.Text(f, 10, C.dim, "LEFT")
  xFrom:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -3)
  local xTo = ns.Text(f, 10, C.dim, "RIGHT")
  xTo:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", 0, -3)
  xTo:SetText("now")
  local change = ns.Text(f, 10, C.text)
  change:SetPoint("TOP", g, "BOTTOM", 0, -3)
  local noData = ns.Text(g, 11, C.dim)
  noData:SetPoint("CENTER")
  noData:SetText("Not enough history yet.")

  local lines, fills = {}, {}
  for i = 1, BUCKETS do
    local ln = g:CreateLine(nil, "ARTWORK")
    ln:SetThickness(1.5)
    ln:SetColorTexture(unpack(C.accent))
    lines[i] = ln
    local fl = g:CreateTexture(nil, "BORDER", nil, 1)
    fl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
    fills[i] = fl
  end
  local dot = g:CreateTexture(nil, "OVERLAY")
  dot:SetTexture(ns.CIRCLE)
  dot:SetSize(5, 5)
  dot:SetVertexColor(unpack(C.title))

  -- Value at time t: the last point at or before t (or the first point).
  local function Series(from, to)
    local p = db.points
    local out, j = {}, 1
    local v = p[1][2]
    for i = 0, BUCKETS do
      local t = from + (to - from) * i / BUCKETS
      while j <= #p and p[j][1] <= t do v = p[j][2]; j = j + 1 end
      out[i] = v
    end
    return out
  end

  local function DrawGraph()
    local p = db.points
    local now = time()
    local span = RANGES[db.range][2]
    for i, b in ipairs(rangeB) do b:SetOn(i == db.range) end
    if #p == 0 then
      noData:Show(); dot:Hide()
      for i = 1, BUCKETS do lines[i]:Hide(); fills[i]:Hide() end
      return
    end
    local from = span and (now - span) or p[1][1]
    if now - from < 60 then from = now - 60 end
    local s = Series(from, now)
    local lo, hi = s[0], s[0]
    for i = 1, BUCKETS do lo = math.min(lo, s[i]); hi = math.max(hi, s[i]) end
    local pad = math.max((hi - lo) * 0.1, 100)
    local bottom, top = math.max(lo - pad, 0), hi + pad
    local gw, gh = g:GetWidth() - 2, GRAPH_H - 2
    local function Y(v) return 1 + (v - bottom) / (top - bottom) * (gh - 4) + 2 end
    noData:SetShown(#p < 2)
    for i = 1, BUCKETS do
      local x1, x2 = 1 + gw * (i - 1) / BUCKETS, 1 + gw * i / BUCKETS
      local ln = lines[i]
      ln:SetStartPoint("BOTTOMLEFT", g, x1, Y(s[i - 1]))
      ln:SetEndPoint("BOTTOMLEFT", g, x2, Y(s[i]))
      ln:Show()
      local fl = fills[i]
      fl:ClearAllPoints()
      fl:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", x1, 1)
      fl:SetSize(math.max(x2 - x1, 1), math.max(Y(math.min(s[i - 1], s[i])) - 1, 1))
      fl:Show()
    end
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", g, "BOTTOMLEFT", 1 + gw, Y(s[BUCKETS]))
    dot:Show()
    yMax:SetText(Money(top))
    yMin:SetText(Money(bottom))
    local secs = now - from
    xFrom:SetText(secs >= 86400 and ("-%dd"):format(math.floor(secs / 86400 + 0.5))
      or ("-%dh"):format(math.max(1, math.floor(secs / 3600 + 0.5))))
    local d = s[BUCKETS] - s[0]
    change:SetText("Change " .. Money(d, true))
    change:SetTextColor(unpack(d > 0 and C.heal or (d < 0 and C.hostile or C.dim)))
  end

  -- Session and source table.
  local y = -(ns.HEADER + 50 + GRAPH_H + 22)
  local sHead = ns.Text(f, 10, C.accent, "LEFT")
  sHead:SetPoint("TOPLEFT", 12, y)
  sHead:SetText("THIS SESSION")
  local function Pair(label, yy, color)
    local a = ns.Text(f, 11, C.text, "LEFT")
    a:SetPoint("TOPLEFT", 12, yy)
    a:SetText(label)
    local v = ns.Text(f, 11, color or C.title, "RIGHT")
    v:SetPoint("TOPLEFT", 80, yy)
    v:SetWidth(120)
    return v
  end
  local vIn = Pair("Income", y - 16, C.heal)
  local vOut = Pair("Expenses", y - 32, C.hostile)
  local vNet = Pair("Net", y - 48)

  local tHead = ns.Text(f, 10, C.accent, "LEFT")
  tHead:SetPoint("TOPLEFT", 220, y)
  tHead:SetText("SOURCES")
  local cS = ns.Text(f, 10, C.dim, "RIGHT")
  cS:SetPoint("TOPRIGHT", -112, y)
  cS:SetText("SESSION")
  local cA = ns.Text(f, 10, C.dim, "RIGHT")
  cA:SetPoint("TOPRIGHT", -12, y)
  cA:SetText("ALL TIME")
  local srcRows = {}
  for i = 1, #SOURCES do
    local yy = y - 4 - i * 15
    local r = {}
    r.label = ns.Text(f, 11, C.text, "LEFT")
    r.label:SetPoint("TOPLEFT", 220, yy)
    r.s = ns.Text(f, 11, C.title, "RIGHT")
    r.s:SetPoint("TOPRIGHT", -112, yy)
    r.a = ns.Text(f, 11, C.dim, "RIGHT")
    r.a:SetPoint("TOPRIGHT", -12, yy)
    srcRows[i] = r
  end

  local function Net(t) return t and (t[1] - t[2]) or nil end

  local function DrawTable()
    vIn:SetText(Money(sIn))
    vOut:SetText(Money(-sOut))
    vNet:SetText(Money(sIn - sOut, true))
    local row = 0
    for _, src in ipairs(SOURCES) do
      local s, a = session[src[1]], db.src[src[1]]
      if s or a then
        row = row + 1
        local r = srcRows[row]
        r.label:SetText(src[2])
        r.s:SetText(s and Money(Net(s), true) or "-")
        r.a:SetText(a and Money(Net(a), true) or "-")
        r.label:Show(); r.s:Show(); r.a:Show()
      end
    end
    for i = row + 1, #srcRows do
      local r = srcRows[i]
      r.label:Hide(); r.s:Hide(); r.a:Hide()
    end
    if row == 0 then
      local r = srcRows[1]
      r.label:SetText("No changes recorded yet.")
      r.label:SetTextColor(unpack(C.dim))
      r.label:Show()
    else
      srcRows[1].label:SetTextColor(unpack(C.text))
    end
  end

  local function Redraw()
    balance:SetText(Money(money))
    DrawGraph()
    DrawTable()
  end

  f:SetScript("OnShow", function() dirty = true end)
  f:SetScript("OnSizeChanged", function() dirty = true end)
  local tick = 0
  ns.Every(1, "wallet", function()
    tick = tick + 1
    if not f:IsShown() then return end
    if dirty or tick % 30 == 0 then dirty = false; Redraw() end
  end)

  ns.Mover(f, { key = "wallet", label = "Wallet", point = "CENTER", x = 40, y = 20 })

  function ns.ToggleWallet()
    f:SetShown(not f:IsShown())
  end
end, "wallet")
