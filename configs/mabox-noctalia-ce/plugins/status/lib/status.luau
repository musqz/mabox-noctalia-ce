--!nonstrict
-- Status: own probes, one at a time through runAsync; cleanup rows run in a terminal.
-- Settings follow mb-status-ce and live in <plugin data dir>/settings.

return function(pinned)
local REFRESH = 30
local MIB = 1048576

local DEFAULTS = {
  big_pkgs = "10",
  disk_limit = "90",
  dir_size_monitor = "y",
  dynamic_menu = "y",
  cache_days = "30",
  thumb_days = "14",
  cache_ignore = "borg betterlockscreen mozilla firefox floorp waterfox firedragon zen chromium google-chrome BraveSoftware vivaldi librewolf paru yay pamac mabox jgmenu mb-status-ce fontconfig",
  warn = "#ff9800",
}
local WARN_COLORS = {
  { name = "red", hex = "#bd1e24" },
  { name = "pink", hex = "#e91e63" },
  { name = "red-orange", hex = "#ff5722" },
  { name = "orange", hex = "#ff9800" },
  { name = "yellow", hex = "#f6c700" },
}

local S = {}
for k, v in pairs(DEFAULTS) do
  S[k] = v
end

-- Shell snippet for the terminal: show size and dry run, ask, run, show size again.
local TERM_SCRIPT = [[
printf '\033[1m%s\033[0m\n\n' "$1"
[ -n "$2" ] && { echo 'Size now:'; sh -c "$2"; echo; }
[ -n "$3" ] && { echo 'Dry run:'; sh -c "$3"; echo; }
printf 'Will run: %s\nContinue? [y/N] ' "$4"
read -r a
case $a in
  y|Y) sh -c "$4"; [ -n "$2" ] && { echo; echo 'Size after:'; sh -c "$2"; } ;;
  *) echo Cancelled ;;
esac
printf '\nPress Enter to close '
read -r _
]]

local data = {}
local queue = {}
local running = false
local again = false
local lastRun = 0
local ticks = 0
local view = "main"
local dirty = false
local expanded = nil
local render

local function trim(s)
  return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function human(bytes)
  local units = { "B", "K", "M", "G", "T" }
  local i = 1
  local v = bytes
  while v >= 1024 and i < #units do
    v = v / 1024
    i += 1
  end
  return i == 1 and `{math.floor(v)}B` or string.format("%.1f%s", v, units[i])
end

local function lines(text)
  local out = {}
  for l in string.gmatch(text or "", "[^\n]+") do
    table.insert(out, l)
  end
  return out
end

local function num(text)
  return tonumber(trim(text or "")) or 0
end

-- Settings

local function settingsPath()
  local dir = noctalia.pluginDataDir()
  return dir and dir .. "/settings" or nil
end

local function loadSettings()
  local path = settingsPath()
  local raw = path and noctalia.readFile(path)
  for l in string.gmatch(raw or "", "[^\n]+") do
    local k, v = string.match(l, "^(%w_*[%w_]*)=(.*)$")
    local numeric = k == "big_pkgs" or k == "disk_limit" or k == "cache_days" or k == "thumb_days"
    local valid = not numeric or string.match(v, "^%d+$")
    if k and DEFAULTS[k] and valid then
      S[k] = v
    end
  end
end

local function setSetting(k, v)
  loadSettings()
  S[k] = v
  dirty = true
  local dir = noctalia.pluginDataDir()
  if not dir then
    return
  end
  noctalia.mkdirAll(dir)
  local out = {}
  for key in pairs(DEFAULTS) do
    table.insert(out, key .. "=" .. S[key])
  end
  table.sort(out)
  noctalia.writeFile(settingsPath(), table.concat(out, "\n") .. "\n")
end

-- Probes

local function ignoreArgs()
  local args = ""
  for name in string.gmatch(S.cache_ignore, "[%w%._%-]+") do
    args = args .. " ! -name '" .. name .. "'"
  end
  return args
end

