--!nonstrict
-- Cava: front end for cavactl (colors, bars, framerate) and the transparent cava window (mb-cava).
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local cfg = {}
local LAYER_FILE = '"${XDG_STATE_HOME:-$HOME/.local/state}/mabox-noctalia-ce/cava-layer"'
local running = false
local loaded = false
local armed = false
local busy = false
local render

-- First uncommented "key = value" wins; a quoted value loses its quotes.
local function parse(text)
  local out = {}
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    local k, v = string.match(line, "^([%w_]+)%s*=%s*(.-)%s*$")
    if k and out[k] == nil then
      out[k] = (string.gsub(v, "^'(.*)'$", "%1"))
    end
  end
  return out
end

local FOLLOW_FILE = '"$HOME/.config/mabox-noctalia-ce/cava-follow"'

local function load()
  noctalia.runAsync({ "sh", "-c", 'cat "$HOME/.config/cava/config" 2>/dev/null; echo; echo "cavactl=$(command -v cavactl)"; echo "running=$(wlrctl toplevel find app_id:cava-transparent >/dev/null 2>&1 && echo 1)"; echo "layer=$(cat ' .. LAYER_FILE .. ' 2>/dev/null)"; echo "cavawidth=$(wlr-randr --json 2>/dev/null | jq -r \'[.[] | select(.enabled)][0] | (.modes[] | select(.current)) as $m | (if (.transform | tostring | test("90|270")) then $m.height else $m.width end) as $w | ($w / .scale * 0.6 | floor)\' 2>/dev/null)"; echo "follow_pair=$(sed -n \'s/^pair=//p\' ' .. FOLLOW_FILE .. ' 2>/dev/null)"; echo "follow_style=$(sed -n \'s/^style=//p\' ' .. FOLLOW_FILE .. ' 2>/dev/null)"; echo "--theme"; cat "$HOME/.config/cava/themes/noctalia" 2>/dev/null' }, function(result)
    local out = result.stdout or ""
    local cfgText, themeText = string.match(out, "^(.-)\n%-%-theme\n(.*)$")
    cfg = parse(cfgText or out)
    -- The colors of the followed theme, kept apart from the manual gradient (keys T_1, T_2, ...).
    for k, v in pairs(parse(themeText or "")) do
      local n = string.match(k, "^gradient_color_(%d)$")
      if n then
        cfg["T_" .. n] = v
      end
    end
    running = cfg.running == "1"
    loaded = true
    render()
  end)
end

local afterWrite = nil
local function finishWrite()
  load()
  if afterWrite then
    local f = afterWrite
    afterWrite = nil
    f()
  end
end

local function ctl(...)
  armed = false
  local argv = { "cavactl", ... }
  noctalia.runAsync(argv, function()
    finishWrite()
  end)
end

local function color(key)
  local c = cfg[key]
  if c and string.match(c, "^#%x%x%x%x%x%x$") then
    return c
  end
  return nil
end

-- Click a pixel on the screen with mb-colorpick. The panel closes meanwhile so it does not cover what you pick from.
-- apply() starts the config write and returns true; the panel reopens once that write has finished.
local colorNote = nil
local function pickFromScreen(apply)
  panel.close()
  colorNote = nil
  local function reopen()
    noctalia.runAsync({ "noctalia", "msg", "panel-open", "mabox/cava:main" })
  end
  noctalia.runAsync({ "mb-colorpick" }, function(result)
    if result.exitCode == 127 then
      colorNote = "mb-colorpick is not installed."
    end
    local hex = result.exitCode == 0 and string.match(result.stdout or "", "#%x%x%x%x%x%x") or nil
    if hex then
      afterWrite = reopen
      if not apply(string.lower(hex)) then
        afterWrite = nil
        reopen()
      end
    else
      reopen()
    end
  end)
end

local function swatch(label, key, command)
  local hex = color(key)
  return ui.row({ key = "sw-" .. key, gap = 8, align = "center" }, {
    ui.box({ fill = hex or "surface", radius = 6, width = 28, height = 28, border = "on_surface_variant", borderWidth = 1 }),
    ui.label({ text = label .. "  " .. (hex or "(not a hex color)"), flexGrow = 1 }),
    ui.button({ text = "Pick", variant = "outline", controlSize = "sm", onClick = function()
      noctalia.openColorPicker(hex or "#59cc33", function(picked)
        -- cavactl writes the value into the config as is, so only a plain #rrggbb goes through.
        if picked ~= nil and string.match(picked, "^#%x%x%x%x%x%x$") then
          ctl(command, string.lower(picked))
        end
      end)
    end }),
    ui.button({ text = "Screen", variant = "outline", controlSize = "sm", tooltip = "Pick a color from the screen", onClick = function()
      pickFromScreen(function(picked)
        ctl(command, picked)
        return true
      end)
    end }),
  })
