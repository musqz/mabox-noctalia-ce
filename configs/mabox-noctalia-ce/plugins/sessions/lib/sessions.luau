--!nonstrict
-- Sessions: named sets of apps on their own workspace, kept by mb-session. The state lives in one table (Luau local limit).

local logo = require("./celogo.luau")
local hotkey = require("./hotkey.luau")
local lapse = require("./lapse.luau")

return function()
local HOME = noctalia.getenv("HOME")
local render
local S = { ws = "", cur = nil, login = false, list = {}, apps = {}, shown = {}, ask = {}, name = "", nonce = 0, renaming = nil, renameText = "", base = false }

function S.run(args, after)
  noctalia.runAsync(args, function(r)
    if r.exitCode ~= 0 then
      local msg = string.match(r.stderr or "", "mb%-session: ([^\n]+)")
      noctalia.notify("Sessions", msg or "mb-session failed")
    end
    local skipped = {}
    for l in string.gmatch(r.stderr or "", "([^\n]+), skipped") do
      table.insert(skipped, l)
    end
    if #skipped > 0 then
      noctalia.notify("Sessions", "Not saved: " .. table.concat(skipped, "; "))
    end
    if after then
      after(r)
    end
    S.load()
  end)
end

function S.loginFile()
  return (noctalia.getenv("XDG_CONFIG_HOME") or (HOME .. "/.config")) .. "/mabox-noctalia-ce/autostart.skip"
end

function S.load()
  S.login = not string.find("\n" .. (noctalia.readFile(S.loginFile()) or "") .. "\n", "\nsession\n", 1, true)
  noctalia.runAsync({ "mb-session", "current" }, function(r)
    S.cur = tonumber(string.match(r.stdout or "", "%d+"))
    render()
  end)
  noctalia.runAsync({ "mb-session", "list" }, function(r)
    S.list = {}
    for n, ws, c in string.gmatch(r.stdout or "", "([^\t\n]+)\t(%d+-?%d*)\t(%d+)") do
      table.insert(S.list, { name = n, ws = ws, count = c })
    end
    for name in pairs(S.shown) do
      noctalia.runAsync({ "mb-session", "show", name }, function(sr)
        S.apps[name] = {}
        for id, cmd in string.gmatch(sr.stdout or "", "([^\t\n]+)\t([^\n]+)") do
          if id ~= "workspace" then
            table.insert(S.apps[name], { id = id, cmd = cmd })
          end
        end
        render()
      end)
    end
    render()
  end)
end

function S.save(newOnly)
  local name = noctalia.string.trim((string.gsub(S.name, "[^%w _%-]", "")))
  if name == "" then
    return
  end
  local args = { "mb-session", "save", name }
  if newOnly then
    table.insert(args, "--new-only")
  end
  local ws = string.match(S.ws, "^%s*(%d+-?%d*)%s*$")
  if ws then
    table.insert(args, "--workspace")
    table.insert(args, ws)
  end
  S.ws = ""
  S.name = ""
  S.nonce += 1
  S.base = false
  S.run(args)
end

-- Workspace "3" or "3-4": does the active workspace fall inside it.
function S.has(ws, cur)
  local a, b = string.match(ws, "^(%d+)-?(%d*)$")
  a = tonumber(a)
  b = tonumber(b) or a
  return a ~= nil and cur ~= nil and cur >= a and cur <= b
end

function S.button(key, glyph, tip, fn)
  return ui.button({ key = key, glyph = glyph, variant = "ghost", controlSize = "sm", tooltip = tip, onClick = fn })
end

-- Two clicks: the button turns into a question for 5 s.
function S.confirm(key, glyph, text, tip, fn)
  local armed = lapse.armed(S.ask, key)
  return ui.button({ key = key, glyph = glyph, text = armed and text or nil, variant = armed and "destructive" or "ghost", controlSize = "sm",
    tooltip = tip, onClick = function()
      if not lapse.armed(S.ask, key) then
        lapse.arm(S.ask, key, 5, render)
        render()
        return
      end
      lapse.disarm(S.ask, key)
      fn()
    end })
end