-- Files in ~/.cache untouched for N days, skipping the top-level names on the ignore list.
local function staleFind(tail)
  return `find ~/.cache -mindepth 1 -maxdepth 1{ignoreArgs()} -exec find \{\} -type f -atime +{S.cache_days} {tail} \;`
end

local SUM = "awk '{t+=$1} END{print t+0}'"

local function probes()
  local list = {
    { key = "tools", cmd = "for t in paru yay pamac docker flatpak snap go npm cargo-cache pip yarn pnpm pacdiff meld expac; do command -v $t >/dev/null && echo $t; done" },
    { key = "sys", cmd = 'echo "$(lsb_release -rs 2>/dev/null) $(lsb_release -cs 2>/dev/null)"; uname -r; pacman -Qq | wc -l; stat -c %W /' },
    { key = "disc", fast = true, cmd = "df -h --output=source,size,used,pcent,target | awk 'NR>1 && $1 ~ /^\\/dev\\// && $1 !~ /loop/ && $5 !~ /^\\/(boot|run)/ && $5 !~ /^\\/run\\/media/ && !seen[$1]++'" },
  }
  if tonumber(S.big_pkgs) > 0 then
    table.insert(list, { key = "big", cmd = `command -v expac >/dev/null && expac -H M '%n %m' | sort -rhk2 | head -n {S.big_pkgs}` })
  end
  if S.dir_size_monitor == "y" then
    local more = {
      { key = "journal", cmd = "journalctl --disk-usage 2>/dev/null" },
      { key = "pk3", cmd = "paccache -dk3 2>/dev/null" },
      { key = "pk1", cmd = "paccache -dk1 2>/dev/null" },
      { key = "pun", cmd = "paccache -duk0 2>/dev/null" },
      { key = "orphans", cmd = "pacman -Qdtq 2>/dev/null" },
      { key = "sizes", cmd = "du -sb -- /var/cache/pacman/pkg ~/.cache/paru ~/.cache/yay /var/tmp/pamac-build-$USER ~/.cache/thumbnails ~/.local/share/Trash 2>/dev/null" },
      { key = "home", cmd = "du -sb -- ~/.cache 2>/dev/null" },
      { key = "stale", cmd = staleFind("-printf '%s\\n'") .. " | " .. SUM },
      { key = "downloads", cmd = 'du -sb -- "$(xdg-user-dir DOWNLOAD)" 2>/dev/null' },
      { key = "docker", cmd = "command -v docker >/dev/null && timeout 3 docker info >/dev/null 2>&1 && { docker ps -aq -f status=exited -f status=created; docker images -qf dangling=true; } | wc -l" },
      { key = "flatpak", cmd = "command -v flatpak >/dev/null && flatpak uninstall --unused --assumeno 2>&1 | grep -cE '^ *[0-9]+\\.'" },
      { key = "snap", cmd = "command -v snap >/dev/null && timeout 3 snap list --all 2>/dev/null | grep -c disabled" },
      { key = "pacdiff", cmd = "find /etc -name '*.pacnew' -o -name '*.pacsave' 2>/dev/null | wc -l" },
    }
    for _, p in ipairs(more) do
      table.insert(list, p)
    end
  end
  return list
end

local function runNext()
  local probe = table.remove(queue, 1)
  if not probe then
    running = false
    if again then
      again = false
      lastRun = ticks
      queue = probes()
      running = true
      runNext()
      return
    end
    render()
    return
  end
  noctalia.runAsync({ "timeout", "30", "sh", "-c", probe.cmd }, function(result)
    data[probe.key] = result.stdout or ""
    render()
    runNext()
  end)
end

-- fastOnly: the periodic refresh only rereads the disc usage.
local function refresh(fastOnly)
  if running then
    again = again or not fastOnly
    return
  end
  running = true
  lastRun = ticks
  queue = {}
  for _, p in ipairs(probes()) do
    if p.fast or not fastOnly then
      table.insert(queue, p)
    end
  end
  runNext()
end

local function has(tool)
  return string.find("\n" .. (data.tools or "") .. "\n", "\n" .. tool .. "\n", 1, true) ~= nil
end

