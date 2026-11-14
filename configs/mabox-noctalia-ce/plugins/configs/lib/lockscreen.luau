--!nonstrict
-- Lock screen look (Noctalia lockscreen.* settings): background and transition.
local toml = require("./tomlsection.luau")
local M = {}

local EFFECTS = { "crt", "diamond", "disc", "fade", "golden", "honeycomb", "melt", "pixel", "stripes", "vortex", "wipe", "zoom" }
local TINTS = { "surface", "primary", "secondary", "tertiary", "error" }

local st = { blurred = false, wallpaper = "", blur = 0.5, tint = 0.3, color = "surface", effects = {}, duration = 1500, smooth = 0.3, note = nil }
local draft = nil

-- Re-read from the state file on every render; keys left out of the file hold their default.
local dragging = false

function M.load()
  if dragging then
    return
  end
  local t = toml.section("lockscreen")
  st.blurred = t.blurred_desktop == "true"
  st.wallpaper = toml.str(t.wallpaper, "")
  st.blur = tonumber(t.blur_intensity) or 0.5
  st.tint = tonumber(t.tint_intensity) or 0.3
  st.color = toml.str(t.tint_color, "surface")
  st.duration = tonumber(t.transition_duration) or 1500
  st.smooth = tonumber(t.edge_smoothness) or 0.3
  st.effects = {}
  for _, e in ipairs(t.transition and toml.words(t.transition) or EFFECTS) do
    st.effects[e] = true
  end
end

local function set(key, value, render, apply)
  st.note = nil
  noctalia.runAsync({ "noctalia", "msg", "config-set", "lockscreen." .. key, value }, function(r)
    if r.exitCode == 0 then
      apply()
      st.note = nil
    else
      st.note = "Could not change the lock screen"
    end
    render()
  end)
end

-- setsid: runAsync ends a long command, which closed the file dialog (same as the Logo picker).
local PICK = [[p=$(yad --file --center --width=1000 --height=650 --title="Lock screen wallpaper" --file-filter="Images | *.jpg *.jpeg *.png *.webp" --filename="$HOME/Pictures/")
p=$(printf %s "$p" | tr -d "'|")
if [ -n "$p" ]; then noctalia msg config-set lockscreen.wallpaper "'$p'" >/dev/null || notify-send -a Configs "Lock screen" "Could not use that file"; fi]]

local function waitPicker(render)
  noctalia.runAsync({ "sh", "-c", "sleep 2; pgrep -f 'Lock screen wallpape[r]' >/dev/null && echo busy" }, function(r)
    if string.find(r.stdout or "", "busy", 1, true) then
      waitPicker(render)
    else
      render()
    end
  end)
end

local function pickWallpaper(render, pinned)
  if pinned then
    noctalia.runAsync({ "setsid", "-f", "sh", "-c", PICK })
    waitPicker(render)
  else
    noctalia.runAsync({ "setsid", "-f", "sh", "-c", PICK .. "\nnoctalia msg panel-close; noctalia msg panel-open mabox/configs:main" })
  end
end

local function bool(v)
  return v == true or v == "true"
end

local function slider(label, key, cfg, min, max, step, fmt, render)
  return ui.row({ gap = 8, align = "center" }, {
    ui.label({ text = label, color = "on_surface_variant", width = 80 }),
    ui.slider({ key = "ls-" .. key, min = min, max = max, step = step, value = st[key], controlSize = "sm", flexGrow = 1,
      onChange = function(v) dragging = true; st[key] = tonumber(v) or st[key]; render() end,
      onDragEnd = function() dragging = false; set(cfg, string.format(fmt, st[key]), render, function() end) end }),
    ui.label({ text = string.format(fmt, st[key]), width = 52 }),
  })
end

function M.rows(render, pinned)
  M.load()
  local fx, fxRows = {}, {}
  for _, e in ipairs(EFFECTS) do
    local on = st.effects[e] == true
    table.insert(fx, ui.button({ key = "lfx" .. e .. (on and "1" or "0"), text = e, variant = on and "primary" or "outline", controlSize = "sm", onClick = function()
      local list, n = {}, 0
      for _, x in ipairs(EFFECTS) do
        local keep = st.effects[x]
        if x == e then
          keep = not keep
        end
        if keep then
          table.insert(list, "'" .. x .. "'")
          n += 1
        end
      end
      if n == 0 then
        st.note = "Keep at least one effect"
        render()
        return
      end
      set("transition", "[ " .. table.concat(list, ", ") .. " ]", render, function() st.effects[e] = not st.effects[e] or nil end)
    end }))
  end
    for i = 1, #fx, 3 do
    table.insert(fxRows, ui.row({ key = "lfxr" .. i, gap = 6 }, { fx[i], fx[i + 1], fx[i + 2] }))
  end
  local tints = {}
  for _, c in ipairs(TINTS) do
    local on = st.color == c
    table.insert(tints, ui.button({ key = "lt" .. c .. (on and "1" or "0"), text = c, variant = on and "primary" or "outline", controlSize = "sm", onClick = function()
      set("tint_color", "'" .. c .. "'", render, function() st.color = c end)
    end }))
  end
  local function setWallpaper()
    local v = noctalia.string.trim(draft or st.wallpaper)
    v = string.gsub(v, "^~/", noctalia.getenv("HOME") .. "/")
    set("wallpaper", "'" .. string.gsub(v, "'", "") .. "'", render, function() st.wallpaper = v; draft = nil end)
  end
  return {
    ui.label({ text = "Background", fontWeight = "bold" }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Desktop capture", flexGrow = 1, tooltip = "Use a snapshot of the desktop as the lock screen background" }),
      ui.toggle({ key = "ls-cap", checked = st.blurred, onChange = function(v)
        local want = bool(v)
        set("blurred_desktop", want and "true" or "false", render, function() st.blurred = want end)
      end }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Wallpaper", color = "on_surface_variant", width = 80 }),
      ui.input({ key = "ls-wp" .. st.wallpaper, value = draft or st.wallpaper, placeholder = "Use desktop wallpaper", controlSize = "sm", frameVisible = true, flexGrow = 1, onChange = function(t) draft = t end, onSubmit = setWallpaper }),
      ui.button({ key = "ls-wppick", glyph = "folder-open", variant = "ghost", controlSize = "sm", tooltip = "Choose an image", onClick = function() pickWallpaper(render, pinned) end }),
      ui.button({ key = "ls-wpsave", glyph = "device-floppy", variant = "ghost", controlSize = "sm", tooltip = "Save (empty: desktop wallpaper)", onClick = setWallpaper }),
    }),
    slider("Blur", "blur", "blur_intensity", 0, 1, 0.05, "%.2f", render),
    slider("Tint", "tint", "tint_intensity", 0, 1, 0.05, "%.2f", render),
    ui.row({ gap = 6 }, { table.unpack(tints, 1, 3) }),
    ui.row({ gap = 6 }, { table.unpack(tints, 4) }),
    ui.label({ text = "Transition", fontWeight = "bold" }),
    ui.label({ text = "Effects when locking and unlocking (one is picked at random)", color = "on_surface_variant", fontSize = 12 }),
    ui.column({ gap = 6 }, fxRows),
    slider("Duration", "duration", "transition_duration", 200, 5000, 100, "%.0f", render),
    slider("Smoothness", "smooth", "edge_smoothness", 0, 1, 0.05, "%.2f", render),
    ui.label({ text = st.note or "", color = "error", fontSize = 12 }),
  }
end

return M