function S.row(it)
  local name = it.name
  if S.renaming == name then
    local function go()
      local new = noctalia.string.trim((string.gsub(S.renameText, "[^%w _%-]", "")))
      S.renaming = nil
      if new ~= "" and new ~= name then
        S.run({ "mb-session", "rename", name, new })
      end
      render()
    end
    return ui.row({ key = "sr" .. name, gap = 4, align = "center" }, {
      ui.input({ key = "srn" .. name, value = name, controlSize = "sm", frameVisible = true, flexGrow = 1,
        onChange = function(t) S.renameText = t end, onSubmit = go }),
      S.button("sry" .. name, "check", "Rename", go),
      S.button("srx" .. name, "x", "Cancel", function() S.renaming = nil; render() end),
    })
  end
  local open = S.shown[name]
  local here = S.has(it.ws, S.cur)
  local row = ui.row({ key = "sr" .. name, gap = 2, align = "center" }, {
    S.button("sf" .. name, open and "chevron-down" or "chevron-right", "Show the apps", function()
      S.shown[name] = (not open) or nil
      S.load()
    end),
    ui.button({ key = "ss" .. name .. (here and "-on" or ""), glyph = here and "point-filled" or "player-play", text = name, variant = here and "primary" or "ghost", contentAlign = "start", flexGrow = 1,
      tooltip = "Workspace " .. it.ws .. ": go there and start the apps that are not open", onClick = function()
        S.run({ "setsid", "-f", "mb-session", "start", name })
        panel.close()
      end }),
    ui.label({ text = it.count .. " · " .. it.ws, tooltip = it.count .. " windows, workspace " .. it.ws, color = "outline_variant", fontSize = 11 }),
    S.confirm("sv" .. name, "device-floppy", "Save?", "Save all open windows into this session (click twice)", function()
      S.run({ "mb-session", "save", name })
    end),
    S.confirm("sp" .. name, "replace", "Replace?", "Save the session you are in, close every window, then start this one (click twice)", function()
      S.run({ "setsid", "-f", "mb-session", "start", name, "--replace" })
      panel.close()
    end),
    S.confirm("sk" .. name, "player-stop", "Stop?", "Close the windows of this session's apps (click twice)", function()
      S.run({ "mb-session", "stop", name })
    end),
    S.button("se" .. name, "pencil", "Rename", function() S.renaming = name; S.renameText = name; render() end),
    S.confirm("sd" .. name, "trash", "Delete?", "Delete (click twice)", function()
      S.shown[name] = nil
      S.run({ "mb-session", "delete", name })
    end),
  })
  if not open then
    return row
  end
  local rows = { row }
  for i, a in ipairs(S.apps[name] or {}) do
    table.insert(rows, ui.row({ key = "sa" .. i .. name .. a.id, gap = 4, align = "center" }, {
      ui.label({ text = a.cmd, color = "on_surface_variant", fontSize = 11, flexGrow = 1, maxLines = 1, tooltip = a.id }),
      S.button("sax" .. i .. name .. a.id, "x", "Remove from the session", function()
        S.run({ "mb-session", "remove", name, a.id })
      end),
    }))
  end
  return ui.column({ key = "sc" .. name, gap = 2 }, rows)
end

function S.card()
  local rows = {}
  if S.cur then
    local at = nil
    for _, it in ipairs(S.list) do
      if S.has(it.ws, S.cur) then
        at = it.name
      end
    end
    table.insert(rows, ui.label({ text = at and ("Now: " .. at .. " (workspace " .. S.cur .. ")") or ("Workspace " .. S.cur .. ", no session"),
      color = at and "primary" or "outline_variant", fontSize = 12 }))
  end
  for _, it in ipairs(S.list) do
    table.insert(rows, S.row(it))
  end
  if #S.list == 0 then
    table.insert(rows, ui.label({ text = "Go to an empty workspace, press New, open the apps, then Save new", color = "on_surface_variant", fontSize = 11, maxLines = 3 }))
  end
  table.insert(rows, ui.row({ gap = 4, align = "center" }, {
    ui.input({ key = "sn" .. S.nonce, value = S.name, placeholder = "session name", controlSize = "sm", frameVisible = true, flexGrow = 1,
      onChange = function(t) S.name = t end, onSubmit = function() S.save(S.base) end }),
    ui.input({ key = "sw" .. S.nonce, value = S.ws, placeholder = "ws 3-4", controlSize = "sm", frameVisible = true, width = 80,
      onChange = function(t) S.ws = t end, onSubmit = function() S.save(S.base) end }),
    ui.button({ key = "snew", glyph = "player-record", variant = S.base and "primary" or "outline", controlSize = "sm",
      tooltip = "New: remember the open windows, then Save keeps only the apps you open after", onClick = function()
        S.base = not S.base
        if S.base then
          S.run({ "mb-session", "baseline" })
        end
        render()
      end }),
    ui.button({ key = "ssave", glyph = "device-floppy", text = S.base and "Save new" or "Save", variant = "outline", controlSize = "sm",
      tooltip = S.base and "Save the apps opened since New" or "Save every open window", onClick = function() S.save(S.base) end }),
  }))
  return ui.column({ key = "sessions", fill = "surface_variant", radius = 10, padding = 10, gap = 2, border = "primary", borderWidth = 1 }, rows)
end

render = function()
  panel.render(ui.column({ fill = "surface", radius = 12, gap = 8, padding = 10, flexGrow = 1 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Sessions" }),
      ui.label({ text = hotkey("mabox/sessions:main"), color = "outline_variant", flexGrow = 1 }),
      ui.button({ key = "slogin", glyph = "login", variant = S.login and "primary" or "ghost", controlSize = "sm",
        tooltip = S.login and "Opens at login (click to turn off)" or "Open this panel at login", onClick = function()
          S.login = not S.login
          noctalia.runAsync({ "mb-session", "login", S.login and "on" or "off" })
          render()
        end }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    ui.scroll({ gap = 8, flexGrow = 1, key = "list" }, { S.card() }),
  }))
end

return {
  open = function() S.load() end,
  key = function(chord)
    if chord == "escape" then
      panel.close()
    end
  end,
}
end