local function sizeMap()
  local map = {}
  for _, l in ipairs(lines(data.sizes)) do
    local bytes, path = string.match(l, "^(%d+)%s+(.+)$")
    if bytes then
      map[path] = tonumber(bytes)
    end
  end
  return map
end

local function runTerminal(title, size, dry, run)
  noctalia.runAsync({ "foot", "-e", "sh", "-c", TERM_SCRIPT, "sh", title, size, dry, run }, function()
    refresh(false)
  end)
end

local function openDir(path)
  noctalia.runAsync({ "xdg-open", path })
end

-- Rows

local function warnColor()
  return S.warn
end

local function row(label, value, onClick, warn)
  local vlabel = ui.label({ text = value, color = warn and warnColor() or "on_surface_variant" })
  if onClick then
    return ui.row({ gap = 6, align = "center" }, {
      ui.button({ text = label, variant = "ghost", controlSize = "sm", contentAlign = "start", flexGrow = 1, onClick = onClick }),
      vlabel,
    })
  end
  return ui.row({ gap = 6, align = "center", padding = 4 }, {
    ui.label({ text = label, flexGrow = 1 }),
    vlabel,
  })
end

local function heading(text)
  return ui.label({ text = string.upper(text), fontSize = 11, color = "primary" })
end

local function systemRows(rows)
  local l = lines(data.sys)
  if #l < 4 then
    return
  end
  table.insert(rows, heading("System"))
  table.insert(rows, row("Release", trim(l[1])))
  table.insert(rows, row("Kernel", trim(l[2])))
  table.insert(rows, row("Packages", trim(l[3])))
  local born = tonumber(l[4])
  if born and born > 0 then
    table.insert(rows, row("Installed", `{math.floor((os.time() - born) / 86400)} days ago`))
  end
end

local function bigRows(rows)
  local l = lines(data.big)
  if #l == 0 or tonumber(S.big_pkgs) == 0 then
    return
  end
  table.insert(rows, heading(`{S.big_pkgs} biggest packages`))
  for _, line in ipairs(l) do
    local name, size = string.match(line, "^(%S+)%s+(.+)$")
    if name then
      table.insert(rows, row(name, size))
    end
  end
end

local function discRows(rows)
  local limit = tonumber(S.disk_limit)
  local l = lines(data.disc)
  if limit == 0 or #l == 0 then
    return
  end
  table.insert(rows, heading("Discs"))
  for _, line in ipairs(l) do
    local _, size, used, pct, mount = string.match(line, "^(%S+)%s+(%S+)%s+(%S+)%s+(%d+)%%%s+(.+)$")
    if mount then
      table.insert(rows, row(mount, `{used} / {size}  {pct}%`, function() openDir(mount) end, tonumber(pct) >= limit))
    end
  end
end