end

-- Rows of five: a column is about 373 px wide and a row does not wrap.
local function choices(title, key, values, command)
  local current = cfg[key]
  local children = { ui.label({ text = title .. (current and ("   " .. current) or ""), fontSize = 12 }) }
  local btns = {}
  for _, v in ipairs(values) do
    local on = current == v
    table.insert(btns, ui.button({ key = key .. "-" .. v, text = (on and "✓ " or "") .. v, variant = on and "primary" or "outline", controlSize = "sm", onClick = function()
      ctl(command, v)
    end }))
  end
  for i = 1, #btns, 5 do
    table.insert(children, ui.row({ key = key .. "-r" .. i, gap = 6, align = "center" }, { table.unpack(btns, i, math.min(i + 4, #btns)) }))
  end
  return ui.column({ key = "ch-" .. key, gap = 6 }, children)
end

local LAYERS = { { "normal", "Normal" }, { "top", "Always on top" }, { "below", "Always below" } }

-- The layer is read by mb-cava when it opens the window, so a running window is restarted.
local function setLayer(value)
  if busy then
    return
  end
  busy = true
  armed = false
  noctalia.runAsync({ "sh", "-c", 'mkdir -p "$(dirname ' .. LAYER_FILE .. ')" && echo ' .. value .. ' > ' .. LAYER_FILE }, function()
    if running then
      -- Wait until the old window is gone, or a second one would open next to it.
      noctalia.runAsync({ "sh", "-c", 'wlrctl toplevel close app_id:cava-transparent; for i in 1 2 3 4 5 6 7 8 9 10; do wlrctl toplevel find app_id:cava-transparent >/dev/null 2>&1 || break; sleep 0.3; done' }, function()
        noctalia.runAsync({ "setsid", "-f", "mb-cava" })
        noctalia.runAsync({ "sleep", "1.5" }, function()
          busy = false
          load()
        end)
      end)
    else
      busy = false
      load()
    end
  end)
  render()
end

local function windowCard()
  local label = busy and "Please wait..." or (running and "Stop cava" or "Start cava")
  local current = cfg.layer or ""
  if current ~= "top" and current ~= "below" then
    current = "normal"
  end
  local layerBtns = {}
  for _, l in ipairs(LAYERS) do
    local on = current == l[1]
    table.insert(layerBtns, ui.button({ key = "layer-" .. l[1], text = (on and "✓ " or "") .. l[2], variant = on and "primary" or "outline", controlSize = "sm", onClick = function()
      setLayer(l[1])
    end }))
  end
  return ui.column(card("window"), {
    ui.label({ text = "Window", fontWeight = "bold", fontSize = 14 }),
    ui.label({ text = "Frameless transparent cava, bottom centre.", fontSize = 11, color = "on_surface_variant" }),
    ui.button({ key = "toggle", text = label, variant = "outline", controlSize = "sm", onClick = function()
      if busy then
        return
      end
      busy = true
      armed = false
      noctalia.runAsync({ "setsid", "-f", "mb-cava", "toggle" })
      -- The window opens and closes a moment after the command returns.
      noctalia.runAsync({ "sleep", "1.5" }, function()
        busy = false
        load()
      end)
      render()
    end }),
    ui.label({ text = "Layer", fontSize = 12 }),
    ui.row({ key = "layer-row", gap = 6, align = "center" }, layerBtns),
  })
end

local MAX_COLORS = 8

local function gradientColors()
  local n = math.max(2, math.min(MAX_COLORS, tonumber(cfg.gradient_count) or 3))
  local out, last = {}, "#59cc33"
  for i = 1, n do
    last = color("gradient_color_" .. i) or last
    out[i] = last
  end
  return out
end

-- cavactl only knows three colors; this writes gradient_count and gradient_color_1..8 straight into the cava config.
-- One sed call keeps it a single rewrite; clicks wait until the file is read back.
local writing = false
local function writeGradient(colors)
  if writing then
    return false
  end
  writing = true
  armed = false
  local exprs = {}
  for i, c in ipairs(colors) do
    table.insert(exprs, string.format("-e \"s|^[ ;]*gradient_color_%d .*|gradient_color_%d = '%s'|\"", i, i, c))
  end
  table.insert(exprs, string.format("-e 's|^[ ;]*gradient_count .*|gradient_count = %d|'", #colors))
  local cmd = 'sed -i -E --follow-symlinks ' .. table.concat(exprs, " ") .. ' "$HOME/.config/cava/config"; pkill -x -USR1 cava; true'
  noctalia.runAsync({ "sh", "-c", cmd }, function()
    writing = false
    finishWrite()
  end)
  return true
end

local selected = 1

local function gradientEditor()
  local colors = gradientColors()
  if selected > #colors then
    selected = #colors
  end
  local boxes = {}
  for i, c in ipairs(colors) do
    local on = i == selected
    table.insert(boxes, ui.box({ key = "gc-" .. i, fill = c, radius = 6, width = 44, height = 32, border = on and "primary" or "on_surface_variant", borderWidth = on and 3 or 1, tooltip = i .. "  " .. c, onClick = function()
      selected = i
      render()
    end }))
  end
  local rows = { ui.label({ text = "Select a color, then Pick or Screen. " .. #colors .. " of " .. MAX_COLORS .. " colors, bottom to top.", fontSize = 12 }) }
  for i = 1, #boxes, 4 do
    table.insert(rows, ui.row({ key = "gr-" .. i, gap = 6, align = "center" }, { table.unpack(boxes, i, math.min(i + 3, #boxes)) }))
  end
  local function setSelected(hex)
    local cur = gradientColors()
    cur[math.min(selected, #cur)] = hex
    return writeGradient(cur)
  end
  table.insert(rows, ui.row({ key = "g-sel", gap = 6, align = "center" }, {
    ui.label({ text = "Color " .. selected .. "  " .. colors[selected], flexGrow = 1 }),
    ui.button({ key = "g-pick", text = "Pick", variant = "outline", controlSize = "sm", onClick = function()
      noctalia.openColorPicker(colors[selected], function(picked)
        if picked ~= nil and string.match(picked, "^#%x%x%x%x%x%x$") then
          setSelected(string.lower(picked))
        end
      end)
    end }),
    ui.button({ key = "g-screen", text = "Screen", variant = "outline", controlSize = "sm", tooltip = "Pick a color from the screen", onClick = function()
      pickFromScreen(setSelected)
    end }),
  }))
  local btns = {}
  if #colors < MAX_COLORS then
    table.insert(btns, ui.button({ key = "g-add", text = "+ Add", variant = "outline", controlSize = "sm", onClick = function()
      local new = { table.unpack(colors) }
      table.insert(new, colors[#colors])
      selected = #new
      writeGradient(new)
    end }))
  end
  if #colors > 2 then
    table.insert(btns, ui.button({ key = "g-del", text = "- Remove", variant = "outline", controlSize = "sm", onClick = function()
      local new = { table.unpack(colors, 1, #colors - 1) }
      writeGradient(new)
    end }))
  end
  table.insert(btns, ui.button({ key = "g-rev", text = "Reverse", variant = "outline", controlSize = "sm", onClick = function()
    local new = {}
    for i = #colors, 1, -1 do
      table.insert(new, colors[i])
    end
    selected = #colors + 1 - selected
    writeGradient(new)
  end }))
  table.insert(rows, ui.row({ key = "g-btns", gap = 6, align = "center" }, btns))
  return ui.column({ key = "gradient-editor", gap = 8 }, rows)
end

-- A Noctalia template writes ~/.config/cava/themes/noctalia from the wallpaper colors; theme = 'noctalia' makes cava use it.
local followError = nil

local function setFollow(on)
  if writing then
    return
  end
  writing = true
  armed = false
  followError = nil
  render()
  local cfgFile = '"$HOME/.config/cava/config"'
  local palette = '"$HOME/.cache/mabox-noctalia-ce/cava-palette"'
  local cmd
  if on then
    -- Noctalia renders the palette on every wallpaper change, so it normally exists; only wait for it on a first run.
    cmd = '[ -f ' .. palette .. ' ] || { noctalia msg templates-apply; for i in 1 2 3 4 5 6; do [ -f ' .. palette .. ' ] && break; sleep 0.5; done; }; '
      .. 'mb-cava-theme --force && sed -i -E --follow-symlinks "s|^[ ;]*theme = .*|theme = \'noctalia\'|" ' .. cfgFile .. ' && mb-cava-theme'
  else
    -- Back to the manual gradient: gradient_count must match the colors that are defined.
    cmd = 'sed -i -E --follow-symlinks "s|^[ ;]*theme = .*|; theme = \'none\'|" ' .. cfgFile .. '; '
      .. 'n=$(grep -oE "^gradient_color_[1-8] " ' .. cfgFile .. ' | sort -u | wc -l); [ "$n" -ge 2 ] && sed -i -E --follow-symlinks "s|^[ ;]*gradient_count .*|gradient_count = $n|" ' .. cfgFile .. '; '
      .. 'pkill -x -USR1 cava; true'
  end
  noctalia.runAsync({ "sh", "-c", cmd }, function(result)
    writing = false
    if on and result.exitCode ~= 0 then
      followError = "Could not build the colors. Is pastel installed?"
    end
    load()
  end)
end

-- The pair and style of the followed colors live in cava-follow; mb-cava-theme rebuilds the theme from them.
local function setFollowOption(key, value)
  if writing then
    return
  end
  writing = true
  local cmd = 'f=' .. FOLLOW_FILE .. '; mkdir -p "$(dirname "$f")"; touch "$f"; sed -i "/^' .. key .. '=/d" "$f"; echo "' .. key .. '=' .. value .. '" >> "$f"; mb-cava-theme'
  noctalia.runAsync({ "sh", "-c", cmd }, function()
    writing = false
    load()
  end)
end

local function followOptions(rows)
  local pair = cfg.follow_pair or ""
  if pair ~= "ps" and pair ~= "st" then
    pair = "pt"
  end
  local style = cfg.follow_style or ""
  if style ~= "soft" and style ~= "palette" then
    style = "vivid"
  end
  local function choice(key, current, value, name, tip)
    local on = current == value
    return ui.button({ key = "f-" .. key .. value, text = (on and "✓ " or "") .. name, variant = on and "primary" or "outline", controlSize = "sm", flexGrow = 1, tooltip = tip, onClick = function()
      setFollowOption(key, value)
    end })
  end
  table.insert(rows, ui.label({ text = "Colors", fontSize = 11, color = "on_surface_variant" }))
  table.insert(rows, ui.row({ gap = 6 }, { choice("pair", pair, "pt", "Pri + Ter", "Primary and tertiary"), choice("pair", pair, "ps", "Pri + Sec", "Primary and secondary"), choice("pair", pair, "st", "Sec + Ter", "Secondary and tertiary") }))
  table.insert(rows, ui.label({ text = "Style", fontSize = 11, color = "on_surface_variant" }))
  table.insert(rows, ui.row({ gap = 6 }, { choice("style", style, "vivid", "Vivid"), choice("style", style, "soft", "Soft"), choice("style", style, "palette", "Palette") }))
end

local function colorCard()
  local gradient = cfg.gradient == "1"
  local function mode(name, on, value)
    return ui.button({ key = "mode-" .. value, text = (on and "✓ " or "") .. name, variant = on and "primary" or "outline", controlSize = "sm", onClick = function()
      ctl("mode", value)
    end })
  end
  local following = cfg.theme == "noctalia"
  local rows = {
    ui.label({ text = "Color", fontWeight = "bold", fontSize = 14 }),
    ui.button({ key = "follow", text = writing and "Please wait..." or ((following and "✓ " or "") .. "Follow wallpaper colors"), variant = following and "primary" or "outline", controlSize = "sm", onClick = function()
      setFollow(not following)
    end }),
  }
  if followError or colorNote then
    table.insert(rows, ui.label({ text = followError or colorNote, fontSize = 11, color = "primary" }))
  end
  if following then
    table.insert(rows, ui.label({ text = "The bars use 2 colors from the Noctalia palette and change with the wallpaper.", fontSize = 11, color = "on_surface_variant" }))
    followOptions(rows)
    return ui.column(card("color"), rows)
  end
  table.insert(rows, ui.row({ gap = 6, align = "center" }, { mode("Solid", not gradient, "solid"), mode("Gradient", gradient, "gradient") }))
  if gradient then
    table.insert(rows, gradientEditor())
  else
    table.insert(rows, swatch("Bar color", "foreground", "foreground"))
  end
  return ui.column(card("color"), rows)
end

local function barsCard()
  return ui.column(card("bars"), {
    ui.label({ text = "Bars", fontWeight = "bold", fontSize = 14 }),
    choices("Bar width", "bar_width", { "1", "2", "3", "4", "5", "6", "8", "10", "20" }, "bar_width"),
    choices("Bar spacing", "bar_spacing", { "0", "1", "2", "3", "4", "5", "6", "8", "10" }, "bar_spacing"),
  })
end

-- cavactl has no reverse command; write the key straight into the cava config like the gradient does.
local function setReverse(value)
  armed = false
  noctalia.runAsync({ "sh", "-c", 'sed -i -E --follow-symlinks "s|^[ ;]*reverse *=.*|reverse = ' .. value .. '|" "$HOME/.config/cava/config"; pkill -x -USR1 cava; true' }, function()
    finishWrite()
  end)
end

local function reverseChoice()
  local on = cfg.reverse == "1"
  return ui.column({ key = "ch-reverse", gap = 6 }, {
    ui.label({ text = "Reverse frequencies   " .. (on and "on" or "off"), fontSize = 12 }),
    ui.row({ key = "reverse-r", gap = 6, align = "center" }, {
      ui.button({ key = "reverse-0", text = (on and "" or "✓ ") .. "Off", variant = on and "outline" or "primary", controlSize = "sm", onClick = function() setReverse(0) end }),
      ui.button({ key = "reverse-1", text = (on and "✓ " or "") .. "On", variant = on and "primary" or "outline", controlSize = "sm", onClick = function() setReverse(1) end }),
    }),
  })
end

local function generalCard()
  return ui.column(card("general"), {
    ui.label({ text = "General", fontWeight = "bold", fontSize = 14 }),
    choices("Framerate", "framerate", { "60", "120", "144" }, "framerate"),
    choices("Noise reduction", "noise_reduction", { "90", "77", "50", "25" }, "noise_reduction"),
    reverseChoice(),
  })
end

local function configRow()
  return ui.row({ key = "cfg-row", gap = 6, align = "center" }, {
    ui.button({ text = "Edit config", variant = "outline", controlSize = "sm", onClick = function()
      noctalia.runAsync({ "sh", "-c", 'xdg-open "$HOME/.config/cava/config"' })
      panel.close()
    end }),
    ui.button({ text = armed and "Confirm reset" or "Reset config", variant = armed and "destructive" or "outline", controlSize = "sm", onClick = function()
      if armed then
        ctl("resetcfg")
      else
        armed = true
        render()
      end
    end }),
  })
end

-- Still spectrum for the header: bar width, spacing and colors follow the cava settings, whether or not cava runs.
local SPECTRUM_HEIGHT = 60
-- Usable width: plugin.toml width (780) minus the panel's own padding and ours (about 26 px on each side).
local SPECTRUM_WIDTH = 728
-- Each of the two columns, with a 10 px gap between them.
local COLUMN_WIDTH = (SPECTRUM_WIDTH - 10) // 2
-- The real window is the cava window of mb-cava: 60% of the output, one terminal cell (foot, font size 2) is 2 px.
local CELL_PX = 2
local DEFAULT_CAVA_WIDTH = 1535
-- Noctalia limits a callback to 25 ms of CPU, so the header has a bar limit and a few colored boxes per bar.
-- Beyond MAX_BARS the bars are drawn wider than the settings say, to keep the full width.
local MAX_BARS = 96
local SPECTRUM_BANDS = 4

local function hexToRgb(hex)
  return tonumber(string.sub(hex, 2, 3), 16), tonumber(string.sub(hex, 4, 5), 16), tonumber(string.sub(hex, 6, 7), 16)
end

-- Colors from bottom to top: the followed theme, the manual gradient, or the single bar color.
local function spectrumStops()
  if cfg.theme == "noctalia" then
    local stops = {}
    for i = 1, MAX_COLORS do
      local c = cfg["T_" .. i]
      if c and string.match(c, "^#%x%x%x%x%x%x$") then
        table.insert(stops, c)
      end
    end
    if #stops >= 1 then
      return stops
    end
  end
  if cfg.gradient == "1" then
    return gradientColors()
  end
  return { color("foreground") or "#59cc33" }
end

local function stopAt(stops, t)
  if #stops == 1 then
    return stops[1]
  end
  local pos = t * (#stops - 1)
  local i = math.min(#stops - 2, math.floor(pos))
  local f = pos - i
  local r1, g1, b1 = hexToRgb(stops[i + 1])
  local r2, g2, b2 = hexToRgb(stops[i + 2])
  return string.format("#%02x%02x%02x", math.floor(r1 + (r2 - r1) * f + 0.5), math.floor(g1 + (g2 - g1) * f + 0.5), math.floor(b1 + (b2 - b1) * f + 0.5))
end

-- A fixed, spectrum-like shape: a few peaks over a low floor.
local function spectrumHeight(i, n)
  local x = (i - 1) / math.max(1, n - 1)
  local function bump(center, width, height)
    return height * math.exp(-((x - center) / width) ^ 2)
  end
  local wobble = 0.06 * math.abs(math.sin(i * 2.7))
  return math.min(1, 0.1 + wobble + bump(0.18, 0.07, 0.55) + bump(0.4, 0.05, 0.95) + bump(0.62, 0.08, 0.5) + bump(0.85, 0.06, 0.4))
end

local headerKey, headerNode = nil, nil

local function spectrumHeader()
  local bw = math.max(1, tonumber(cfg.bar_width) or 2)
  local bs = math.max(0, tonumber(cfg.bar_spacing) or 2)
  local stops = spectrumStops()
  local cavaWidth = tonumber(cfg.cavawidth) or DEFAULT_CAVA_WIDTH
  local key = bw .. "|" .. bs .. "|" .. cavaWidth .. "|" .. table.concat(stops, ",")
  if key == headerKey then
    return headerNode
  end
  -- The whole cava window is scaled down to the panel, so the bar count and proportions match the real ones.
  local scale = SPECTRUM_WIDTH / cavaWidth
  local ideal = math.max(1, math.floor((cavaWidth + bs * CELL_PX) / ((bw + bs) * CELL_PX)))
  local count = math.min(MAX_BARS, ideal)
  -- Too many bars to draw: make them wider so the header still fills the width.
  local unit = CELL_PX * scale * ideal / count
  local barPx = math.max(1, math.floor(bw * unit))
  -- A spacing of 1 or more always shows at least 1 px.
  local gapPx = bs > 0 and math.max(1, math.floor(bs * unit + 0.5)) or 0
  while barPx > 1 and count * barPx + (count - 1) * gapPx > SPECTRUM_WIDTH do
    barPx -= 1
  end
  local bands = #stops == 1 and 1 or SPECTRUM_BANDS
  local bandHeight = SPECTRUM_HEIGHT // bands
  local bandColors = {}
  for j = 1, bands do
    bandColors[j] = stopAt(stops, bands == 1 and 0 or (j - 1) / (bands - 1))
  end
  local bars = {}
  for i = 1, count do
    local px = math.floor(spectrumHeight(i, count) * SPECTRUM_HEIGHT + 0.5)
    -- Top band first: the column is laid out from the top and pushed to the bottom.
    local segs = {}
    for j = bands, 1, -1 do
      local h = math.max(0, math.min(bandHeight, px - (j - 1) * bandHeight))
      if h >= 1 then
        table.insert(segs, ui.box({ key = "s-" .. i .. "-" .. j, fill = bandColors[j], width = barPx, height = h }))
      end
    end
    table.insert(bars, ui.column({ key = "b-" .. i, gap = 0, justify = "end", height = SPECTRUM_HEIGHT }, segs))
  end
  headerKey = key
  headerNode = ui.row({ key = "spectrum", gap = gapPx, align = "end", justify = "center", height = SPECTRUM_HEIGHT }, bars)
  return headerNode
end

render = function()
  local rows = {}
  if not loaded then
    table.insert(rows, ui.label({ text = "Reading settings...", color = "on_surface_variant" }))
  elseif cfg.cavactl == nil or cfg.cavactl == "" then
    table.insert(rows, ui.label({ text = "cavactl is not installed (mabox-colorizer).", color = "primary" }))
  else
    -- Two columns: Window and Color on the left, Bars and General on the right; the spectrum and the config row span both.
    rows = {
      spectrumHeader(),
      ui.row({ key = "columns", gap = 10, align = "start" }, {
        ui.column({ key = "col-left", gap = 10, flexGrow = 1, minWidth = COLUMN_WIDTH }, { windowCard(), colorCard() }),
        ui.column({ key = "col-right", gap = 10, flexGrow = 1, minWidth = COLUMN_WIDTH }, { barsCard(), generalCard() }),
      }),
      configRow(),
    }
  end
  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 6, align = "center" }, {
      logo(),
      ui.label({ text = "Cava" }),
      ui.label({ text = hotkey("mabox/cava:main"), color = "outline_variant", flexGrow = 1 }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    ui.column({ gap = 10 }, rows),
  }))
end

function onOpen()
  armed = false
  loaded = false
  render()
  load()
end
