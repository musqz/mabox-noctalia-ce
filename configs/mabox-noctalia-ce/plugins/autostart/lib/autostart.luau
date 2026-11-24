--!nonstrict
-- autostart.local lines "(sleep N && CMD) &" (enabled) and "#(sleep N && CMD) &" (off); other lines are kept as they are.
-- autostart.skip holds the names of shipped defaults that stay off.
local M = {}

M.DEFAULTS = {
  { name = "skippy-wl", desc = "Window switcher service" },
  { name = "kanshi", desc = "Monitor profiles" },
  { name = "mb-updates-ce", desc = "Update checker for the bar" },
  { name = "mb-status-warn", desc = "Status warnings" },
  { name = "mb-hide-cursor", desc = "Hide the pointer (F20)" },
  { name = "numlock", desc = "Switch NumLock on at login" },
  { name = "session", desc = "Open the Sessions panel (A-F1)" },
}

-- Started by the session, not switchable here. polkit is a Noctalia setting (shell.polkit_agent).
M.FIXED = {
  { name = "noctalia", desc = "Shell, bar, launcher and panels" },
  { name = "polkit agent", desc = "Password prompts, run by Noctalia" },
  { name = "labwc-session.target", desc = "Systemd user services of the session" },
  { name = "mabox plugins", desc = "Adds the plugin source and enables new plugins" },
  { name = "stock wallpaper", desc = "Sets the default wallpaper at the first login" },
  { name = "autostart.local", desc = "Your entries above" },
}

local function dir()
  return noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce"
end

function M.localFile()
  return dir() .. "/autostart.local"
end

local function skipFile()
  return dir() .. "/autostart.skip"
end

local function parse(line)
  local off, delay, cmd = string.match(line, "^(#?)%(sleep (%d+) && (.-)%) &%s*$")
  if not delay then
    return nil
  end
  return { on = off == "", delay = tonumber(delay), cmd = cmd }
end

local function format(e)
  return (e.on and "" or "#") .. "(sleep " .. e.delay .. " && " .. e.cmd .. ") &"
end

-- Returns the entries plus the raw lines; each entry remembers its line number.
function M.load()
  local lines, entries = {}, {}
  local text = noctalia.readFile(M.localFile()) or ""
  M.loaded = text
  for line in string.gmatch(text, "([^\n]*)\n?") do
    table.insert(lines, line)
  end
  if lines[#lines] == "" then
    table.remove(lines)
  end
  for i, line in ipairs(lines) do
    local e = parse(line)
    if e then
      e.line = i
      table.insert(entries, e)
    end
  end
  return entries, lines
end

-- Rewrites matched lines in place, appends entries without a line, drops removed ones (line set, entry gone).
function M.save(entries, lines)
  if (noctalia.readFile(M.localFile()) or "") ~= M.loaded then
    return false, "changed"
  end
  local keep = {}
  for _, e in ipairs(entries) do
    if e.line then
      lines[e.line] = format(e)
      keep[e.line] = true
    end
  end
  local out = {}
  for i, line in ipairs(lines) do
    if keep[i] or not parse(line) then
      table.insert(out, line)
    end
  end
  for _, e in ipairs(entries) do
    if not e.line then
      table.insert(out, format(e))
    end
  end
  noctalia.mkdirAll(dir())
  return noctalia.writeFile(M.localFile(), table.concat(out, "\n") .. "\n")
end

function M.skipped()
  local set = {}
  for line in string.gmatch(noctalia.readFile(skipFile()) or "", "[^\n]+") do
    set[line] = true
  end
  return set
end

-- Read the file again before changing it: other names (written by hand or by mb-session) stay.
function M.setSkipped(name, skip)
  local names = {}
  for line in string.gmatch(noctalia.readFile(skipFile()) or "", "[^\n]+") do
    line = noctalia.string.trim(line)
    if line ~= "" and line ~= name then
      table.insert(names, line)
    end
  end
  if skip then
    table.insert(names, name)
  end
  noctalia.mkdirAll(dir())
  return noctalia.writeFile(skipFile(), #names > 0 and table.concat(names, "\n") .. "\n" or "")
end

return M