local function cleanRows(rows)
  if S.dir_size_monitor ~= "y" then
    return
  end
  local dyn = S.dynamic_menu == "y"
  local sizes = sizeMap()
  local home = noctalia.getenv("HOME")
  local function size(path)
    return sizes[(string.gsub(path, "^~", home))] or 0
  end
  local list = {}

  -- opts: { label, run, dry, size, bad }; one option runs on click, several unfold under the row.
  local function add(id, label, value, title, opts, warn)
    local function go(o)
      runTerminal(o.title or title, o.size or "", o.dry or "", o.run)
    end
    if #opts == 1 then
      table.insert(list, row(label, value, function() go(opts[1]) end, warn))
      return
    end
    table.insert(list, row(label, value, function()
      expanded = expanded ~= id and id or nil
      render()
    end, warn))
    if expanded == id then
      for _, o in ipairs(opts) do
        table.insert(list, ui.row({ gap = 6, padding = 2 }, {
          ui.button({ text = (o.bad and "! " or "") .. o.label, variant = "ghost", controlSize = "sm", contentAlign = "start", flexGrow = 1, onClick = function() go(o) end }),
        }))
      end
    end
  end

  local function saved(key)
    return string.match(data[key] or "", "disk space saved: ([^)]+)")
  end

  local journal = string.match(data.journal or "", "take up (%S+)")
  if journal then
    local function vac(label, flag)
      return { label = label, size = "journalctl --disk-usage", run = "sudo journalctl " .. flag }
    end
    add("journal", "Logs", journal, "Vacuum the journal", {
      vac("Keep 1 day", "--vacuum-time=1d"), vac("Keep 7 days", "--vacuum-time=7d"),
      vac("Keep 200M", "--vacuum-size=200M"), vac("Keep 500M", "--vacuum-size=500M"),
    })
  end

  local pkgs = size("/var/cache/pacman/pkg")
  if pkgs > 0 and (not dyn or saved("pk3") or saved("pk1") or saved("pun")) then
    local sz = "du -sh /var/cache/pacman/pkg"
    local function pc(label, key, flag)
      local s = saved(key)
      return { label = label .. (s and `  ({s})` or ""), size = sz, dry = "paccache -d" .. flag, run = "sudo paccache -r" .. flag }
    end
    add("paccache", "Pacman cache", human(pkgs), "Clean the pacman cache", {
      pc("Keep 3 versions", "pk3", "k3"), pc("Keep 1 version", "pk1", "k1"), pc("Uninstalled packages", "pun", "uk0"),
      { label = "Remove everything", bad = true, size = sz, run = "sudo pacman -Scc" },
    })
  end

  local orphans = #lines(data.orphans)
  if orphans > 0 or not dyn then
    local function rm(label, flags, bad)
      return { label = label, bad = bad, dry = "pacman -Qi $(pacman -Qdtq) | grep -E '^(Name|Installed Size)'", run = "sudo pacman " .. flags .. " $(pacman -Qdtq)" }
    end
    if orphans == 0 then
      table.insert(list, row("Orphans", "none"))
    else
      add("orphans", "Orphans", `{orphans} pkgs`, "Remove orphaned packages", {
        rm("Remove, keep configs", "-R"), rm("Remove with dependencies", "-Rs"), rm("Remove with dependencies and configs", "-Rns", true),
      })
    end
  end

  local aurOpts = {}
  local aurDirs = { "~/.cache/paru", "~/.cache/yay", "/var/tmp/pamac-build-$USER" }
  if has("paru") then table.insert(aurOpts, { label = "paru", run = "paru -Sc --aur" }) end
  if has("yay") then table.insert(aurOpts, { label = "yay", run = "yay -Sc --aur" }) end
  if has("pamac") then table.insert(aurOpts, { label = "pamac", run = "pamac clean -b" }) end
  if #aurOpts > 0 then
    local aur = size("~/.cache/paru") + size("~/.cache/yay") + (sizes["/var/tmp/pamac-build-" .. (noctalia.getenv("USER") or "")] or 0)
    if not dyn or aur > 0 then
      for _, o in ipairs(aurOpts) do
        o.size = "du -shc " .. table.concat(aurDirs, " ") .. " 2>/dev/null"
      end
      add("aur", "AUR cache", human(aur), "Clean the AUR build cache", aurOpts)
    end
  end

  local stale = num(data.stale)
  local thumbs = size("~/.cache/thumbnails")
  if not dyn or stale > 0 or thumbs > 0 then
    local thumbFind = `find ~/.cache/thumbnails -type f -atime +{S.thumb_days}`
    add("cache", "Thumbnails / cache", human(stale), "Clean ~/.cache", {
      { label = `Thumbnails older than {S.thumb_days} days`, size = "du -sh ~/.cache/thumbnails", dry = thumbFind .. " | head -20", run = thumbFind .. " -delete" },
      { label = `All thumbnails ({human(thumbs)})`, size = "du -sh ~/.cache/thumbnails", run = "find ~/.cache/thumbnails -mindepth 1 -delete" },
      { label = `Files untouched for {S.cache_days} days`, size = staleFind("-printf '%s\\n'") .. " | " .. SUM, run = staleFind("-delete") },
    })
  end

  local devOpts = {}
  local function dev(tool, label, run, bad)
    if has(tool) then
      table.insert(devOpts, { label = label, run = run, bad = bad })
    end
  end
  dev("go", "go build cache", "go clean -cache")
  dev("go", "go module cache", "go clean -modcache", true)
  dev("npm", "npm verify", "npm cache verify")
  dev("npm", "npm clean", "npm cache clean --force")
  dev("cargo-cache", "cargo", "cargo cache --autoclean")
  dev("pip", "pip", "pip cache purge")
  dev("yarn", "yarn", "yarn cache clean")
  dev("pnpm", "pnpm", "pnpm store prune")
  if #devOpts > 0 then
    add("dev", "Developer caches", "", "Developer caches", devOpts)
  end

  local contOpts = {}
  if has("docker") and (not dyn or num(data.docker) > 0) then
    table.insert(contOpts, { label = "docker", dry = "docker system df", run = "docker system prune" })
  end
  if has("flatpak") and (not dyn or num(data.flatpak) > 0) then
    table.insert(contOpts, { label = "flatpak", dry = "flatpak uninstall --unused --assumeno", run = "flatpak uninstall --unused" })
  end
  if has("snap") and (not dyn or num(data.snap) > 0) then
    table.insert(contOpts, {
      label = "snap: remove old revisions",
      dry = "snap list --all | grep disabled",
      run = "snap list --all | awk '/disabled/{print $1, $3}' | while read -r n r; do sudo snap remove \"$n\" --revision=\"$r\"; done",
    })
  end
  if #contOpts > 0 then
    add("containers", "Containers", "", "Containers", contOpts)
  end

  if has("pacdiff") then
    local n = num(data.pacdiff)
    if not dyn or n > 0 then
      local opts = { { label = "List files", run = "find /etc -name '*.pacnew' -o -name '*.pacsave'" } }
      if has("meld") then
        table.insert(opts, { label = "Review and merge", run = "sudo DIFFPROG=meld pacdiff" })
      end
      add("leftover", "Leftover configs", `{n}`, "Leftover configs", opts)
    end
  end

  local trash = size("~/.local/share/Trash")
  if not dyn or trash > 4096 then
    add("trash", "Trash", human(trash), "Empty the trash", {
      { label = "Open the trash", run = "xdg-open trash:///" },
      { label = "Empty the trash", bad = true, size = "du -sh ~/.local/share/Trash", run = "rm -rf ~/.local/share/Trash/files ~/.local/share/Trash/info ~/.local/share/Trash/expunged" },
    })
  end

  local dlBytes, dlPath = string.match(data.downloads or "", "^(%d+)%s+(.+)$")
  if dlBytes then
    local b = tonumber(dlBytes)
    table.insert(list, row("Downloads", human(b), function() openDir(dlPath) end, b >= 1073741824))
  end

  if #list > 0 then
    table.insert(rows, heading("Directory size monitor"))
    for _, r in ipairs(list) do
      table.insert(rows, r)
    end
  end
