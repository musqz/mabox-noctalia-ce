--!nonstrict
-- Reads one section of Noctalia's state file (settings.toml) as key -> raw value. The file is rewritten on every
-- config-set, so a panel that re-reads it on each render never shows a stale copy.
local M = {}

function M.section(header)
  local base = noctalia.getenv("XDG_STATE_HOME")
  if not base or base == "" then
    base = noctalia.getenv("HOME") .. "/.local/state"
  end
  local out, inside = {}, false
  for line in string.gmatch(noctalia.readFile(base .. "/noctalia/settings.toml") or "", "[^\n]+") do
    local h = string.match(line, "^%s*%[([^%]]+)%]%s*$")
    if h then
      inside = h == header
    elseif inside then
      local k, v = string.match(line, "^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
      if k then
        out[k] = v
      end
    end
  end
  return out
end

function M.str(v, default)
  return v and string.match(v, '^"(.*)"$') or default
end

function M.words(v)
  local list = {}
  for w in string.gmatch(v or "", '"([%w_]+)"') do
    table.insert(list, w)
  end
  return list
end

return M
