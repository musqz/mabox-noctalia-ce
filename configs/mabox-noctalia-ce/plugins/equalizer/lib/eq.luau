--!nonstrict
-- Shared by the panel and the login service: saved state and the mb-eq commands.
local M = {}

M.LABELS = { "Pre", "31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k" }

-- Preamp first, then the ten bands.
M.PRESETS = {
  { name = "Flat", gains = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
  { name = "Bass", gains = { -3, 6, 5, 4, 2, 0, 0, 0, 0, 0, 0 } },
  { name = "Treble", gains = { -3, 0, 0, 0, 0, 0, 1, 2, 4, 5, 6 } },
  { name = "Vocal", gains = { -2, -2, -1, 0, 0, 2, 3, 3, 2, 0, -1 } },
  { name = "Loudness", gains = { -4, 5, 4, 1, 0, -1, 0, 1, 3, 4, 2 } },
}

local function path()
  local dir = noctalia.pluginDataDir()
  return dir and dir .. "/state.json" or nil
end

function M.load()
  local state = { on = false, gains = { table.unpack(M.PRESETS[1].gains) }, presets = {} }
  local p = path()
  local raw = p and noctalia.readFile(p)
  local data = raw and noctalia.json.decode(raw)
  if type(data) == "table" then
    state.on = data.on == true
    if type(data.gains) == "table" and #data.gains == 11 then
      state.gains = data.gains
    end
    if type(data.presets) == "table" then
      for _, p in ipairs(data.presets) do
        if type(p) == "table" and type(p.name) == "string" and type(p.gains) == "table" and #p.gains == 11 then
          table.insert(state.presets, p)
        end
      end
    end
  end
  return state
end

function M.save(state)
  local p = path()
  if p then
    noctalia.writeFile(p, noctalia.json.encode(state, true) .. "\n")
  end
end

function M.gainArgs(gains)
  local out = {}
  for i = 1, 11 do
    out[i] = string.format("%.1f", tonumber(gains[i]) or 0)
  end
  return out
end

return M
