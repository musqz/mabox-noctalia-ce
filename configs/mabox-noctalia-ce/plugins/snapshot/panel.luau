--!nonstrict
-- Snapshot: front end for mabox-snapshot. Explain runs in the panel; the build runs in a terminal (sudo, passphrase).
local logo = require("./lib/celogo.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 6, border = "primary", borderWidth = 1 }
end

local PROFILES = {
  { id = "share", name = "Share with others", blurb = "Clean copy without your files or passwords. Login demo/demo.", args = { "reset" } },
  { id = "private", name = "Personal snapshot", blurb = "Full clone of this system with your files and passwords, for new hardware or backup. Keep it private.", args = { "preserving" }, encrypt = true },
  { id = "small", name = "Smallest ISO", blurb = "Clean, lean and xz-compressed. Slow to build.", args = { "reset", "--profile", "lean", "--compression", "xz" } },
  { id = "fast", name = "Quick test build", blurb = "Clean, lean and lz4. For trying the ISO in a VM.", args = { "reset", "--profile", "lean", "--compression", "lz4" } },
}

local version = nil
local outdir = nil
local workdir = nil
local settings = false
local draft = { workdir = "", output_dir = "" }
local saved = nil
local quoted = false
local armed = nil
local explain = nil
local busy = false
local render

local cfg = {}
local kernels = {}
local running = nil
local kernSel = nil
local note = nil
local encrypt = false
local function encPath()
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/encrypt") or nil
end

-- Read synchronously so the first render already knows the saved choice.
local function loadEncrypt()
  local path = encPath()
  return path ~= nil and string.match(noctalia.readFile(path) or "", "^on") ~= nil
end
local hasUsb = false
local usb = false
local hasVm = false
local isos = {}
local probed = false

local function q(v)
  return "'" .. string.gsub(v, "'", "'\\''") .. "'"
end

-- sudo ignores the user's config, so every setting goes on the command line.
local function cmdline(p)
  local has = {}
  for _, a in ipairs(p.args) do
    has[a] = true
  end
  local parts = { "mabox-snapshot", "create" }
  for _, a in ipairs(p.args) do
    table.insert(parts, a)
  end
  if p.encrypt and encrypt then
    table.insert(parts, "--encrypt")
  end
  local function flag(name, value)
    if value and value ~= "" and not has[name] then
      table.insert(parts, name)
      table.insert(parts, q(value))
    end
  end
  flag("--workdir", cfg.workdir)
  flag("--output-dir", cfg.output_dir)
  flag("--compression", cfg.compression)
  local comp = cfg.compression
  for i, a in ipairs(p.args) do
    if a == "--compression" then
      comp = p.args[i + 1]
    end
  end
  -- xz and lz4 have no level option and error out when given one.
  if comp == "zstd" or comp == "gzip" or comp == "lzo" then
    flag("--compression-level", cfg.compression_level)
  end
  flag("--exclude-list", cfg.exclude_list)
  flag("--change-threshold-mb", cfg.change_threshold_mb)
  flag("--profile", cfg.profile)
  local picked, total = {}, #kernels
  for _, k in ipairs(kernels) do
    if kernSel and kernSel[k] then
      table.insert(picked, k)
    end
  end
  if total > 0 and #picked == total then
    table.insert(parts, "--all-kernels")
  elseif #picked == 1 then
    flag("--kernel", picked[1])
  end
  for _, f in ipairs(cfg.folders or {}) do
    table.insert(parts, "--exclude-folder")
    table.insert(parts, f)
  end
  return table.concat(parts, " ")
end

local function kernelProblem()
  local n = 0
  for _, k in ipairs(kernels) do
    if kernSel and kernSel[k] then
      n = n + 1
    end
  end
  if n == 0 then
    return "Pick a kernel."
  elseif n > 1 and n < #kernels then
    return "mabox-snapshot takes one kernel or all of them. Pick one, or select all."
  end
end

local runExplain
local function probe()
  noctalia.runAsync({ "sh", "-c", "mabox-snapshot version 2>/dev/null; command -v mabox-persistence-usb >/dev/null && echo usb=1; v=$(pacman -Q quickbox-qt 2>/dev/null | cut -d' ' -f2); [ -n \"$v\" ] && [ \"$(vercmp \"$v\" 1.4)\" -ge 0 ] && echo vm=1; echo run=$(uname -r); echo; for f in /etc/mkinitcpio.d/*.preset; do b=${f##*/}; echo k=${b%.preset}; done 2>/dev/null; echo; mabox-snapshot config show 2>/dev/null; echo q=$(grep -c '^encrypt = \"' \"$HOME/.config/mabox-snapshot/mabox-snapshot.conf\" 2>/dev/null)" }, function(result)
    local out = "\n" .. (result.stdout or "")
    version = string.match(out, "mabox%-snapshot (%d+%.%d+%.%d+)")
    cfg = { folders = {} }
    for k, v in string.gmatch(out, "\n([%w_]+) = ([^\n]*)") do
      local inner = string.match(v, "^[%w]*%('(.*)'%)$") or string.match(v, "^'(.*)'$") or v
      if inner ~= "None" then
        cfg[k] = (string.gsub(inner, "^True$", "true"))
      end
      if k == "exclude_folders" then
        for name in string.gmatch(v, "'(%w+)'") do
          table.insert(cfg.folders, name)
        end
      end
    end
    local major, minor = string.match(out, "\nrun=(%d+)%.(%d+)")
    running = major and ("linux" .. major .. minor) or nil
    kernels = {}
    for k in string.gmatch(out, "\nk=([%w_%-]+)") do
      table.insert(kernels, k)
    end
    -- linux612 = 6.12, linux72 = 7.2: compare major digit, then minor.
    local function ver(k)
      local major, minor = string.match(k, "^linux(%d)(%d*)$")
      return major and (tonumber(major) * 1000 + (tonumber(minor) or 0)) or 0
    end
    table.sort(kernels, function(a, b) return ver(a) < ver(b) end)
    if kernSel == nil then
      kernSel = {}
      if cfg.all_kernels == "true" then
        for _, k in ipairs(kernels) do
          kernSel[k] = true
        end
      elseif cfg.kernel and cfg.kernel ~= "" then
        kernSel[cfg.kernel] = true
      elseif #kernels > 0 then
        kernSel[kernels[#kernels]] = true
      end
    end
    outdir = cfg.output_dir
    workdir = cfg.workdir
    draft.workdir, draft.output_dir = workdir or "", outdir or ""
    quoted = string.match(out, "q=1") ~= nil
    hasUsb = string.match(out, "usb=1") ~= nil
    hasVm = string.match(out, "vm=1") ~= nil
    probed = true
    render()
  end)
end

local function older(v, want)
  local a, b, c = string.match(v, "(%d+)%.(%d+)%.(%d+)")
  local x, y, z = string.match(want, "(%d+)%.(%d+)%.(%d+)")
  a, b, c, x, y, z = tonumber(a), tonumber(b), tonumber(c), tonumber(x), tonumber(y), tonumber(z)
  return (a * 1000000 + b * 1000 + c) < (x * 1000000 + y * 1000 + z)
end

-- The tool hard-wraps at 80 columns and aligns a table with spaces; join the wrapped lines so the panel font can wrap them.
local function tidy(text)
  local out = {}
  local fresh = true
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    if string.match(line, "^%s*$") then
      table.insert(out, "")
      fresh = true
    else
      local key, value = string.match(line, "^%s+([%a][%a ]-):%s%s+(.*)$")
      local step = string.match(line, "^%s*%d+%. ")
      local trimmed = string.gsub(string.gsub(line, "^%s+", ""), "%s+$", "")
      if key then
        table.insert(out, key .. ": " .. value)
      elseif step or fresh or not string.match(line, "^%s") then
        if step and #out > 0 and out[#out] ~= "" then
          table.insert(out, "")
        end
        table.insert(out, trimmed)
      else
        out[#out] = out[#out] .. (string.sub(out[#out], -1) == "-" and "" or " ") .. trimmed
      end
      fresh = false
    end
  end
  return table.concat(out, "\n")
end

runExplain = function(p)
  if busy then
    return
  end
  note = kernelProblem()
  if note then
    render()
    return
  end
  armed = nil
  busy = true
  render()
  local cmd = cmdline(p)
  noctalia.runAsync({ "sh", "-c", cmd .. " --explain 2>&1" }, function(result)
    busy = false
    explain = { name = p.name, cmd = "$ " .. cmd, text = (result.stdout or "") ~= "" and tidy(result.stdout) or "No output." }
    render()
  end)
end

local function build(p)
  armed = nil
  note = kernelProblem()
  if note then
    render()
    return
  end
  local script = "printf '\\033[1m$ %s\\033[0m\\n\\n' " .. q("sudo " .. cmdline(p)) .. "; sudo " .. cmdline(p)
    .. "; s=$?; echo; if [ $s -eq 0 ]; then echo Done.; " .. (outdir and ("command -v mb-iso-next >/dev/null && mb-iso-next " .. q(outdir) .. "; ") or "") .. "else echo \"Failed (exit code $s).\"; fi; printf 'Press Enter to close. '; read _"
  -- setsid: the terminal would die with the panel when it loses focus.
  noctalia.runAsync({ "sh", "-c", 'command -v foot >/dev/null || { notify-send -u critical "Snapshot" "foot is not installed"; exit 1; }; setsid -f foot -T "Mabox Snapshot" sh -c "$1"', "sh", script })
  panel.close()
end

local function setEncrypt(on)
  encrypt = on
  armed = nil
  note = nil
  local path = encPath()
  if path then
    noctalia.mkdirAll(noctalia.pluginDataDir())
    noctalia.writeFile(path, on and "on\n" or "off\n")
  end
  render()
end

local function save()
  local cmd, changed = "", false
  for _, key in ipairs({ "workdir", "output_dir" }) do
    local v = (string.gsub(draft[key], "^%s+", ""))
    v = string.gsub(v, "%s+$", "")
    local current = outdir
    if key == "workdir" then
      current = workdir
    end
    if v ~= "" and v ~= current then
      changed = true
      cmd = cmd .. "mabox-snapshot config set " .. key .. " " .. q(v) .. " || exit 1; "
    end
  end
  if not changed then
    saved = "Nothing changed."
    render()
    return
  end
  noctalia.runAsync({ "sh", "-c", cmd .. "true" }, function(result)
    saved = (result.exitCode == nil or result.exitCode == 0) and "Saved." or "Could not save the settings."
    probe()
  end)
end

local loadingIsos = false

-- Skips files touched in the last 2 minutes: a build that is still writing its ISO.
local function loadIsos()
  isos = {}
  if not outdir then
    return
  end
  loadingIsos = true
  noctalia.runAsync({ "sh", "-c", 'find "$1" -maxdepth 1 -name "*.iso" -mmin +2 -printf "%T@ %s %p\\n" | sort -rn | head -n 8', "sh", outdir }, function(result)
    loadingIsos = false
    for mtime, size, path in string.gmatch((result.stdout or "") .. "\n", "(%d+)%.?%d* (%d+) ([^\n]+)\n") do
      table.insert(isos, { size = tonumber(size), mtime = tonumber(mtime), path = path })
    end
    render()
  end)
end

local function startVm(path)
  noctalia.runAsync({ "setsid", "-f", "quickbox", "--iso", path })
  panel.close()
end

-- The tool asks for the stick and a typed confirmation itself; setsid keeps the terminal alive when the panel closes.
local function writeIso(path)
  noctalia.runAsync({ "setsid", "-f", "foot", "-T", "Snapshot USB", "sh", "-c", 'sudo mabox-persistence-usb write "$1"; printf "Press Enter to close. "; read _', "sh", path })
  panel.close()
end

local function usbView()
  local rows = {
    ui.label({ text = "Newest ISOs" .. (outdir and (" in " .. outdir) or "") .. ". The stick gets a persistence partition and is erased. More options: mabox-persistence-usb write --help in a terminal.", fontSize = 11, color = "on_surface_variant" }),
  }
  for i, iso in ipairs(isos) do
    local name = string.match(iso.path, "([^/]+)$")
    table.insert(rows, ui.row(card("iso-" .. i), {
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = name, fontSize = 12, fontWeight = "bold" }),
        ui.label({ text = os.date("%x %H:%M", iso.mtime) .. "  " .. string.format("%.1f GiB", iso.size / 1073741824), fontSize = 11, color = "on_surface_variant" }),
      }),
      hasUsb and ui.button({ text = "USB", variant = "outline", controlSize = "sm", tooltip = "Write this ISO to a USB stick", onClick = function() writeIso(iso.path) end }) or nil,
      hasVm and ui.button({ text = "VM", variant = "outline", controlSize = "sm", tooltip = "Start this ISO in a VM with quickbox", onClick = function() startVm(iso.path) end }) or nil,
    }))
  end
  if loadingIsos then
    table.insert(rows, ui.label({ text = "Reading ISOs...", color = "on_surface_variant" }))
  elseif not outdir then
    table.insert(rows, ui.label({ text = "No ISO folder set. Open the settings (gear) and set the ISO folder.", color = "primary" }))
  elseif #isos == 0 then
    table.insert(rows, ui.label({ text = "No finished ISO found.", color = "on_surface_variant" }))
  end
  return ui.column({ gap = 10 }, rows)