end

-- Settings

local function choice(label, key, values)
  local buttons = {}
  for _, v in ipairs(values) do
    table.insert(buttons, ui.button({ text = v, variant = S[key] == v and "primary" or "ghost", controlSize = "sm", flexGrow = 1, onClick = function()
      setSetting(key, v)
      render()
    end }))
  end
  return ui.column({ gap = 2 }, {
    ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
    ui.row({ gap = 4 }, buttons),
  })
end

local function toggle(label, key)
  local on = S[key] == "y"
  return ui.button({ text = label, glyph = on and "square-check" or "square", variant = "ghost", controlSize = "sm", contentAlign = "start", onClick = function()
    setSetting(key, on and "n" or "y")
    render()
  end })
end

local function settingsCards()
  local cards = {}
  local function card(items)
    table.insert(cards, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, items))
  end
  if has("expac") then
    local count = tonumber(S.big_pkgs) or 10
    local function step(delta)
      return function()
        setSetting("big_pkgs", tostring(math.max(0, math.min(100, count + delta))))
        render()
      end
    end
    card({
      heading("Biggest packages"),
      ui.label({ text = "How many to list (0 hides the list, max 100)", fontSize = 11, color = "on_surface_variant" }),
      ui.row({ gap = 4, align = "center" }, {
        ui.button({ text = "-10", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = step(-10) }),
        ui.button({ text = "-1", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = step(-1) }),
        ui.label({ text = tostring(count), flexGrow = 1, textAlign = "center" }),
        ui.button({ text = "+1", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = step(1) }),
        ui.button({ text = "+10", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = step(10) }),
      }),
    })
  end
  card({ heading("Disc alert level"), choice("Warn at percent used", "disk_limit", { "0", "75", "80", "85", "90", "95" }) })
  local function colorButton(c)
    return ui.button({ text = c.name, variant = S.warn == c.hex and "primary" or "ghost", controlSize = "sm", flexGrow = 1, onClick = function()
      setSetting("warn", c.hex)
      render()
    end })
  end
  local warnItems = {
    heading("Warning color"),
    ui.label({ text = "Current " .. S.warn, color = S.warn }),
    ui.row({ gap = 4 }, { colorButton(WARN_COLORS[1]), colorButton(WARN_COLORS[2]), colorButton(WARN_COLORS[3]) }),
    ui.row({ gap = 4 }, { colorButton(WARN_COLORS[4]), colorButton(WARN_COLORS[5]) }),
    ui.button({ text = "Pick from spectrum", glyph = "palette", variant = "ghost", controlSize = "sm", onClick = function()
      noctalia.openColorPicker(S.warn, function(color)
        if color ~= nil then
          setSetting("warn", string.lower(color))
          render()
        end
      end)
    end }),
  }
  card(warnItems)
  card({
    heading("Directory size monitor"),
    toggle("Directory size monitor", "dir_size_monitor"),
    toggle("Dynamic menu", "dynamic_menu"),
    ui.label({ text = "Hide rows with nothing to clean", fontSize = 11, color = "on_surface_variant" }),
    choice("Days before a ~/.cache file is stale", "cache_days", { "7", "14", "30", "60", "90" }),
    choice("Days before a thumbnail is old", "thumb_days", { "7", "14", "30", "60" }),
    ui.label({ text = "Names in ~/.cache that are never touched", fontSize = 11, color = "on_surface_variant" }),
    ui.input({ key = "ignore", value = S.cache_ignore, onChange = function(text)
      setSetting("cache_ignore", (string.gsub(text, "[\n']", " ")))
    end }),
  })
  return cards
