-- Print EveUIDB.pilotState (and killmails) from an EveUI SavedVariables file as JSON.
-- Usage: lua5.1 sv2json.lua <EveUI.lua>
local path = arg[1]
local env = {}
local chunk = assert(loadfile(path))
setfenv(chunk, env)
chunk()
local db = env.EveUIDB or {}

local function esc(s)
  return (s:gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[c] or string.format('\\u%04x', c:byte())
  end))
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

local function enc(v, out)
  local t = type(v)
  if t == 'table' then
    if next(v) == nil then out[#out + 1] = '[]' return end
    if isArray(v) then
      out[#out + 1] = '['
      for i, x in ipairs(v) do
        if i > 1 then out[#out + 1] = ',' end
        enc(x, out)
      end
      out[#out + 1] = ']'
    else
      out[#out + 1] = '{'
      local first = true
      for k, x in pairs(v) do
        if not first then out[#out + 1] = ',' end
        first = false
        out[#out + 1] = '"' .. esc(tostring(k)) .. '":'
        enc(x, out)
      end
      out[#out + 1] = '}'
    end
  elseif t == 'string' then
    out[#out + 1] = '"' .. esc(v) .. '"'
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = 'null'
    else out[#out + 1] = string.format('%.10g', v) end
  elseif t == 'boolean' then
    out[#out + 1] = tostring(v)
  else
    out[#out + 1] = 'null'
  end
end

local out = {}
enc({ state = db.pilotState, marks = db.pilotMarks, mode = db.pilotMode, killmails = db.killmails }, out)
io.write(table.concat(out))
