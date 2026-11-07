--!nonstrict
-- Cava: front end for cavactl (colors, bars, framerate) and the transparent cava window (mb-cava).

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local cfg = {}
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

local function load()
  noctalia.runAsync({ "sh", "-c", 'cat "$HOME/.config/cava/config" 2>/dev/null; echo; echo "cavactl=$(command -v cavactl)"; echo "running=$(wlrctl toplevel find app_id:cava-transparent >/dev/null 2>&1 && echo 1)"' }, function(result)
    cfg = parse(result.stdout or "")
    running = cfg.running == "1"
    loaded = true
    render()
  end)
end

local function ctl(...)
  armed = false
  local argv = { "cavactl", ... }
  noctalia.runAsync(argv, function()
    load()
  end)
end

local function color(key)
  local c = cfg[key]
  if c and string.match(c, "^#%x%x%x%x%x%x$") then
    return c
  end
  return nil
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
  })
end

-- Rows of five: the panel is 420 px wide and a row does not wrap.
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

local function windowCard()
  local label = busy and "Please wait..." or (running and "Stop cava" or "Start cava")
  return ui.column(card("window"), {
    ui.label({ text = "Window", fontWeight = "bold", fontSize = 14 }),
    ui.label({ text = "Frameless transparent cava, bottom centre.", fontSize = 11, color = "on_surface_variant" }),
    ui.button({ key = "toggle", text = label, variant = "outline", controlSize = "sm", onClick = function()
      if busy then
        return
      end
      busy = true
      armed = false
      if running then
        noctalia.runAsync({ "wlrctl", "toplevel", "close", "app_id:cava-transparent" })
      else
        noctalia.runAsync({ "setsid", "-f", "mb-cava" })
      end
      -- The window opens and closes a moment after the command returns.
      noctalia.runAsync({ "sleep", "1.5" }, function()
        busy = false
        load()
      end)
      render()
    end }),
  })
end

local function colorCard()
  local gradient = cfg.gradient == "1"
  local function mode(name, on, value)
    return ui.button({ key = "mode-" .. value, text = (on and "✓ " or "") .. name, variant = on and "primary" or "outline", controlSize = "sm", onClick = function()
      ctl("mode", value)
    end })
  end
  local rows = {
    ui.label({ text = "Color", fontWeight = "bold", fontSize = 14 }),
    ui.row({ gap = 6, align = "center" }, { mode("Solid", not gradient, "solid"), mode("Gradient", gradient, "gradient") }),
  }
  if gradient then
    table.insert(rows, swatch("From", "gradient_color_1", "grad_from"))
    table.insert(rows, swatch("To", "gradient_color_3", "grad_to"))
    if color("gradient_color_1") and color("gradient_color_3") then
      table.insert(rows, ui.button({ key = "reverse", text = "Reverse gradient", variant = "outline", controlSize = "sm", onClick = function()
        ctl("gradient", color("gradient_color_3"), color("gradient_color_1"))
      end }))
    end
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

local function generalCard()
  return ui.column(card("general"), {
    ui.label({ text = "General", fontWeight = "bold", fontSize = 14 }),
    choices("Framerate", "framerate", { "60", "120", "144" }, "framerate"),
    choices("Noise reduction", "noise_reduction", { "90", "77", "50", "25" }, "noise_reduction"),
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

render = function()
  local rows = {}
  if not loaded then
    table.insert(rows, ui.label({ text = "Reading settings...", color = "on_surface_variant" }))
  elseif cfg.cavactl == nil or cfg.cavactl == "" then
    table.insert(rows, ui.label({ text = "cavactl is not installed (mabox-colorizer).", color = "primary" }))
  else
    rows = { windowCard(), colorCard(), barsCard(), generalCard(), configRow() }
  end
  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Cava", flexGrow = 1 }),
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
