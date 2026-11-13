--!nonstrict
-- Update actions of the bar button: pending counts from mb-updates-ce, buttons start the upgrade in a terminal.
local hotkey = require("./hotkey.luau")
local SOURCES = { { "repo", "Repo" }, { "aur", "AUR" }, { "flatpak", "Flatpak" }, { "snap", "Snap" }, { "npm", "npm" }, { "pipx", "pipx" } }
local counts = {}
local orphans = 0
local has = {}
local checking = false
local view = "main"
local render

local function dir()
  return (noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/mb-updates/"
end

local function load()
  counts = {}
  for _, s in ipairs(SOURCES) do
    local n = 0
    for _ in string.gmatch(noctalia.readFile(dir() .. s[1]) or "", "[^\n]+") do
      n += 1
    end
    counts[s[1]] = n
  end
end

local function lines(name)
  local out = {}
  for l in string.gmatch(noctalia.readFile(dir() .. name) or "", "[^\n]+") do
    table.insert(out, l)
  end
  return out
end

-- "name old -> new" (pacman, yay) splits into a name and a version change; other lines stay as they are.
local function split(line)
  local name, old, new = string.match(line, "^(%S+)%s+(%S+)%s+%->%s+(%S+)")
  if name then
    return name, old .. " -> " .. new
  end
  return line, nil
end

local function listView()
  local rows = {}
  for _, s in ipairs(SOURCES) do
    local items = lines(s[1])
    if #items > 0 then
      table.insert(rows, ui.label({ text = s[2] .. " (" .. #items .. ")", fontSize = 12, color = "primary" }))
      for _, line in ipairs(items) do
        local name, detail = split(line)
        local entry = { ui.label({ text = name, fontSize = 12 }) }
        if detail then
          table.insert(entry, ui.label({ text = detail, fontSize = 10, color = "on_surface_variant" }))
        end
        table.insert(rows, ui.column({ gap = 0 }, entry))
      end
    end
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "Nothing to update", color = "on_surface_variant" }))
  end
  panel.render(ui.column({ gap = 8, padding = 12, height = 460 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.button({ glyph = "arrow-left", variant = "ghost", controlSize = "sm", tooltip = "Back", onClick = function() view = "main" render() end }),
      ui.label({ text = "Pending updates", fontSize = 14 }),
    }),
    ui.scroll({ flexGrow = 1, gap = 6, key = "list" }, rows),
  }))
end

local function card(key, children)
  return ui.column({ key = key, fill = "surface_variant", radius = 10, padding = 10, gap = 4, border = "primary", borderWidth = 1 }, children)
end

local INFO = {
  { "Checking", {
    "Counts pacman, AUR, Flatpak, Snap, npm and pipx updates.",
    "Runs 30 s after start, hourly and after each pacman change.",
    "Check now runs it by hand.",
  } },
  { "Updating", {
    "Buttons open a terminal and ask for your password.",
    "Flatpak, Snap, npm and pipx buttons show only when that source has updates.",
    "Snap is skipped while snapd is off.",
  } },
}

local function mirrorInfo()
  if has.mirrors then
    return { "Mirrors", { "Fasttrack: fastest up-to-date mirrors.", "Continent: mirrors near you.", "Choose (all): pick mirrors from a list (takes a minute)." } }
  elseif has.reflector then
    return { "Mirrors", { "Reflector: fastest https mirrors, written to /etc/pacman.d/mirrorlist." } }
  end
end

local function infoView()
  local cards = {
    ui.row({ gap = 6, align = "center" }, {
      ui.button({ glyph = "arrow-left", variant = "ghost", controlSize = "sm", tooltip = "Back", onClick = function() view = "main" render() end }),
      ui.label({ text = "Update checker", fontSize = 14 }),
    }),
  }
  local sections = { table.unpack(INFO) }
  table.insert(sections, mirrorInfo())
  for _, sec in ipairs(sections) do
    local rows = { ui.label({ text = sec[1], fontSize = 12, color = "primary" }) }
    for _, t in ipairs(sec[2]) do
      table.insert(rows, ui.label({ text = t, fontSize = 11, color = "on_surface_variant" }))
    end
    table.insert(cards, card("info-" .. sec[1], rows))
  end
  panel.render(ui.column({ gap = 8, padding = 12 }, cards))
end