end

local function settingsView()
  local function field(label, key)
    return ui.column({ key = "f-" .. key, gap = 2 }, {
      ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
      ui.input({ key = "in-" .. key, value = draft[key], onChange = function(text) draft[key] = text end }),
    })
  end
  return ui.column(card("settings"), {
    field("Work folder (scratch space, needs about the size of the system)", "workdir"),
    field("ISO folder (where the finished .iso is written)", "output_dir"),
    ui.row({ gap = 6, align = "center" }, {
      ui.button({ text = "Save", variant = "primary", controlSize = "sm", onClick = save }),
      ui.label({ text = saved or "", fontSize = 11, color = "on_surface_variant" }),
    }),
  })
end

local function kernelRow()
  local btns = {}
  for _, k in ipairs(kernels) do
    local on = kernSel and kernSel[k] or false
    table.insert(btns, ui.button({ key = "k-" .. k, text = (on and "✓ " or "") .. k, variant = on and "outline" or "ghost", controlSize = "sm", tooltip = "Kernel in the ISO", onClick = function()
      kernSel[k] = not on or nil
      armed = nil
      note = nil
      render()
    end }))
  end
  local picked = 0
  for _, k in ipairs(kernels) do
    if kernSel and kernSel[k] then
      picked = picked + 1
    end
  end
  local all = #kernels > 0 and picked == #kernels
  local only = running
  local known = false
  for _, k in ipairs(kernels) do
    known = known or k == only
  end
  if not known then
    only = kernels[#kernels]
  end
  if #kernels > 1 then
    table.insert(btns, ui.button({ key = "k-all", text = all and "✓ All" or "All", variant = all and "outline" or "ghost", controlSize = "sm", tooltip = all and (known and "Keep only the running kernel" or "Keep only the newest kernel") or "Every installed kernel", onClick = function()
      for _, k in ipairs(kernels) do
        kernSel[k] = (not all) or k == only or nil
      end
      armed = nil
      note = nil
      render()
    end }))
  end
  -- Three buttons per row: the panel is 420 px wide and a row does not wrap.
  local children = { ui.label({ text = "Kernel in the ISO", fontSize = 11, color = "on_surface_variant" }) }
  for i = 1, #btns, 3 do
    table.insert(children, ui.row({ key = "kr-" .. i, gap = 6, align = "center" }, { table.unpack(btns, i, math.min(i + 2, #btns)) }))
  end
  return ui.column(card("kernels"), children)
end

local function profileCard(p)
  local sure = armed == p.id
  return ui.column(card("p-" .. p.id), {
    ui.label({ text = p.name, fontWeight = "bold", fontSize = 14 }),
    ui.label({ text = p.blurb, fontSize = 11, color = "on_surface_variant" }),
    p.encrypt and ui.button({ key = "enc-" .. p.id, text = encrypt and "✓ Encrypted (LUKS2)" or "Encrypted (LUKS2): off", variant = encrypt and "outline" or "ghost", controlSize = "sm", tooltip = "Lock the ISO with a passphrase; you type it in the terminal", onClick = function()
      setEncrypt(not encrypt)
    end }) or ui.label({ key = "enc-" .. p.id, text = "", fontSize = 1 }),
    sure and ui.label({ key = "cmd-" .. p.id, text = "sudo " .. cmdline(p), fontSize = 10, color = "on_surface_variant" }) or ui.label({ key = "cmd-" .. p.id, text = "", fontSize = 1 }),
    ui.row({ gap = 6, align = "center" }, {
      ui.button({ text = "Explain", variant = "outline", controlSize = "sm", tooltip = "Show what the build will do", onClick = function() runExplain(p) end }),
      ui.button({
        text = sure and "Confirm build" or "Build",
        variant = sure and "destructive" or "outline",
        controlSize = "sm",
        tooltip = "Build the ISO in a terminal",
        onClick = function()
          if sure then
            build(p)
          else
            armed = p.id
            render()
          end
        end,
      }),
    }),
  })
end

render = function()
  if usb and not explain and not settings then
    panel.render(ui.column({ key = "root-usb", gap = 8, padding = 12 }, {
      ui.row({ gap = 6, align = "center" }, {
        logo(),
        ui.label({ text = "Write an ISO to USB", flexGrow = 1 }),
        ui.button({ glyph = "arrow-left", variant = "ghost", controlSize = "sm", tooltip = "Back", onClick = function()
          usb = false
          render()
        end }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
      }),
      usbView(),
    }))
    return
  end
  local nav
  if explain then
    nav = ui.button({ glyph = "arrow-left", variant = "ghost", controlSize = "sm", tooltip = "Back", onClick = function()
      explain = nil
      armed = nil
      render()
    end })
  else
    nav = ui.button({ glyph = settings and "arrow-left" or "settings", variant = "ghost", controlSize = "sm", tooltip = settings and "Back" or "Settings", onClick = function()
      settings = not settings
      saved = nil
      render()
    end })
  end
  local top = ui.row({ gap = 6, align = "center" }, {
    logo(),
    ui.label({ text = explain and ("Explain: " .. explain.name) or (settings and "Snapshot settings" or "Snapshot"), flexGrow = 1 }),
    nav,
    ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
  })
  local body
  if settings and not explain then
    body = settingsView()
  elseif explain then
    body = ui.scroll({ flexGrow = 1, key = "explain" }, { ui.column({ gap = 8, padding = 4 }, { ui.label({ text = explain.cmd, fontSize = 11, color = "on_surface_variant" }), ui.label({ text = explain.text, fontSize = 12 }) }) })
  else
    local rows = {}
    if not probed then
      table.insert(rows, ui.label({ text = "Reading settings...", color = "on_surface_variant" }))
    elseif version == nil then
      table.insert(rows, ui.label({ text = "mabox-snapshot is not installed.", color = "primary" }))
    else
      table.insert(rows, ui.label({ text = "mabox-snapshot " .. version .. (outdir and ("  ->  " .. outdir) or ""), fontSize = 11, color = "on_surface_variant" }))
      if quoted and older(version, "0.3.4") then
        table.insert(rows, ui.label({ text = "Config has encrypt = \"false\" with quotes: builds in reset mode fail. Remove the quotes or update to 0.3.4.", fontSize = 11, color = "primary" }))
      end
      table.insert(rows, kernelRow())
      for _, p in ipairs(PROFILES) do
        table.insert(rows, profileCard(p))
      end
      if hasUsb or hasVm then
        table.insert(rows, ui.column(card("usb-card"), {
          ui.label({ text = hasUsb and "USB stick or VM" or "VM", fontWeight = "bold", fontSize = 14 }),
          ui.label({ text = "Write one of the newest ISOs to a USB stick (mabox-persistence-usb, the stick is erased) or start it in a VM.", fontSize = 11, color = "on_surface_variant" }),
          ui.button({ key = "usb", text = "Choose an ISO...", variant = "outline", controlSize = "sm", onClick = function()
            usb = true
            loadIsos()
            render()
          end }),
        }))
      end
      table.insert(rows, ui.label({ text = note or (busy and "Reading plan..." or "Build asks for your sudo password in the terminal."), fontSize = 11, color = note and "primary" or "on_surface_variant" }))
    end
    body = ui.column({ gap = 10 }, rows)
  end
  -- A scroll in a content-height panel collapses; a fixed height on the column lets it scroll. The key keeps the fixed height from sticking to the list view.
  panel.render(ui.column({ key = explain and "root-explain" or "root", gap = 8, padding = 12, height = explain and 780 or nil }, { top, body }))
end

function onOpen()
  encrypt = loadEncrypt()
  armed, explain, busy, settings, saved, note, usb = nil, nil, false, false, nil, nil, false
  render()
  probe()
end
