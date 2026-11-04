--!nonstrict
-- Sysinfo desktop widget: replica of the Mabox sysinfo conky, colored by theme tokens.
-- CPU/RAM come from noctalia.systemStats(); the rest from shell calls.

local HISTORY = 60
local TICK_MS = 2000

local cpuHist, ramHist = {}, {}
local cpu, ramUsed, ramTotal, ramPct = 0, 0, 0, 0
local info = { distro = "", release = "", kernel = "", pkgs = "", who = "" }
local topCpu, topMem = {}, {}
local discs = {}
local bat = nil
local extra = { vpn = nil, vpnUp = false, orphans = 0, upd = {}, unchecked = false }
local ticks = 0
local procBusySince = nil

local STATIC_CMD = [[
[ -r /etc/lsb-release ] && . /etc/lsb-release
echo "1 $DISTRIB_DESCRIPTION"
echo "2 $DISTRIB_RELEASE $DISTRIB_CODENAME"
echo "3 $(uname -r | cut -d- -f1)"
echo "4 $(pacman -Q | wc -l)"
echo "5 $(whoami)@$(hostname)"
]]

-- top's second frame has per-interval CPU; the first is since process start.
local PROC_CMD = [[
top -b -n2 -d0.5 -w 100 -o %CPU | awk '/^top -/{n++} n==2 && $1 ~ /^[0-9]+$/ && $12!="top" && $12!="awk" {print "C\t"$12"\t"$9}' | head -4
top -b -n1 -w 100 -o RES | awk 'NR>7 {print "M\t"$12"\t"$6}' | head -4
df -h --output=target,used,size,pcent -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay -x fuse.portal | tail -n +2 | grep -v '^/boot' | sed 's/^/D /'
for b in /sys/class/power_supply/BAT*; do [ -r "$b/capacity" ] && echo "B $(cat "$b/capacity") $(cat "$b/status")"; done
]]

local function formatMem(mb)
  if mb >= 1024 then
    return string.format("%.1fG", mb / 1024)
  end
  return string.format("%dM", mb)
end

-- Counts come from the lists mb-updates-ce keeps (repo, AUR, flatpak, snap, npm, pipx).
local SLOW_CMD = [[
if command -v piactl >/dev/null; then echo "V $(piactl get region 2>/dev/null)"; echo "S $(piactl get connectionstate 2>/dev/null)"; fi
echo "O $(pacman -Qtdq 2>/dev/null | wc -l)"
d="${XDG_RUNTIME_DIR:-/tmp}/mb-updates"
[ -d "$d" ] || echo "N"
for s in repo aur flatpak snap npm pipx; do echo "U $s $(cat "$d/$s" 2>/dev/null | grep -c .)"; done
]]

local function push(hist, value)
  table.insert(hist, math.max(0, math.min(1, value / 100)))
  if #hist > HISTORY then
    table.remove(hist, 1)
  end
end

local function lines(text)
  local out = {}
  for line in string.gmatch(text or "", "[^\n]+") do
    table.insert(out, line)
  end
  return out
end

local function loadStatic()
  noctalia.runAsync(STATIC_CMD, function(r)
    local l = {}
    for _, line in ipairs(lines(r.stdout)) do
      local idx, text = string.match(line, "^(%d) ?(.*)")
      if idx then
        l[tonumber(idx)] = text
      end
    end
    info = { distro = l[1] or "", release = l[2] or "", kernel = l[3] or "", pkgs = l[4] or "", who = l[5] or "" }
  end)
end

local function loadSlow()
  noctalia.runAsync(SLOW_CMD, function(r)
    local e = { vpn = nil, vpnUp = false, orphans = 0, upd = {}, unchecked = false }
    for _, line in ipairs(lines(r.stdout)) do
      local tag, rest = string.match(line, "^(%u) ?(.*)")
      if tag == "V" and rest ~= "" then
        e.vpn = rest
      elseif tag == "S" then
        e.vpnUp = rest == "Connected"
      elseif tag == "N" then
        e.unchecked = true
      elseif tag == "O" then
        e.orphans = tonumber(rest) or 0
      elseif tag == "U" then
        local name, n = string.match(rest, "^(%S+) (%d+)")
        if name then
          table.insert(e.upd, { name = name, n = tonumber(n) or 0 })
        end
      end
    end
    extra = e
  end)
end

local function updatesText()
  if extra.unchecked then
    return "not checked yet", "on_surface_variant"
  end
  local total, parts = 0, {}
  for _, u in ipairs(extra.upd) do
    total += u.n
    if u.n > 0 then
      table.insert(parts, u.n .. " " .. u.name)
    end
  end
  if total == 0 then
    return "up to date", "on_surface"
  end
  return total .. " (" .. table.concat(parts, ", ") .. ")", "tertiary"
end