local function start(argv)
  panel.close()
  local cmd = { "setsid", "-f", "mb-updates-ce" }
  for _, a in ipairs(argv) do
    table.insert(cmd, a)
  end
  noctalia.runAsync(cmd)
end

local function action(text, glyph, argv, variant)
  return ui.button({ text = text, glyph = glyph, variant = variant or "ghost", contentAlign = "start", onClick = function() start(argv) end })
end

render = function()
  if view == "list" then
    listView()
    return
  end
  if view == "info" then
    infoView()
    return
  end
  local total, parts = 0, {}
  for _, s in ipairs(SOURCES) do
    total += counts[s[1]] or 0
    if (counts[s[1]] or 0) > 0 then
      table.insert(parts, s[2] .. " " .. counts[s[1]])
    end
  end
  local head = {
    ui.label({ text = checking and "Checking for updates" or (total > 0 and (total .. " updates") or "System up to date"), fontSize = 14, flexGrow = 1 }),
    ui.button({ glyph = "help-circle", variant = "ghost", controlSize = "sm", tooltip = "About the update checker", onClick = function() view = "info" render() end }),
    ui.button({ glyph = "info-circle", variant = "ghost", controlSize = "sm", tooltip = "System info and fixes " .. hotkey("mabox/system:system"), onClick = function()
      panel.close()
      noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/system:system" })
    end }),
  }
  local top = { ui.row({ gap = 6, align = "center" }, head) }
  if #parts > 0 then
    table.insert(top, ui.label({ text = table.concat(parts, "  "), color = "on_surface_variant", fontSize = 11 }))
  end
  local updates = {}
  if total > 0 then
    table.insert(updates, ui.button({ text = "View updates (" .. total .. ")", glyph = "list", variant = "ghost", contentAlign = "start", onClick = function() view = "list" render() end }))
  end
  table.insert(updates, action("Update all", "download", { "upgrade", "all" }, "primary"))
  table.insert(updates, action("Repo + AUR (yay)", "package", { "upgrade", "aur" }))
  table.insert(updates, action("Repo only (pacman)", "package", { "upgrade", "repo" }))
  for _, s in ipairs({ { "flatpak", "Flatpak" }, { "snap", "Snap" }, { "npm", "npm" }, { "pipx", "pipx" } }) do
    if (counts[s[1]] or 0) > 0 then
      table.insert(updates, action("Update " .. s[2], "package", { "upgrade", s[1] }))
    end
  end
  if orphans > 0 then
    table.insert(updates, action("Remove orphans (" .. orphans .. ")", "trash", { "orphans" }))
  end
  local items = { ui.column({ gap = 2 }, top), card("updates", updates) }
  if has.mirrors or has.reflector then
    local mirrors = { ui.label({ text = "Mirrors", fontSize = 14 }) }
    if has.mirrors then
      table.insert(mirrors, action("Fasttrack", "world", { "mirrors", "fasttrack" }))
      table.insert(mirrors, action("Continent", "world", { "mirrors", "continent" }))
      table.insert(mirrors, action("Choose (all)", "world", { "mirrors", "all" }))
    end
    if has.reflector and not has.mirrors then
      table.insert(mirrors, action("Reflector", "world", { "mirrors", "reflector" }))
    end
    table.insert(items, card("mirrors", mirrors))
  end
  table.insert(items, card("check", { ui.button({
    text = "Check now",
    glyph = "refresh",
    variant = "ghost",
    contentAlign = "start",
    onClick = function()
      checking = true
      render()
      noctalia.runAsync({ "mb-updates-ce", "check" }, function()
        checking = false
        load()
        render()
      end)
    end,
  }) }))
  panel.render(ui.column({ gap = 8, padding = 12 }, { ui.scroll({ gap = 8, flexGrow = 1, key = "main" }, items) }))
end

return function()
  checking = false
  view = "main"
  load()
  render()
  noctalia.runAsync({ "sh", "-c", "command -v pacman-mirrors >/dev/null && echo mirrors; command -v reflector >/dev/null && echo reflector; true" }, function(result)
    has = { mirrors = string.find(result.stdout or "", "mirrors", 1, true) ~= nil, reflector = string.find(result.stdout or "", "reflector", 1, true) ~= nil }
    render()
  end)
  noctalia.runAsync({ "sh", "-c", "pacman -Qtdq 2>/dev/null | grep -c . || true" }, function(result)
    orphans = tonumber(string.match(result.stdout or "", "%d+")) or 0
    render()
  end)
end
