-- Cast display in the style of an EVE module cycle: a segmented ring that
-- fills over the cast (amber), drains over a channel (cyan), turns steel with
-- a LOCKED tag when the cast cannot be interrupted, flashes cyan-white on
-- success and blinks red on an interrupt. A bright lead segment marks the
-- current point of the cycle.
--
-- When the game hides cast times (secret values) the ring follows the cast's
-- duration object and a thin timer bar driven by the game (SetTimerDuration,
-- elapsed for casts, remaining for channels) shows progress.
local ADDON, ns = ...
local C = ns.C

local STEEL = { 0.62, 0.70, 0.76, 1 }
local SUCCESS = { 0.80, 0.97, 1.00, 1 }
local LEAD = { 1, 1, 1, 1 }

local EVENTS = {
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
  "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local DIR = Enum and Enum.StatusBarTimerDirection
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

-- Game-driven timer bar: casts count up (fill), channels count down (drain).
function ns.SetTimer(bar, dur, channel)
  if not (bar.SetTimerDuration and dur) then return false end
  if bar.SetReverseFill then bar:SetReverseFill(false) end
  local dir = DIR and (channel and DIR.RemainingTime or DIR.ElapsedTime)
  if dir and pcall(bar.SetTimerDuration, bar, dur, INTERP, dir) then return true end
  return pcall(bar.SetTimerDuration, bar, dur) and true or false
end

-- Plain 0..1 elapsed fraction from a duration object, or nil if secret.
local function DurElapsed(dur)
  if not dur then return nil end
  local ok, p = pcall(dur.GetElapsedPercent, dur)
  if not ok or p == nil or ns.issecret(p) or type(p) ~= "number" then return nil end
  if p > 1.001 then p = p / 100 end
  return math.min(math.max(p, 0), 1)
end

-- Last casts with progress samples, so a reversed display shows up in
-- EveUIDB.castTrace and /eve check.
ns.castTrace = {}
local function TraceStart(unit, st, path)
  local rec = { unit = unit, name = ns.Plain(st.name) or "?", channel = st.channel and true or false,
    path = path, t0 = GetTime(), samples = {} }
  local t = ns.castTrace
  t[#t + 1] = rec
  if #t > 12 then table.remove(t, 1) end
  if EveUIDB then EveUIDB.castTrace = t end
  return rec
end

function ns.CastReport()
  local n, bad = 0, {}
  for _, r in ipairs(ns.castTrace) do
    if r.reversed ~= nil then
      n = n + 1
      if r.reversed then bad[#bad + 1] = r.unit .. " " .. r.name end
    end
  end
  return n, bad
end

local function Upper(s)
  if s == nil or ns.issecret(s) then return s end
  return s:upper()
end

-- parent: frame whose CENTER is the ring centre.
-- o: radius, thickness, from, to, segments, textSize
-- Returns the display; place display.text (and display.timer) yourself.
function ns.CreateCast(parent, unit, o)
  local d = CreateFrame("Frame", nil, parent)
  d:SetAllPoints(parent)
  d:Hide()

  local ringOpts = { radius = o.radius, thickness = o.thickness, from = o.from, to = o.to,
    segments = o.segments, gap = o.gap or 2, color = C.cast, off = { 1, 1, 1, 0.07 } }
  local arc = ns.CreateArc(d, ringOpts)

  -- Flash ring: a second, fully lit copy on its own frame so it can fade alone.
  local fl = CreateFrame("Frame", nil, d)
  fl:SetAllPoints(d)
  fl:SetFrameLevel(d:GetFrameLevel() + 2)
  ringOpts.off = { 0, 0, 0, 0 }
  local flash = ns.CreateArc(fl, ringOpts)
  flash:SetValue(1)
  fl:SetAlpha(0)

  d.text = ns.Text(d, o.textSize or 11, C.title)
  d.text:SetWordWrap(false)

  -- Fallback progress bar for secret cast times.
  local tb = CreateFrame("StatusBar", nil, d)
  tb:SetStatusBarTexture(ns.WHITE)
  tb:SetSize(o.barWidth or 120, 2)
  tb:SetPoint("TOP", d.text, "BOTTOM", 0, -3)
  local tbg = tb:CreateTexture(nil, "BACKGROUND")
  tbg:SetAllPoints()
  tbg:SetColorTexture(1, 1, 1, 0.08)
  tb:Hide()
  d.timer = tb

  -- Fade out the whole display after a cycle ends.
  local fade = d:CreateAnimationGroup()
  local fa = fade:CreateAnimation("Alpha")
  fa:SetFromAlpha(1); fa:SetToAlpha(0)
  fade:SetScript("OnFinished", function() d:Hide(); d:SetAlpha(1) end)

  -- Flash: quick in, slower out; `blinks` repeats for interrupts.
  local fg = fl:CreateAnimationGroup()
  local fin = fg:CreateAnimation("Alpha")
  fin:SetFromAlpha(0); fin:SetToAlpha(1); fin:SetDuration(0.06); fin:SetOrder(1)
  local fout = fg:CreateAnimation("Alpha")
  fout:SetFromAlpha(1); fout:SetToAlpha(0); fout:SetDuration(0.3); fout:SetOrder(2)
  fg:SetScript("OnFinished", function() fl:SetAlpha(0) end)

  local st = {}        -- current cycle: s, e, channel, locked, castID, name, manual
  local lead           -- index of the lit lead segment

  local function Color()
    if st.locked then return STEEL end
    return st.channel and C.accent or C.cast
  end

  local function SetLead(i)
    if lead == i then return end
    local c = Color()
    if lead and arc.on[lead] then arc:PaintSegment(lead, c) end
    lead = i
    if i and arc.on[i] then arc:PaintSegment(i, LEAD) end
  end

  local function Paint()
    arc.color = nil
    arc:SetColor(Color())
    lead = nil
    local c = Color()
    tb:SetStatusBarColor(c[1], c[2], c[3])
  end

  local function Label(extra, color)
    local tag = st.locked and "  |cff9eb3c2LOCKED|r" or ""
    if extra then
      d.text:SetText(extra)
      d.text:SetTextColor(unpack(color or C.title))
    else
      d.text:SetTextColor(unpack(C.title))
      local left
      if st.manual then left = st.e - GetTime()
      elseif st.dur then
        local ok, r = pcall(st.dur.GetRemainingDuration, st.dur)
        if ok and type(r) == "number" and not ns.issecret(r) then left = r end
      end
      if left then
        d.text:SetFormattedText("%s  |cff5cc7dc%.1f|r%s", Upper(st.name) or "", math.max(left, 0), tag)
      else
        d.text:SetFormattedText("%s%s", Upper(st.name) or "", tag)
      end
    end
  end

  local function Clear()
    st.active = nil
    SetLead(nil)
    d:SetScript("OnUpdate", nil)
  end

  local function Hide()
    Clear()
    fade:Stop()
    d:Hide()
  end

  -- Elapsed fraction 0..1: start/end times first, then the game's
  -- duration object; nil when both are secret.
  local function Progress()
    local p = DurElapsed(st.dur)
    local m
    if st.manual then m = math.min(math.max((GetTime() - st.s) / (st.e - st.s), 0), 1) end
    return m or p, p, m
  end

  local acc = 0
  local function OnUpdate(_, el)
    acc = acc + (el or 1)
    if acc < 0.03 then return end
    acc = 0
    local p, pd, pm = Progress()
    local shown
    if p then
      shown = st.channel and (1 - p) or p
      arc:SetValue(shown)
      local n = arc.n
      local idx = math.floor(shown * n + 0.5)
      SetLead(idx >= 1 and idx <= n and idx or nil)
    elseif st.dur then
      -- Secret: the game evaluates each segment's step curve.
      local dur, ch = st.dur, st.channel
      arc:SetFrom(function(c)
        if ch then return dur:EvaluateRemainingPercent(c) end
        return dur:EvaluateElapsedPercent(c)
      end)
    end
    local rec = st.trace
    if rec and p and #rec.samples < 8 and GetTime() - (rec.last or 0) >= 0.2 then
      rec.last = GetTime()
      rec.samples[#rec.samples + 1] = string.format("%.2f/%s/%s", shown,
        pd and string.format("%.2f", pd) or "-", pm and string.format("%.2f", pm) or "-")
    end
    Label()
  end

  local function Start(channel)
    local name, s, e, locked, castID, _
    if channel then
      name, _, _, s, e, _, locked = UnitChannelInfo(unit)
    else
      name, _, _, s, e, _, castID, locked = UnitCastingInfo(unit)
    end
    if not ns.issecret(name) and name == nil then return Hide() end
    fade:Stop()
    d:SetAlpha(1)
    st.active, st.channel, st.name, st.castID = true, channel, name, ns.Plain(castID)
    st.locked = ns.Plain(locked) == true
    if channel then st.dur = ns.Call(UnitChannelDuration, unit) else st.dur = ns.Call(UnitCastingDuration, unit) end
    Paint()
    s, e = ns.Plain(s), ns.Plain(e)
    st.manual = (s and e and e > s) and true or nil
    if st.manual then st.s, st.e = s / 1000, e / 1000 end
    if st.manual or DurElapsed(st.dur) then
      tb:Hide()
      st.trace = TraceStart(unit, st, st.manual and "times" or "duration")
    else
      -- Secret times: the ring follows the game's curves and the thin bar
      -- is animated by the game.
      arc:SetValue(0)
      tb:SetShown(ns.SetTimer(tb, st.dur, channel))
      st.trace = TraceStart(unit, st, "secret")
    end
    acc = 1
    d:SetScript("OnUpdate", OnUpdate)
    OnUpdate()
    d:Show()
  end

  -- End of a cycle: success (cyan-white flash) or failure (red blinks).
  local function Finish(ok, text)
    if not st.active then return end
    local rec = st.trace
    if rec and #rec.samples >= 2 then
      local a, b = tonumber(rec.samples[1]:match("^[%d.]+")), tonumber(rec.samples[#rec.samples]:match("^[%d.]+"))
      if a and b and b ~= a then rec.reversed = (b < a) ~= rec.channel end
    end
    st.trace = nil
    Clear()
    tb:Hide()
    local c = ok and SUCCESS or C.hostile
    flash.color = nil
    flash:SetColor(c)
    if ok then
      arc:SetValue(1)
      arc.color = nil
      arc:SetColor(c)
      d.text:SetTextColor(unpack(SUCCESS))
      d.text:SetFormattedText("%s", Upper(st.name) or "")
      fin:SetDuration(0.05); fout:SetDuration(0.3)
      fg:SetLooping("NONE")
      fa:SetStartDelay(0.1); fa:SetDuration(0.3)
    else
      arc.color = nil
      arc:SetColor(C.hostile)
      Label(text or "INTERRUPTED", C.hostile)
      fin:SetDuration(0.05); fout:SetDuration(0.18)
      fa:SetStartDelay(0.45); fa:SetDuration(0.4)
    end
    fg:Stop(); fg:Play()
    if not ok then
      -- Second blink for interrupts.
      C_Timer.After(0.25, function() if not st.active and d:IsShown() then fg:Stop(); fg:Play() end end)
    end
    fade:Stop(); fade:Play()
  end

  local function Refresh()
    Hide()
    if ns.issecret(UnitCastingInfo(unit)) or UnitCastingInfo(unit) ~= nil then return Start(false) end
    if ns.issecret(UnitChannelInfo(unit)) or UnitChannelInfo(unit) ~= nil then return Start(true) end
  end

  local function SameCast(castID)
    castID = ns.Plain(castID)
    return st.castID == nil or castID == nil or castID == st.castID
  end

  local ev = CreateFrame("Frame")
  for _, e in ipairs(EVENTS) do ev:RegisterUnitEvent(e, unit) end
  if unit == "target" then ev:RegisterEvent("PLAYER_TARGET_CHANGED") end
  if unit == "focus" then ev:RegisterEvent("PLAYER_FOCUS_CHANGED") end
  if unit == "pet" then ev:RegisterEvent("UNIT_PET") end
  ev:SetScript("OnEvent", ns.Safe("cast " .. unit, function(_, event, _, castID)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
      Start(false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
      Start(true)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      if st.active and not st.channel and SameCast(castID) then Finish(true) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
      if st.active and SameCast(castID) then Finish(false, "INTERRUPTED") end
    elseif event == "UNIT_SPELLCAST_FAILED" then
      if st.active and not st.channel and SameCast(castID) then Finish(false, "FAILED") end
    elseif event == "UNIT_SPELLCAST_STOP" then
      -- STOP follows SUCCEEDED/INTERRUPTED; anything still active was cancelled.
      if st.active and not st.channel then Finish(false, "CANCELLED") end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
      if st.active and st.channel then
        local p = Progress()
        local done
        if st.manual then done = st.e - GetTime() < 0.25 else done = not p or p > 0.9 end
        if done then Finish(true) else Finish(false, "STOPPED") end
      end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
      if st.active then
        st.locked = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
        Paint()
        Label()
      end
    else
      Refresh()
    end
  end))
  d.Refresh = Refresh

  -- /eve test: cast, channel, locked, success and interrupt previews.
  function d.Test(kind)
    st.active, st.channel, st.locked, st.name = true, kind == "channel", kind == "locked", "Test Module"
    st.castID, st.s, st.e, st.manual, st.dur, st.trace = nil, GetTime(), GetTime() + 2.5, true, nil, nil
    fade:Stop(); d:SetAlpha(1); Paint(); tb:Hide()
    d:SetScript("OnUpdate", OnUpdate)
    d:Show()
    if kind == "interrupt" then C_Timer.After(1.2, function() Finish(false, "INTERRUPTED") end)
    else C_Timer.After(2.5, function() if st.active then Finish(true) end end) end
  end
  return d
end

-- Legacy helper (straight bar), kept for any caller that wants one.
ns.CreateCastBar = function(parent, unit, w, h)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(w, h)
  return holder
end
