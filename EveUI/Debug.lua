-- /eve debug: records the visible top-level frames into EveUIDB.debug, for
-- layout work (read it from SavedVariables after the next /reload).
local ADDON, ns = ...

local function Describe(f)
  local ok, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
  local p, rel, rp, x, y = f:GetPoint(1)
  local relName = rel and rel.GetName and rel:GetName() or tostring(rel)
  return ("%s %s %.0fx%.0f %s>%s:%s %.0f,%.0f scale=%.3f"):format(
    f:GetName() or "?", f:GetObjectType(), ok and w or 0, ok and h or 0,
    tostring(p), tostring(relName), tostring(rp), x or 0, y or 0, f:GetEffectiveScale())
end

function ns.DebugDump()
  local out = {}
  for _, f in ipairs({ UIParent:GetChildren() }) do
    if not (f.IsForbidden and f:IsForbidden()) and f:IsVisible() and f:GetName() then
      out[#out + 1] = Describe(f)
    end
  end
  for _, f in ipairs({ ns.root:GetChildren() }) do
    if f:IsVisible() and f:GetName() then out[#out + 1] = "root: " .. Describe(f) end
  end
  table.sort(out)
  local plates = {}
  if C_NamePlate and C_NamePlate.GetNamePlates then
    for i, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local tok = p.namePlateUnitToken
      plates[#plates + 1] = ("%d %s token=%s unitframe=%s exists=%s"):format(i, tostring(p:GetName()), tostring(tok),
        tostring(p.UnitFrame and p.UnitFrame.unit), tostring(tok and ns.Plain(UnitExists(tok))))
    end
  end
  for i = 1, 5 do plates[#plates + 1] = "nameplate" .. i .. " exists=" .. tostring(ns.Plain(UnitExists("nameplate" .. i))) end
  out[#out + 1] = "plates: " .. table.concat(plates, " | ")
  local regs = {}
  local function Dump(label, f)
    if not f then regs[#regs + 1] = label .. " nil"; return end
    for k, v in pairs(f) do
      if type(v) == "table" and v.GetObjectType then regs[#regs + 1] = label .. "." .. tostring(k) .. "=" .. v:GetObjectType() end
    end
    for i, r in ipairs({ f:GetRegions() }) do
      local tex = r.GetTexture and r:GetTexture() or (r.GetAtlas and r:GetAtlas())
      local atlas = r.GetAtlas and r:GetAtlas()
      regs[#regs + 1] = ("%s region%d %s %s tex=%s atlas=%s a=%.2f shown=%s"):format(label, i, r:GetObjectType(),
        tostring(r:GetName()), tostring(tex), tostring(atlas), r:GetAlpha(), tostring(r:IsShown()))
    end
    for i, c in ipairs({ f:GetChildren() }) do regs[#regs + 1] = label .. " child" .. i .. " " .. c:GetObjectType() .. " " .. tostring(c:GetName()) end
  end
  local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
  for i, f in ipairs(foci or {}) do
    local chain, p = {}, f
    while p and #chain < 8 do
      chain[#chain + 1] = tostring(p.GetName and p:GetName() or "?") .. "(" .. (p.GetObjectType and p:GetObjectType() or "") .. ")"
      p = p.GetParent and p:GetParent()
    end
    regs[#regs + 1] = "focus" .. i .. " " .. table.concat(chain, " < ")
    Dump("focus" .. i, f)
    for ci, c in ipairs({ f:GetChildren() }) do Dump("focus" .. i .. "c" .. ci, c) end
  end
  local seen = {}
  local function Walk(f, path, depth)
    if depth > 9 or (f.IsForbidden and f:IsForbidden()) then return end
    for _, r in ipairs({ f:GetRegions() }) do
      if r:IsObjectType("Texture") and r:IsVisible() and r:GetAlpha() > 0 then
        local key = tostring(r:GetAtlas() or r:GetTexture())
        if not seen[key] then
          seen[key] = true
          regs[#regs + 1] = "tex " .. key .. " @ " .. path .. " layer=" .. tostring(r:GetDrawLayer())
        end
      end
    end
    for i, c in ipairs({ f:GetChildren() }) do
      if c:IsVisible() then Walk(c, path .. "/" .. (c:GetName() or c:GetDebugName() or i), depth + 1) end
    end
  end
  if CharacterFrame and CharacterFrame:IsVisible() then Walk(CharacterFrame, "CF", 0) end
  for _, n in ipairs({ "ObjectiveTrackerFrame", "ContainerFrameCombinedBags", "SpellBookFrame", "PlayerSpellsFrame", "WorldMapFrame",
    "QuestLogFrame", "FriendsFrame", "PVEFrame", "CommunitiesFrame", "CollectionsJournal", "EncounterJournal",
    "AchievementFrame", "ProfessionsFrame", "SettingsPanel", "MerchantFrame", "GossipFrame", "QuestFrame" }) do
    local f = _G[n]
    if f and f.IsVisible and f:IsVisible() then f.eveWalked = true; Walk(f, n, 0) end
  end
  -- Any other open window EveUI skinned.
  for _, f in ipairs({ UIParent:GetChildren() }) do
    if not (f.IsForbidden and f:IsForbidden()) and f.eveSkin and not f.eveWalked and f:IsVisible() then
      Walk(f, f:GetName() or "?", 0)
    end
  end
  for _, f in ipairs({ UIParent:GetChildren() }) do f.eveWalked = nil end
  local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
  if not np and C_NamePlate then
    for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
      if p.UnitFrame and p.UnitFrame.healthBar and p.UnitFrame.healthBar:IsVisible() then np = p; break end
    end
  end
  regs[#regs + 1] = "npfound=" .. tostring(np ~= nil)
  if np and np.UnitFrame then
    Dump("np", np.UnitFrame)
    for ci, c in ipairs({ np.UnitFrame:GetChildren() }) do Dump("npc" .. ci .. "(" .. (c:GetDebugName() or "") .. ")", c) end
  end
  regs[#regs + 1] = "AlertFrame.AddAlertFrame=" .. type(AlertFrame and AlertFrame.AddAlertFrame) .. " alertSkinned=" .. tostring(ns.alertCount)
  if MirrorTimerContainer then
    Dump("mc", MirrorTimerContainer)
    for k, v in pairs(MirrorTimerContainer) do
      if type(v) == "table" and not v.GetObjectType then
        local n = 0
        for kk, vv in pairs(v) do n = n + 1; if n <= 3 then regs[#regs + 1] = "mc." .. tostring(k) .. "." .. tostring(kk) .. "=" .. tostring(type(vv) == "table" and vv.GetObjectType and (vv:GetName() or vv:GetObjectType()) or vv) end end
      end
    end
    for _, n in ipairs({ "MirrorTimer1", "MirrorTimer2" }) do if _G[n] then Dump(n, _G[n]) end end
  end
  regs[#regs + 1] = "alertNames=" .. table.concat(ns.alertNames or {}, ",")
  if ns.lastAlert then
    Dump("alert", ns.lastAlert)
    for ci, c in ipairs({ ns.lastAlert:GetChildren() }) do Dump("alertc" .. ci, c) end
  end
  local mt = MirrorTimerContainer and MirrorTimerContainer.mirrorTimers and MirrorTimerContainer.mirrorTimers[1]
  for k, t in pairs(MirrorTimerContainer and MirrorTimerContainer.activeTimers or {}) do
    local b = t.StatusBar
    local tex = b and b:GetStatusBarTexture()
    local mn, mx = b:GetMinMaxValues()
    regs[#regs + 1] = ("mirror %s shown=%s value=%s min=%s max=%s texAlpha=%s tex=%s w=%s fillW=%s timer=%s"):format(k,
      tostring(t:IsShown()), tostring(b:GetValue()), tostring(mn), tostring(mx), tostring(tex and tex:GetAlpha()),
      tostring(tex and (tex:GetAtlas() or tex:GetTexture())), tostring(b:GetWidth()), tostring(tex and tex:GetWidth()), tostring(t.timer))
  end
  if mt then
    Dump("mt", mt)
    for ci, c in ipairs({ mt:GetChildren() }) do Dump("mtc" .. ci, c) end
  end
  if MirrorTimerContainer then
    for ci, c in ipairs({ MirrorTimerContainer:GetChildren() }) do
      if ci <= 1 then
        Dump("mirror" .. ci, c)
        for cj, cc in ipairs({ c:GetChildren() }) do Dump("mirror" .. ci .. "c" .. cj, cc) end
      end
    end
  end
  Dump("head", CharacterHeadSlot)
  if PaperDollFrame then
    for i, c in ipairs({ PaperDollFrame:GetChildren() }) do if i >= 2 and i <= 4 then Dump("pdfc" .. i, c) end end
  end
  Dump("pdf", PaperDollFrame)
  local cat = CharacterStatsPane and CharacterStatsPane.AttributesCategory
  Dump("cat", cat)
  local h = CharacterHeadSlot
  regs[#regs + 1] = "headicon alpha=" .. tostring(h and h.icon and h.icon:GetAlpha()) .. " eveSkin=" .. tostring(h and h.eveSkin)
  local cb = ContainerFrameCombinedBags
  if cb and cb.EnumerateValidItems then for _, b in cb:EnumerateValidItems() do Dump("bagitem", b); break end end
  out[#out + 1] = "regions: " .. table.concat(regs, " | ")
  out[#out + 1] = "extrasLoaded=" .. tostring(ns.extrasLoaded)
  EveUIDB.debug = { build = { GetBuildInfo() }, frames = out }
  ns.Print("debug snapshot saved (" .. #out .. " frames); /reload to write it.")
end

-- Records what the cast APIs return (plain or secret, duration object methods).
local probe = CreateFrame("Frame")
probe:RegisterUnitEvent("UNIT_SPELLCAST_START", "player", "target")
probe:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "target")
probe:SetScript("OnEvent", function(_, event, unit)
  local ok, err = pcall(function()
    EveUIDB.castProbe = EveUIDB.castProbe or {}
    if #EveUIDB.castProbe > 10 then return end
    local info = { event, unit }
    local r = { (event:find("CHANNEL") and UnitChannelInfo or UnitCastingInfo)(unit) }
    for i = 1, 9 do info[#info + 1] = i .. "=" .. (ns.issecret(r[i]) and "SECRET" or tostring(r[i])) end
    local dur = event:find("CHANNEL") and UnitChannelDuration and UnitChannelDuration(unit) or (UnitCastingDuration and UnitCastingDuration(unit))
    if dur then
      local keys = {}
      local mt = getmetatable(dur)
      local idx = mt and mt.__index
      if type(idx) == "table" then for k in pairs(idx) do keys[#keys + 1] = k end end
      table.sort(keys)
      info[#info + 1] = "dur methods: " .. table.concat(keys, ",")
    end
    EveUIDB.castProbe[#EveUIDB.castProbe + 1] = table.concat(info, " ")
  end)
  if not ok then EveUIDB.castProbeErr = tostring(err) end
end)

-- /eve dev: temporary test helpers (F9 = interact with target, with
-- click-to-move so the character walks there). Run again to restore.
-- Override bindings are never saved; the old click-to-move value is restored.
local dev = CreateFrame("Frame")
function ns.ToggleDev()
  if InCombatLockdown() then return ns.Print("not in combat") end
  if dev.on or EveUIDB.devOldAuto then
    ClearOverrideBindings(dev)
    if EveUIDB.devOldAuto ~= nil then SetCVar("autoInteract", EveUIDB.devOldAuto) end
    EveUIDB.devOldAuto = nil
    dev.on = nil
    ns.Print("dev mode off (click-to-move restored to " .. tostring(GetCVar("autoInteract")) .. ")")
  else
    EveUIDB.devOldAuto = GetCVar("autoInteract")
    SetCVar("autoInteract", "1")
    SetOverrideBinding(dev, true, "F9", "INTERACTTARGET")
    dev.on = true
    ns.Print("dev mode on: F9 interacts with your target")
  end
end

-- /eve show <FrameName>: open an (empty) Blizzard window to check its skin.
-- Development only; /reload afterwards.
function ns.DevShow(name)
  if not name or InCombatLockdown() then return end
  local f = _G[name]
  if not f then
    -- Frame names are case-sensitive; try a case-insensitive match.
    local want = name:lower()
    for k, v in pairs(_G) do
      if type(k) == "string" and k:lower() == want and type(v) == "table" and v.Show then f = v; break end
    end
  end
  if not f then return ns.Print("no frame " .. name) end
  local ok, err = pcall(f.Show, f)
  ns.Print(("shown %s (%s)"):format(f:GetName() or name, ok and "ok" or tostring(err)))
end

-- Lua errors from any addon or Blizzard code: keep the default handler, but
-- count and remember them so /eve check can report them during a test run.
ns.luaErrors = {}
do
  local old = geterrorhandler()
  seterrorhandler(function(msg, ...)
    msg = tostring(msg)
    -- Keep where it came from: the message alone often names only '?'.
    local stack = debugstack and debugstack(3, 6, 0)
    if stack and stack ~= "" then msg = msg .. "\n" .. stack end
    if #ns.luaErrors < 30 then
      ns.luaErrors[#ns.luaErrors + 1] = msg
      if EveUIDB then
        EveUIDB.errors = EveUIDB.errors or {}
        if #EveUIDB.errors < 40 then table.insert(EveUIDB.errors, "lua: " .. msg) end
      end
    end
    return old(msg, ...)
  end)
end

-- /eve check: one-line health report for the test checklist.
-- Art scan: every visible texture outside EveUI that still shows Blizzard art
-- (an atlas or a texture file), so nothing unthemed gets missed. Skips our
-- own textures, hidden ones, steel-tinted ones and icons/portraits.
local ART_OK = { "interface\\icons", "white8x8", "tempportraitalphamask", "interface\\addons\\eveui",
  "^color%-", "filedata id 0" }
local function KeyOf(parent, obj)
  for k, v in pairs(parent) do if v == obj and type(k) == "string" then return k end end
end
function ns.ArtScan(limit)
  limit = limit or 400
  local out, byTop = {}, {}
  local function Fine(r, key)
    if r.eveOwn or r.eveHid or r:GetAlpha() < 0.05 or not r:IsVisible() then return true end
    if r:IsDesaturated() then return true end
    if key and (key:lower():find("icon") or key:lower():find("portrait")) then return true end
    return false
  end
  local function Walk(f, path, top, depth)
    if depth > 12 or #out >= limit then return end
    if (f.IsForbidden and f:IsForbidden()) or f == ns.root or f == WorldFrame then return end
    if not f:IsVisible() or (f.GetEffectiveAlpha and f:GetEffectiveAlpha() < 0.05) then return end
    if f.IsObjectType and f:IsObjectType("Minimap") then return end
    for _, r in ipairs({ f:GetRegions() }) do
      if r:IsObjectType("Texture") then
        local key = KeyOf(f, r)
        if not Fine(r, key) then
          local atlas = r:GetAtlas()
          local file = r:GetTexture()
          local name = atlas or file
          if name ~= nil and not ns.issecret(name) then
            local low = tostring(name):lower()
            local ok = false
            for _, pat in ipairs(ART_OK) do if low:find(pat) then ok = true; break end end
            if not ok and type(name) == "number" and r:GetWidth() < 40 and r:GetHeight() < 40
              and r:GetWidth() > 10 and math.abs(r:GetWidth() - r:GetHeight()) < 2 then
              ok = true  -- small square file: almost always an icon
            end
            if not ok then
              out[#out + 1] = ("%s.%s %s=%s %dx%d"):format(path, key or r:GetDrawLayer(), atlas and "atlas" or "file",
                tostring(name), r:GetWidth() + 0.5, r:GetHeight() + 0.5)
              byTop[top] = (byTop[top] or 0) + 1
            end
          end
        end
      end
    end
    for i, c in ipairs({ f:GetChildren() }) do
      local n = c:GetName()
      Walk(c, n or (path .. "." .. (KeyOf(f, c) or ("#" .. i))), top, depth + 1)
    end
  end
  for _, c in ipairs({ UIParent:GetChildren() }) do
    local n = c:GetName() or "?"
    local ok, err = pcall(Walk, c, n, n, 0)
    if not ok then out[#out + 1] = "scan error in " .. n .. ": " .. tostring(err) end
  end
  local tops = {}
  for k, v in pairs(byTop) do tops[#tops + 1] = { k, v } end
  table.sort(tops, function(a, b) return a[2] > b[2] end)
  EveUIDB.artScan = { time = date("%H:%M:%S"), count = #out, frames = {}, textures = out }
  for i, t in ipairs(tops) do EveUIDB.artScan.frames[i] = t[1] .. " " .. t[2] end
  return out, tops
end

-- Scan once shortly after login; written to SavedVariables on the next reload.
C_Timer.After(8, function() pcall(ns.ArtScan) end)

function ns.Check()
  local errs = EveUIDB.errors and #EveUIDB.errors or 0
  ns.Print(("check: %d logged, %d blocked, %d lua errors, combat=%s"):format(errs, ns.blockedCount or 0,
    #ns.luaErrors, tostring(InCombatLockdown())))
  for i = math.max(1, #ns.luaErrors - 2), #ns.luaErrors do
    ns.Print("  lua: " .. ns.luaErrors[i]:match("^[^\n]*"):sub(1, 140))
  end
  -- Health/power gauges: which path ran and what they show.
  for key, t in pairs(ns.arcTrace or {}) do
    if key:find("^player") then
      ns.Print(("  gauge %s: %d updates, %d secret%s"):format(key, t.calls, t.secret,
        t.err and (", error: " .. t.err) or ""))
    end
  end
  -- Font objects still on another face.
  local want, other = ns.FONT:lower(), {}
  for name, obj in pairs(_G) do
    if type(name) == "string" and type(obj) == "table" then
      local ok, kind = pcall(function() return obj.GetObjectType and obj:GetObjectType() end)
      if ok and kind == "Font" then
        local file = obj:GetFont()
        if file and file:lower() ~= want then other[#other + 1] = name .. "=" .. file end
      end
    end
  end
  table.sort(other)
  ns.Print("  face: " .. (ns.fontLoaded and "Barlow Semi Condensed" or "Arial Narrow (Barlow not found until a client restart)"))
  ns.Print(("  fonts: %d not swapped%s"):format(#other, #other > 0 and (": " .. table.concat(other, ", ", 1, math.min(#other, 6))) or ""))
  -- Visible Blizzard windows EveUI has not skinned.
  local raw = {}
  for _, f in ipairs({ UIParent:GetChildren() }) do
    if not (f.IsForbidden and f:IsForbidden()) and f:IsVisible() and f:GetName() and f:GetAlpha() > 0
      and (f.NineSlice or f.PortraitContainer or f.TitleContainer or f.Border) and not f.eveSkin then
      raw[#raw + 1] = f:GetName()
    end
  end
  if #raw > 0 then ns.Print("  unskinned: " .. table.concat(raw, ", ")) end
  -- Blizzard art still visible.
  local out, tops = ns.ArtScan()
  local list = {}
  for i = 1, math.min(#tops, 8) do list[i] = tops[i][1] .. " " .. tops[i][2] end
  ns.Print(("  blizzard art: %d textures%s"):format(#out, #list > 0 and (" in " .. table.concat(list, ", ")) or ""))
  -- Cast direction: rings/bars whose progress went the wrong way.
  if ns.CastReport then
    local n, bad = ns.CastReport()
    local pn, pbad = 0, {}
    for _, r in ipairs(ns.plateTrace or {}) do
      if r.reversed ~= nil then
        pn = pn + 1
        if r.reversed then pbad[#pbad + 1] = r.type end
      end
    end
    ns.Print(("  casts: %d rings, %d reversed%s; %d plates, %d reversed%s"):format(n, #bad,
      #bad > 0 and (" (" .. table.concat(bad, ", ") .. ")") or "", pn, #pbad,
      #pbad > 0 and (" (" .. table.concat(pbad, ", ") .. ")") or ""))
  end
end