end

render = function()
  local rows = {}
  if view == "settings" then
    rows = settingsCards()
  else
    for _, build in ipairs({ systemRows, bigRows, discRows, cleanRows }) do
      local items = {}
      build(items)
      if #items > 0 then
        table.insert(rows, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 2 }, items))
      end
    end
    if #rows == 0 then
      table.insert(rows, ui.label({ text = "Reading system state", color = "on_surface_variant" }))
    end
  end
  local settingsView = view == "settings"
  local top = ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = settingsView and "Status settings" or (running and "Status  (updating)" or "Status"), flexGrow = 1 }),
    ui.button({ glyph = settingsView and "arrow-left" or "settings", variant = "ghost", controlSize = "sm", tooltip = settingsView and "Back" or "Settings", onClick = function()
      view = settingsView and "main" or "settings"
      if view == "main" and dirty then
        dirty = false
        refresh(false)
      end
      render()
    end }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = function()
      refresh(false)
      render()
    end }),
    ui.button({ glyph = pinned and "x" or "pin", variant = "ghost", controlSize = "sm", tooltip = pinned and "Close" or "Pin window", onClick = function()
      panel.close()
      if not pinned then
        noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/status:pinned" })
      end
    end }),
  })
  local body = ui.scroll({ gap = 8, flexGrow = 1, key = "list" }, rows)
  if pinned then
    panel.render(ui.column({ gap = 8, padding = 10, flexGrow = 1 }, { top, body }))
  else
    panel.render(ui.column({ gap = 8, padding = 12, height = 560 }, { top, body }))
  end
end

local function open()
  loadSettings()
  ticks = 0
  view = "main"
  expanded = nil
  render()
  refresh(false)
end

local function tick()
  ticks += 1
  if view == "main" and ticks - lastRun >= REFRESH then
    refresh(true)
  end
end

return open, tick
end
