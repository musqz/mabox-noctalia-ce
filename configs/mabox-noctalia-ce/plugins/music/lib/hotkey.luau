--!nonstrict
-- Hotkey of a command, read from the live rc.xml: hotkey("mb-pinned notes") returns "(C-W-n)" or "".

local binds, checked = {}, 0

local function load()
  if os.time() - checked < 5 then
    return
  end
  checked = os.time()
  local home = noctalia.getenv("HOME")
  local body = home and noctalia.readFile(home .. "/.config/mabox-noctalia-ce/rc.xml")
  if not body then
    return
  end
  body = string.gsub(body, "<!%-%-.-%-%->", "")
  binds = {}
  for line in string.gmatch(body, "[^\n]+") do
    local key = string.match(line, '<keybind%s+key="([^"]+)"')
    if key then
      table.insert(binds, { key = key, line = line })
    end
  end
end

return function(command)
  load()
  for _, b in ipairs(binds) do
    if string.find(b.line, command, 1, true) then
      return "(" .. b.key .. ")"
    end
  end
  return ""
end
