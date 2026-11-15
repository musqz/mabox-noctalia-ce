--!nonstrict
-- Install apps: curated pacman-only list (lists/install.csv); installs with sudo pacman -S in a terminal.
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local CSV = "/usr/share/mabox-noctalia-ce/install.csv"

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 6, border = "primary", borderWidth = 1 }
end

local apps, order = {}, {}
local installed = {}
local query = ""
local render

local function loadList()
  apps, order = {}, {}
  local seen = {}
  for line in string.gmatch((noctalia.readFile(CSV) or "") .. "\n", "([^\n]*)\n") do
    local cat, pkg, name, desc = string.match(line, "^([^,#][^,]*),([^,]+),([^,]+),(.*)$")
    if cat then
      if not seen[cat] then
        seen[cat] = true
        table.insert(order, cat)
        apps[cat] = {}
      end
      table.insert(apps[cat], { pkg = pkg, name = name, desc = desc })
    end
  end
end

local function queryInstalled()
  noctalia.runAsync({ "sh", "-c", "pacman -Qq 2>/dev/null" }, function(result)
    installed = {}
    for pkg in string.gmatch(result.stdout or "", "[^\n]+") do
      installed[pkg] = true
    end
    render()
  end)
end

-- Terminal from the Agents plugin setting, then $TERMINAL, then the first installed one; detached so it outlives the panel command.
local RUN = [[t=$(sed -n 's/^terminal=//p' "${XDG_CONFIG_HOME:-$HOME/.config}/mabox/mb-agent-sessions.conf" 2>/dev/null)
for t in "$t" ${TERMINAL%% *} foot kitty alacritty terminator xfce4-terminal xterm; do
  [ -n "$t" ] && command -v "$t" >/dev/null || continue
  case "${t##*/}" in
    kitty) setsid -f "$t" sh -c "$1" sh "$2"; exit ;;
    terminator|xfce4-terminal) setsid -f "$t" -x sh -c "$1" sh "$2"; exit ;;
    *) setsid -f "$t" -e sh -c "$1" sh "$2"; exit ;;
  esac
done
exit 127]]

local function install(app)
  -- Closing the terminal reopens the panel, which re-reads the installed packages.
  local script = "sudo pacman -S --needed \"$1\"; echo; printf 'Press Enter to close. '; read _; noctalia msg panel-open mabox/install:main"
  noctalia.runAsync({ "sh", "-c", RUN, "sh", script, app.pkg }, function(result)
    if result.exitCode == 127 then
      noctalia.notify("Install apps", "No terminal found")
    end
  end)
  panel.close()
end

local function row(app)
  local right
  if installed[app.pkg] then
    right = ui.label({ text = "installed", color = "primary" })
  else
    right = ui.button({ text = "Install", variant = "outline", controlSize = "sm", onClick = function()
      install(app)
    end })
  end
  return ui.column({ key = app.pkg, gap = 0 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = app.name, flexGrow = 1 }),
      right,
    }),
    ui.label({ text = app.desc, color = "on_surface_variant", fontSize = 11 }),
  })
end

local function matches(app)
  local q = string.lower(noctalia.string.trim(query))
  return q == "" or string.find(string.lower(app.name .. " " .. app.pkg .. " " .. app.desc), q, 1, true) ~= nil
end

render = function()
  local cards, total, have = {}, 0, 0
  for _, cat in ipairs(order) do
    local rows = {}
    for _, app in ipairs(apps[cat]) do
      total = total + 1
      if installed[app.pkg] then
        have = have + 1
      end
      if matches(app) then
        table.insert(rows, row(app))
      end
    end
    if #rows > 0 then
      table.insert(cards, ui.column(card(cat), { ui.label({ text = cat, color = "primary" }), ui.column({ gap = 8 }, rows) }))
    end
  end
  local left, right = {}, {}
  for i, c in ipairs(cards) do
    table.insert(i % 2 == 1 and left or right, c)
  end
  local body
  if total == 0 then
    body = ui.label({ text = "No app list found at " .. CSV, color = "on_surface_variant" })
  else
    body = ui.row({ gap = 10, align = "start" }, {
      ui.column({ key = "col-left", gap = 10, flexGrow = 1, minWidth = 300 }, left),
      ui.column({ key = "col-right", gap = 10, flexGrow = 1, minWidth = 300 }, right),
    })
  end
  panel.render(ui.column({ gap = 10, padding = 12, height = 700 }, {
    ui.row({ gap = 6, align = "center" }, {
      logo(),
      ui.label({ text = "Install apps" }),
      ui.label({ text = hotkey("mabox/install:main"), color = "outline_variant", flexGrow = 1 }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.input({ key = "search", value = query, focus = true, placeholder = "filter apps", controlSize = "sm", flexGrow = 1, onChange = function(text)
        query = text
        render()
      end }),
      ui.label({ text = have .. " of " .. total .. " installed", color = "on_surface_variant", fontSize = 11 }),
    }),
    ui.scroll({ flexGrow = 1, key = "list" }, { body }),
  }))
end

function onOpen()
  query = ""
  loadList()
  render()
  queryInstalled()
end