local function loadProcs()
  if procBusySince and os.time() - procBusySince < 15 then
    return
  end
  procBusySince = os.time()
  noctalia.runAsync(PROC_CMD, function(r)
    procBusySince = nil
    local c, m = {}, {}
    bat = nil
    local d = {}
    for _, line in ipairs(lines(r.stdout)) do
      local kind, name, val = string.match(line, "^([CM])\t(%S+)\t(%S+)")
      if kind == "C" then
        table.insert(c, { name = name, val = val .. "%" })
      elseif kind == "M" then
        local kb = tonumber(val)
        table.insert(m, { name = name, val = kb and formatMem(kb // 1024) or val })
      elseif string.sub(line, 1, 2) == "B " then
        local pct, status = string.match(line, "^B (%d+) (.+)")
        bat = { pct = tonumber(pct) or 0, status = status or "" }
      elseif string.sub(line, 1, 2) == "D " then
        local target, used, size, pct = string.match(line, "^D (.-)%s+(%S+)%s+(%S+)%s+(%d+)%%%s*$")
        if target then
          table.insert(d, { name = string.gsub(target, "^/run/media/[^/]+/", ""), used = used, size = size, pct = tonumber(pct) or 0 })
        end
      end
    end
    topCpu, topMem, discs = c, m, d
  end)
end

local function uptime()
  local secs = tonumber(string.match(noctalia.readFile("/proc/uptime") or "", "^(%d+)")) or 0
  local d, h, m = secs // 86400, (secs % 86400) // 3600, (secs % 3600) // 60
  if d > 0 then
    return string.format("%dd %dh %dm", d, h, m)
  end
  return string.format("%dh %dm", h, m)
end

local function row(left, right, rightColor)
  return ui.row({ gap = 6 }, {
    ui.label({ text = left, fontSize = 11, color = "on_surface", flexGrow = 1, maxLines = 1 }),
    ui.label({ text = right, fontSize = 11, color = rightColor or "primary" }),
  })
end

local function section(title, value, children)
  local items = {
    ui.row({ gap = 6 }, {
      ui.label({ text = title, fontSize = 11, color = "primary", flexGrow = 1 }),
      ui.label({ text = value, fontSize = 11, color = "on_surface" }),
    }),
  }
  for _, c in ipairs(children) do
    table.insert(items, c)
  end
  return items
end

local function procRows(list)
  local rows = {}
  for i, p in ipairs(list) do
    table.insert(rows, row(p.name, p.val))
  end
  return rows
end

local function render()
  local now = os.time()
  local body = {
    ui.row({ align = "center", gap = 8 }, {
      ui.column({ flexGrow = 1, gap = 0 }, {
        ui.label({ text = os.date("%A", now), fontSize = 13, color = "primary" }),
        ui.label({ text = tostring(tonumber(os.date("%d", now))) .. os.date(" %B", now), fontSize = 12, color = "on_surface_variant" }),
      }),
      ui.label({ text = os.date("%H:%M", now), fontSize = 26, color = "secondary" }),
      ui.image({ path = "/usr/share/icons/mabox-logo.svg", width = 48, height = 48, fit = "contain" }),
    }),
    ui.separator({ color = "outline_variant" }),
    row(info.distro, info.release, "on_surface_variant"),
    row(info.kernel, "kernel"),
    row("pkgs", info.pkgs, "on_surface"),
    row(info.who, uptime(), "primary"),
  }
  if extra.vpn then
    table.insert(body, row("VPN", extra.vpnUp and extra.vpn or "off", extra.vpnUp and "primary" or "on_surface_variant"))
  end
  table.insert(body, row("orphans", tostring(extra.orphans), extra.orphans > 0 and "tertiary" or "on_surface"))
  local utext, ucolor = updatesText()
  table.insert(body, row("updates", utext, ucolor))
  table.insert(body, ui.box({ height = 4 }))

  local function add(items)
    for _, n in ipairs(items) do
      table.insert(body, n)
    end
  end

  add(section("CPU", string.format("%d%%", cpu), {
    ui.graph({ values = { table.unpack(cpuHist) }, color = "tertiary", lineWidth = 1.5, fillOpacity = 0.15, height = 36 }),
  }))
  add(procRows(topCpu))
  table.insert(body, ui.box({ height = 4 }))

  add(section("RAM", string.format("%s / %s  %d%%", formatMem(ramUsed), formatMem(ramTotal), ramPct), {
    ui.graph({ values = { table.unpack(ramHist) }, color = "tertiary", lineWidth = 1.5, fillOpacity = 0.15, height = 36 }),
  }))
  add(procRows(topMem))
  table.insert(body, ui.separator({ color = "outline_variant" }))

  add(section("discs", "", {}))
  for i, dsc in ipairs(discs) do
    if i > 8 then
      break
    end
    table.insert(body, row(dsc.name, string.format("%s / %s  %d%%", dsc.used, dsc.size, dsc.pct), "on_surface"))
    table.insert(body, ui.progress({ progress = dsc.pct / 100, fill = "tertiary", track = "surface_variant", height = 4, radius = 2 }))
  end

  if bat then
    table.insert(body, ui.separator({ color = "outline_variant" }))
    table.insert(body, row("battery", string.format("%d%% %s", bat.pct, bat.status), "on_surface"))
    table.insert(body, ui.progress({ progress = bat.pct / 100, fill = "tertiary", track = "surface_variant", height = 6, radius = 3 }))
  end

  desktopWidget.render(ui.column({
    gap = 3,
    padding = 10,
    minWidth = 230,
    fill = "surface/0.85",
    radius = 8,
    border = "outline",
    borderWidth = 1,
  }, body))
end

function update()
  local s = noctalia.systemStats()
  if s ~= nil then
    cpu = s.cpu.usagePercent
    ramUsed, ramTotal, ramPct = s.ram.usedMb, s.ram.totalMb, s.ram.usagePercent
    push(cpuHist, cpu)
    push(ramHist, ramPct)
  end
  -- every 2nd tick for processes (the sample itself takes 0.5 s), every ~10 min for static info
  if ticks % 2 == 0 then
    loadProcs()
  end
  if ticks % 300 == 0 then
    loadStatic()
  end
  if ticks % 30 == 0 then
    loadSlow()
  end
  ticks += 1
  render()
end

noctalia.setUpdateInterval(TICK_MS)
desktopWidget.setWantsSecondTicks(false)
render()
