--!nonstrict
-- Update actions of the bar button: pending counts from mb-updates-ce, buttons start the upgrade in a terminal.
local SOURCES = { { "repo", "Repo" }, { "aur", "AUR" }, { "flatpak", "Flatpak" }, { "snap", "Snap" }, { "npm", "npm" }, { "pipx", "pipx" } }
local counts = {}
local orphans = 0
local checking = false
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
  local total, parts = 0, {}
  for _, s in ipairs(SOURCES) do
    total += counts[s[1]] or 0
    if (counts[s[1]] or 0) > 0 then
      table.insert(parts, s[2] .. " " .. counts[s[1]])
    end
  end
  local items = {
    ui.label({ text = checking and "Checking for updates" or (total > 0 and (total .. " updates") or "System up to date"), fontSize = 14 }),
  }
  if #parts > 0 then
    table.insert(items, ui.label({ text = table.concat(parts, "  "), color = "on_surface_variant", fontSize = 11 }))
  end
  table.insert(items, action("Update all", "download", { "upgrade", "all" }, "primary"))
  table.insert(items, action("Repo + AUR (yay)", "package", { "upgrade", "aur" }))
  table.insert(items, action("Repo only (pacman)", "package", { "upgrade", "repo" }))
  for _, s in ipairs({ { "flatpak", "Flatpak" }, { "snap", "Snap" }, { "npm", "npm" }, { "pipx", "pipx" } }) do
    if (counts[s[1]] or 0) > 0 then
      table.insert(items, action("Update " .. s[2], "package", { "upgrade", s[1] }))
    end
  end
  if orphans > 0 then
    table.insert(items, action("Remove orphans (" .. orphans .. ")", "trash", { "orphans" }))
  end
  table.insert(items, ui.button({
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
  }))
  panel.render(ui.column({ gap = 4, padding = 12 }, items))
end

return function()
  checking = false
  load()
  render()
  noctalia.runAsync({ "sh", "-c", "pacman -Qtdq 2>/dev/null | grep -c . || true" }, function(result)
    orphans = tonumber(string.match(result.stdout or "", "%d+")) or 0
    render()
  end)
end
