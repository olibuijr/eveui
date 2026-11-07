-- Faction themes: accent and steel colours after EVE's four empires (plus a
-- neutral one). Core calls ns.ApplyTheme when the saved settings load, before
-- any module draws, so every module picks the colours up. Changing the theme
-- needs a reload. The palette tables are edited in place, so anything that
-- holds a reference to C.accent and friends sees the new values.
local ADDON, ns = ...
local C = ns.C

-- accent, border (steel) tint, header tint, cast colour
ns.THEMES = {
  { key = "caldari", label = "Caldari", accent = { 0.36, 0.78, 0.86 }, steel = { 0.30, 0.38, 0.42 },
    header = { 0.08, 0.10, 0.12 } },
  { key = "amarr", label = "Amarr", accent = { 0.95, 0.76, 0.34 }, steel = { 0.42, 0.37, 0.28 },
    header = { 0.11, 0.09, 0.06 } },
  { key = "gallente", label = "Gallente", accent = { 0.42, 0.86, 0.58 }, steel = { 0.30, 0.40, 0.35 },
    header = { 0.07, 0.10, 0.09 } },
  { key = "minmatar", label = "Minmatar", accent = { 0.92, 0.48, 0.30 }, steel = { 0.42, 0.33, 0.29 },
    header = { 0.11, 0.08, 0.07 } },
  { key = "jove", label = "Jove", accent = { 0.70, 0.60, 0.98 }, steel = { 0.35, 0.33, 0.44 },
    header = { 0.09, 0.08, 0.12 } },
}

local function Set(dst, rgb, a)
  dst[1], dst[2], dst[3] = rgb[1], rgb[2], rgb[3]
  if a then dst[4] = a end
end

function ns.Theme()
  local key = EveUIDB and EveUIDB.theme or "caldari"
  for _, t in ipairs(ns.THEMES) do if t.key == key then return t end end
  return ns.THEMES[1]
end

function ns.ApplyTheme()
  local t = ns.Theme()
  ns.appliedTheme = t.key
  Set(C.accent, t.accent, 1)
  Set(C.border, t.steel, 0.75)
  Set(C.line, t.steel, 0.35)
  Set(C.header, t.header, 0.95)
  ns.accentHex = ("%02x%02x%02x"):format(t.accent[1] * 255, t.accent[2] * 255, t.accent[3] * 255)
end

-- /eve theme [name]
function ns.ThemeCommand(arg)
  if arg and arg ~= "" then
    for _, t in ipairs(ns.THEMES) do
      if t.key == arg then
        EveUIDB.theme = t.key ~= "caldari" and t.key or nil
        ReloadUI()
        return
      end
    end
  end
  local names = {}
  for _, t in ipairs(ns.THEMES) do names[#names + 1] = t.key end
  ns.Print("theme: " .. ns.Theme().key .. "  (/eve theme " .. table.concat(names, " | ") .. ")")
end
