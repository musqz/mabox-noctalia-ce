--!nonstrict
-- AI agents: sessions of Claude Code, Codex and Agy with a detail card, and a project picker
-- for new sessions. Data and launching come from mb-agent-sessions.
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local LABEL = { claude = "Claude", codex = "Codex", agy = "Agy" }

local data = nil
local failed = false
local query = ""
local agent = "" -- "" = all agents
local tab = "sessions" -- sessions | new
local selected = nil
local newAgent = nil
local searchNonce = 0
local loadSeq = 0

local function load()
  loadSeq += 1
  local seq = loadSeq
  noctalia.runAsync({ "mb-agent-sessions", "--panel" }, function(result)
    if seq ~= loadSeq then
      return
    end
    local ok, d = false, nil
    if result.exitCode == 0 then
      ok, d = pcall(noctalia.json.decode, result.stdout)
    end
    failed = not ok
    data = ok and d or nil
    render()
  end)
end

local function lower(s)
  return string.lower(s or "")
end

local function visibleSessions()
  local q = lower(noctalia.string.trim(query))
  local out = {}
  for _, s in ipairs(data and data.sessions or {}) do
    if (agent == "" or s.agent == agent) and (q == "" or string.find(lower(s.title .. " " .. s.dir .. " " .. (s.first or "") .. " " .. (s.last or "")), q, 1, true)) then
      table.insert(out, s)
    end
  end
  return out
end

local function visibleProjects()
  local q = lower(noctalia.string.trim(query))
  local out = {}
  for _, p in ipairs(data and data.projects or {}) do
    if q == "" or string.find(lower(p.text), q, 1, true) then
      table.insert(out, p)
    end
  end
  return out
end

local function launch(argv)
  panel.close()
  noctalia.runAsync(argv)
end

local function resume(s)
  launch({ "mb-agent-sessions", "--open", s.key })
end

local function startIn(dir)
  local a = newAgent or (data and data.agents and data.agents[1])
  if a then
    launch({ "mb-agent-sessions", "--start", a, dir })
  end
end

local function copyResume(s)
  local id = string.match(s.key, ":(.+)$")
  local dir = string.gsub(s.dir, "^~", noctalia.getenv("HOME") or "~")
  local cmd = "cd '" .. string.gsub(dir, "'", "'\\''") .. "' && " .. (s.agent == "claude" and "claude --resume " or s.agent == "codex" and "codex resume " or "agy --conversation ") .. id
  noctalia.runAsync({ "wl-copy", "--", cmd }, function(result)
    if result.exitCode == 0 then
      noctalia.notify("Command copied", cmd)
    end
  end)
end

local function chip(text, active, action)
  return ui.button({ text = text, variant = active and "primary" or "ghost", controlSize = "sm", onClick = action })
end

local function sessionRow(s)
  local on = selected == s.key
  return ui.row({ key = "r" .. s.key, gap = 8, align = "center", padding = 4, radius = 8, border = "primary", borderWidth = on and 3 or 0 }, {
    ui.label({ text = os.date("%x %H:%M", s.ts), fontSize = 11, color = "on_surface_variant", width = 120 }),
    ui.label({ text = LABEL[s.agent] or s.agent, fontSize = 11, color = "primary", width = 56 }),
    ui.label({ text = s.title, fontSize = 12, maxLines = 1, flexGrow = 1 }),
    ui.label({ text = s.dir, fontSize = 11, color = "on_surface_variant", maxLines = 1, width = 230 }),
    ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = "Resume", onClick = function() resume(s) end }),
  })
end

local function field(label, text)
  if not text or text == "" then
    return ui.box({ height = 0 })
  end
  return ui.column({ gap = 2 }, {
    ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
    ui.label({ text = text, fontSize = 12, maxLines = 6 }),
  })
end

local function detail(s)
  if not s then
    return ui.column({ width = 380, fill = "surface_variant", radius = 8, padding = 10 }, {
      ui.label({ text = "Select a session", color = "on_surface_variant" }),
    })
  end
  local meta = LABEL[s.agent] or s.agent
  if (s.n or 0) > 0 then
    meta = meta .. "  ·  " .. s.n .. (s.n == 1 and " prompt" or " prompts")
  end
  return ui.column({ width = 380, fill = "surface_variant", radius = 8, padding = 10, gap = 8 }, {
    ui.label({ text = s.title, maxLines = 2 }),
    ui.label({ text = meta .. "  ·  " .. os.date("%x %H:%M", s.ts), fontSize = 11, color = "on_surface_variant" }),
    field("Folder", s.dir),
    field("First prompt", s.first),
    s.last ~= s.first and field("Last prompt", s.last) or ui.box({ height = 0 }),
    ui.row({ gap = 6 }, {
      ui.button({ text = "Resume", variant = "primary", controlSize = "sm", onClick = function() resume(s) end }),
      ui.button({ text = "Copy command", variant = "ghost", controlSize = "sm", onClick = function() copyResume(s) end }),
    }),
  })
end

