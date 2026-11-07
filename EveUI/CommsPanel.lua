-- Fleet comms: shows the AI combat coach's debrief of the last long fight.
-- The pilot service writes the tips to Comms.lua (EveUIComms), which the game
-- loads on /reload. Click the title bar to collapse; hidden when there are none.
local ADDON, ns = ...
local C = ns.C

local W, PAD, GAP = 300, 10, 6

local function Clock(sec)
  if type(sec) ~= "number" or sec < 0 then return "" end
  sec = math.floor(sec + 0.5)
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function Ago(t)
  if type(t) ~= "number" or not time then return "" end
  local d = time() - t
  if d < 60 then return "just now" end
  if d < 3600 then return ("%d min ago"):format(math.floor(d / 60)) end
  if d < 86400 then return ("%d h ago"):format(math.floor(d / 3600)) end
  return ("%d d ago"):format(math.floor(d / 86400))
end

local function Data()
  local d = EveUIComms
  if type(d) ~= "table" or type(d.tips) ~= "table" then return nil end
  local tips = {}
  for _, t in ipairs(d.tips) do
    if type(t) == "string" and t ~= "" then tips[#tips + 1] = t end
  end
  if #tips == 0 then return nil end
  return d, tips
end

ns.RegisterModule(function()
  local f = ns.CreatePanel("EveUICommsPanel", ns.root, "Fleet comms", W, 80)
  f:SetFrameStrata("LOW")
  f:Hide()

  local toggle = CreateFrame("Button", nil, f)
  toggle:SetPoint("TOPLEFT", 1, -1)
  toggle:SetPoint("TOPRIGHT", -1, -1)
  toggle:SetHeight(ns.HEADER - 1)
  local sign = ns.Text(toggle, 12, C.dim, "RIGHT")
  sign:SetPoint("RIGHT", -8, 0)

  local sub = ns.Text(f, 10, C.dim, "LEFT")
  sub:SetPoint("TOPLEFT", PAD, -(ns.HEADER + 6))
  sub:SetPoint("TOPRIGHT", -PAD, -(ns.HEADER + 6))

  local head = ns.Text(f, 12, C.accent, "LEFT")
  head:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -4)
  head:SetWidth(W - 2 * PAD)
  if head.SetWordWrap then head:SetWordWrap(true) end

  local rows = {}
  local function Row(i)
    local r = rows[i]
    if r then return r end
    r = {}
    r.mark = f:CreateTexture(nil, "ARTWORK")
    r.mark:SetColorTexture(unpack(C.accent))
    r.mark:SetSize(4, 4)
    r.text = ns.Text(f, 11, C.text, "LEFT")
    r.text:SetWidth(W - 2 * PAD - 10)
    if r.text.SetWordWrap then r.text:SetWordWrap(true) end
    if r.text.SetJustifyV then r.text:SetJustifyV("TOP") end
    rows[i] = r
    return r
  end

  local function Collapsed() return EveUIDB.commsCollapsed and true or false end

  local function Refresh()
    local d, tips = Data()
    if not d then f:Hide(); return end
    f:Show()
    local fight = type(d.fight) == "string" and d.fight or "Last engagement"
    sub:SetText(("%s  -  %s%s  -  %s"):format(fight:upper(), Clock(d.duration),
      type(d.dps) == "number" and ("  -  %d dps"):format(math.floor(d.dps + 0.5)) or "", Ago(d.generated)))
    local collapsed = Collapsed()
    sign:SetText(collapsed and ("+ " .. #tips) or "-")
    local h = ns.HEADER + 6 + sub:GetStringHeight() + 6
    if collapsed then
      head:Hide()
      for _, r in ipairs(rows) do r.mark:Hide(); r.text:Hide() end
      f:SetHeight(h)
      return
    end
    local anchor, y = sub, -4
    if type(d.headline) == "string" and d.headline ~= "" then
      head:SetText(d.headline)
      head:Show()
      h = h + head:GetStringHeight() + 4
      anchor, y = head, -GAP
    else
      head:Hide()
    end
    for i, tip in ipairs(tips) do
      local r = Row(i)
      r.text:ClearAllPoints()
      r.text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", i == 1 and (anchor == sub or anchor == head) and 10 or 0, y)
      r.text:SetText(tip)
      r.text:Show()
      r.mark:ClearAllPoints()
      r.mark:SetPoint("TOPRIGHT", r.text, "TOPLEFT", -5, -4)
      r.mark:Show()
      h = h + r.text:GetStringHeight() + GAP
      anchor, y = r.text, -GAP
    end
    for i = #tips + 1, #rows do rows[i].mark:Hide(); rows[i].text:Hide() end
    f:SetHeight(math.floor(h + PAD))
  end

  toggle:SetScript("OnClick", function()
    EveUIDB.commsCollapsed = not Collapsed() or nil
    Refresh()
  end)
  toggle:SetScript("OnEnter", function() sign:SetTextColor(unpack(C.accent)) end)
  toggle:SetScript("OnLeave", function() sign:SetTextColor(unpack(C.dim)) end)

  ns.Mover(f, { key = "comms", label = "Fleet comms", point = "LEFT", x = 16, y = 140 })
  ns.Every(30, "comms", Refresh)
end, "comms")
