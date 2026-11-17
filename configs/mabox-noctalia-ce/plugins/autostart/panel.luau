--!nonstrict
-- Startup programs: autostart.local entries (add, delay, switch off, remove) and the shipped defaults (switch off).

local store = require("./lib/autostart.luau")
local logo = require("./lib/celogo.luau")
local lapse = require("./lib/lapse.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local entries, lines = {}, {}
local skipped = {}
local polkit = nil
local err = nil
local note = nil
local armed = nil
local confirm = {}
local newCmd, newDelay = "", "3"
local drafts = {}
local cmdDrafts = {}
local formGen = 0

local render

local rev = 0

-- keep: unsaved edits survive (line numbers did not change).
local function reload(keep)
  entries, lines = store.load()
  skipped = store.skipped()
  if not keep then
    drafts = {}
    cmdDrafts = {}
  end
  rev += 1
  armed = nil
end

local function persist(msg, keep)
  local ok, why = store.save(entries, lines)
  if ok then
    err = nil
    note = msg
  else
    err = why == "changed" and "autostart.local changed on disk, nothing written. Read again and retry" or "Could not write autostart.local"
    note = nil
  end
  reload(keep)
  render()
end

local function toggle(e)
  e.on = not e.on
  persist("Saved. Applies at next login", true)
end

local function remove(e)
  if not lapse.armed(confirm, "rm") or armed ~= e.line then
    armed = e.line
    lapse.arm(confirm, "rm", 5, render)
    render()
    return
  end
  lapse.disarm(confirm, "rm")
  armed = nil
  for i, x in ipairs(entries) do
    if x == e then
      table.remove(entries, i)
      break
    end
  end
  persist("Removed")
end

local function cancel()
  lapse.disarm(confirm, "rm")
  armed = nil
  render()
end

-- Checks a command and delay; calls done(cmd, seconds) when both are fine.
local function validate(cmdText, delayText, done)
  local cmd = noctalia.string.trim(cmdText)
  local n = tonumber(string.match(noctalia.string.trim(delayText), "^%d+$"))
  local bad = nil
  if cmd == "" then
    bad = "Enter a command"
  elseif string.find(cmd, "[\n\r]") then
    bad = "One line only"
  elseif string.find(cmd, "&$") or string.find(cmd, "^#") then
    bad = "No trailing & or leading #"
  elseif not n or n > 3600 then
    bad = "Delay is whole seconds, 0 to 3600"
  end
  if bad then
    err = bad
    render()
    return
  end
  noctalia.runAsync({ "bash", "-n", "-c", "(sleep 1 && " .. cmd .. ") &" }, function(r)
    if r.exitCode ~= 0 then
      err = "Not a valid shell command"
      render()
      return
    end
    done(cmd, n)
  end)
end

local function add()
  validate(newCmd, newDelay, function(cmd, n)
    table.insert(entries, { on = true, delay = n, cmd = cmd })
    newCmd = ""
    formGen += 1
    persist("Added. Starts at next login")
  end)
end

local function dirty(e)
  local d, c = drafts[e.line], cmdDrafts[e.line]
  return (d ~= nil and noctalia.string.trim(d) ~= tostring(e.delay)) or (c ~= nil and noctalia.string.trim(c) ~= e.cmd)
end

-- The command is only checked when it was edited, so a hand-written entry keeps its delay editable.
local function saveRow(e)
  local line = e.line
  local newText = cmdDrafts[line] and noctalia.string.trim(cmdDrafts[line]) or e.cmd
  local function apply(cmd, n)
    for _, x in ipairs(entries) do
      if x.line == line then
        x.cmd, x.delay = cmd, n
        drafts[line], cmdDrafts[line] = nil, nil
        persist("Saved. Applies at next login", true)
        return
      end
    end
  end
  if newText == e.cmd then
    local n = tonumber(string.match(noctalia.string.trim(drafts[line] or tostring(e.delay)), "^%d+$"))
    if not n or n > 3600 then
      err = "Delay is whole seconds, 0 to 3600"
      render()
      return
    end
    apply(e.cmd, n)
  else
    validate(newText, drafts[line] or tostring(e.delay), apply)
  end
end

local function toggleDefault(name)
  skipped[name] = not skipped[name] or nil
  if store.saveSkipped(skipped) then
    err = nil
    note = "Saved. Applies at next login"
  else
    err = "Could not write autostart.skip"
    note = nil
  end
  render()
end

local function openFile()
  noctalia.runAsync({ "sh", "-c", 'f=$1; [ -e "$f" ] || touch "$f"; if command -v geany >/dev/null; then exec setsid -f geany "$f"; else exec setsid -f xdg-open "$f"; fi', "sh", store.localFile() })
  panel.close()
end

local function refresh()
  reload()
  err = nil
  note = "Read again"
  render()
end

function render()
  local rows = {}
  for i, e in ipairs(entries) do
    local isArmed = armed == e.line and lapse.armed(confirm, "rm")
    table.insert(rows, ui.row({ key = "e" .. e.line, gap = 8, align = "center", padding = 4 }, {
      ui.toggle({ key = "t" .. e.line .. (e.on and "1" or "0"), checked = e.on, onChange = function() toggle(e) end }),
      ui.input({ key = "dl" .. e.line .. "_" .. rev, value = drafts[e.line] or tostring(e.delay), width = 56, controlSize = "sm", frameVisible = true, tooltip = "Delay in seconds",
        onChange = function(t)
          local was = dirty(e)
          drafts[e.line] = t
          err = nil
          if dirty(e) ~= was then render() end
        end, onSubmit = function() saveRow(e) end }),
      ui.label({ text = "s", color = "on_surface_variant" }),
      ui.input({ key = "cm" .. e.line .. "_" .. rev, value = cmdDrafts[e.line] or e.cmd, flexGrow = 1, controlSize = "sm", frameVisible = true,
        onChange = function(t)
          local was = dirty(e)
          cmdDrafts[e.line] = t
          err = nil
          if dirty(e) ~= was then render() end
        end, onSubmit = function() saveRow(e) end }),
      dirty(e) and ui.button({ key = "sv" .. e.line, glyph = "device-floppy", text = "Save", variant = "primary", controlSize = "sm", onClick = function() saveRow(e) end }) or ui.box({ width = 0 }),
      isArmed and ui.button({ key = "c" .. e.line, text = "Cancel", variant = "ghost", controlSize = "sm", onClick = cancel }) or ui.box({ width = 0 }),
      ui.button({ key = "d" .. e.line .. (isArmed and "a" or ""), glyph = "trash", text = isArmed and "Click again" or nil, variant = isArmed and "destructive" or "ghost", controlSize = "sm", tooltip = "Remove", onClick = function() remove(e) end }),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No entries yet", color = "on_surface_variant" }))
  end

  local defaults = {}
  for _, d in ipairs(store.DEFAULTS) do
    local off = skipped[d.name] == true
    table.insert(defaults, ui.row({ key = "df" .. d.name, gap = 8, align = "center", padding = 4 }, {
      ui.toggle({ key = "dt" .. d.name .. (off and "0" or "1"), checked = not off, onChange = function() toggleDefault(d.name) end }),
      ui.label({ text = d.name, width = 150, color = off and "on_surface_variant" or "on_surface" }),
      ui.label({ text = d.desc, flexGrow = 1, color = "on_surface_variant", maxLines = 1 }),
    }))
  end

  local fixed = {}
  for _, d in ipairs(store.FIXED) do
    local desc = d.desc
    if d.name == "polkit agent" and polkit ~= nil then
      desc = desc .. (polkit and " (on)" or " (off in the Noctalia settings)")
    end
    table.insert(fixed, ui.row({ key = "fx" .. d.name, gap = 8, align = "center", padding = 4 }, {
      ui.box({ width = 40 }),
      ui.label({ text = d.name, width = 150 }),
      ui.label({ text = desc, flexGrow = 1, color = "on_surface_variant", maxLines = 1 }),
    }))
  end

  panel.render(ui.column({ gap = 10, padding = 12, height = 620 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Autostart", flexGrow = 1 }),
      ui.button({ key = "refresh", glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Read the file again", onClick = refresh }),
      ui.button({ key = "geany", glyph = "file-text", text = "Open autostart.local", variant = "ghost", controlSize = "sm", onClick = openFile }),
    }),
    err and ui.label({ text = err, color = "error" }) or ui.label({ text = note or "Changes apply at next login", color = note and "primary" or "on_surface_variant", fontSize = 12 }),
    ui.scroll({ key = "body", gap = 10, flexGrow = 1 }, {
    ui.column(card("mine"), {
      ui.label({ text = "Your startup programs", color = "on_surface_variant", fontSize = 12 }),
      ui.column({ gap = 0 }, rows),
      ui.row({ gap = 8, align = "center" }, {
        ui.input({ key = "newcmd" .. formGen, value = newCmd, placeholder = "Command", flexGrow = 1, controlSize = "sm", frameVisible = true, onChange = function(t) newCmd = t end, onSubmit = add }),
        ui.input({ key = "newdelay", value = newDelay, width = 56, controlSize = "sm", frameVisible = true, tooltip = "Delay in seconds", onChange = function(t) newDelay = t end, onSubmit = add }),
        ui.label({ text = "s", color = "on_surface_variant" }),
        ui.button({ key = "add", glyph = "plus", text = "Add", variant = "ghost", controlSize = "sm", onClick = add }),
      }),
    }),
    ui.column(card("defaults"), {
      ui.label({ text = "Shipped defaults", color = "on_surface_variant", fontSize = 12 }),
      ui.column({ gap = 0 }, defaults),
    }),
    ui.column(card("fixed"), {
      ui.label({ text = "Always started", color = "on_surface_variant", fontSize = 12 }),
      ui.column({ gap = 0 }, fixed),
    }),
    ui.box({ height = 4 }),
    }),
  }))
end

function onOpen()
  reload()
  noctalia.runAsync({ "noctalia", "msg", "config-get", "shell.polkit_agent" }, function(r)
    if r.exitCode == 0 then
      polkit = string.find(r.stdout or "", "true") ~= nil
      render()
    end
  end)
  err = nil
  note = nil
  armed = nil
  render()
end