local function sessionsView()
  local list = visibleSessions()
  if not data then
    return ui.label({ text = failed and "Could not run mb-agent-sessions" or "Loading", color = "on_surface_variant" })
  end
  if #list == 0 then
    return ui.label({ text = "No sessions found", color = "on_surface_variant" })
  end
  local current
  local rows = {}
  for _, s in ipairs(list) do
    if s.key == selected then
      current = s
    end
    table.insert(rows, ui.row({ key = "c" .. s.key, onClick = function() selected = s.key render() end }, { sessionRow(s) }))
  end
  current = current or list[1]
  selected = current.key
  return ui.row({ gap = 10, align = "start", height = 470 }, {
    ui.scroll({ flexGrow = 1, key = "list" }, { ui.column({ gap = 2 }, rows) }),
    detail(current),
  })
end

local SECTIONS = {
  { id = "fav", title = "Favorite repos" },
  { id = "github", title = "GitHub" },
  { id = "aur", title = "AUR" },
  { id = "recent", title = "Folders of earlier sessions" },
}

local function favorite(action, dir)
  noctalia.runAsync({ "mb-agent-sessions", "--fav", action, dir }, function()
    load()
  end)
end

-- Detached (setsid) so the chooser survives the panel closing; the panel reopens afterwards and reloads.
local PICK = "mb-agent-sessions --fav pick; noctalia msg panel-close; noctalia msg panel-open mabox/agents:main"

local function pickFolder()
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", PICK })
end

local function projectRow(p, isFav)
  local name = (LABEL[newAgent] or newAgent)
  return ui.row({ key = "p" .. p.dir, gap = 8, align = "center", padding = 4, radius = 8, onClick = function() startIn(p.dir) end }, {
    ui.label({ text = p.text, maxLines = 1, flexGrow = 1, fontSize = 12 }),
    isFav
      and ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Remove from favorites", onClick = function() favorite("remove", p.dir) end })
      or ui.button({ glyph = "star", variant = "ghost", controlSize = "sm", tooltip = "Add to favorites", onClick = function() favorite("add", p.dir) end }),
    ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = "Start " .. name .. " here", onClick = function() startIn(p.dir) end }),
  })
end

local function newView()
  if not data then
    return ui.label({ text = failed and "Could not run mb-agent-sessions" or "Loading", color = "on_surface_variant" })
  end
  local agents = data.agents or {}
  if #agents == 0 then
    return ui.label({ text = "No agent installed (claude, codex or agy)", color = "on_surface_variant" })
  end
  newAgent = newAgent or agents[1]
  local chips = {}
  for _, a in ipairs(agents) do
    table.insert(chips, chip(LABEL[a] or a, newAgent == a, function() newAgent = a render() end))
  end
  local bySection = {}
  for _, p in ipairs(visibleProjects()) do
    bySection[p.section] = bySection[p.section] or {}
    table.insert(bySection[p.section], p)
  end
  local frames = {}
  for _, sec in ipairs(SECTIONS) do
    local items = bySection[sec.id] or {}
    local rows = {}
    if sec.id == "fav" then
      table.insert(rows, ui.row({ key = "p-home", gap = 8, align = "center", padding = 4, radius = 8, onClick = function() startIn(noctalia.getenv("HOME") or "/") end }, {
        ui.label({ text = "~", flexGrow = 1 }),
        ui.label({ text = "home folder", fontSize = 11, color = "on_surface_variant" }),
      }))
    end
    for _, p in ipairs(items) do
      table.insert(rows, projectRow(p, sec.id == "fav"))
    end
    if sec.id == "fav" or #items > 0 then
      table.insert(frames, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, {
        ui.row({ gap = 8, align = "center" }, {
          ui.label({ text = sec.title, fontSize = 13, flexGrow = 1 }),
          sec.id == "fav" and ui.button({ text = "Add folder", glyph = "folder-plus", variant = "ghost", controlSize = "sm", onClick = pickFolder }) or ui.box({ width = 0 }),
        }),
        ui.column({ gap = 2 }, rows),
      }))
    end
  end
  return ui.column({ gap = 8, height = 470 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Start", fontSize = 12, color = "on_surface_variant" }),
      ui.row({ gap = 4 }, chips),
      ui.label({ text = "in a folder:", fontSize = 12, color = "on_surface_variant" }),
    }),
    ui.scroll({ flexGrow = 1, key = "projects" }, { ui.column({ gap = 8 }, frames) }),
  })
end

function render()
  local agents = data and data.agents or {}
  local chips = { chip("All", agent == "", function() agent = "" render() end) }
  for _, a in ipairs(agents) do
    table.insert(chips, chip(LABEL[a] or a, agent == a, function() agent = a render() end))
  end
  panel.render(ui.column({ gap = 8, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "AI agents" }),
      ui.label({ text = hotkey("mabox/agents:main"), color = "outline_variant", flexGrow = 1 }),
      chip("Sessions", tab == "sessions", function() tab = "sessions" render() end),
      chip("New session", tab == "new", function() tab = "new" render() end),
      ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Reload", onClick = load }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.input({ key = "search" .. searchNonce, value = query, focus = true, controlSize = "sm", flexGrow = 1,
        placeholder = tab == "sessions" and "search title, folder or prompt" or "search project folder",
        onChange = function(t) query = t render() end }),
      tab == "sessions" and ui.row({ gap = 4 }, chips) or ui.box({ width = 0 }),
    }),
    tab == "sessions" and sessionsView() or newView(),
  }))
end

function onOpen()
  query = ""
  selected = nil
  searchNonce += 1
  render()
  load()
end

function onKey(chord, pressed)
  if pressed and chord == "alt+s" then
    searchNonce += 1
    render()
  end
end
