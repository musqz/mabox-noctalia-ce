--!nonstrict
-- /ag: start an agent or resume an earlier session. Parsing and filtering live in
-- mb-agent-sessions (python), so the callback only builds a few rows.

local LABEL = { claude = "Claude Code", codex = "Codex", agy = "Agy" }

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  noctalia.runAsync({ "mb-agent-sessions", "--json", q }, function(result)
    local ok, data = false, nil
    if result.exitCode == 0 then
      ok, data = pcall(noctalia.json.decode, result.stdout)
    end
    local rows = {}
    if q == "" then
      table.insert(rows, { id = "panel", title = "All sessions …", subtitle = "Panel with details and a project picker", glyph = "list-search", score = 1100 })
    end
    if ok and type(data) == "table" then
      for i, a in data.agents or {} do
        if LABEL[a] and (q == "" or noctalia.fuzzyScore(q, LABEL[a]) ~= nil) then
          table.insert(rows, { id = "start:" .. a, title = "Start " .. LABEL[a], subtitle = "New session in your home folder", glyph = "player-play", score = 1000 - i })
        end
      end
      for _, pr in data.projects or {} do
        for i, a in data.agents or {} do
          if LABEL[a] then
            table.insert(rows, { id = "startin:" .. a .. ":" .. pr.dir, title = "Start " .. LABEL[a] .. " in " .. pr.text, subtitle = "New session in this folder", glyph = "folder", score = 950 - i })
          end
        end
      end
      for i, s in data.sessions or {} do
        table.insert(rows, { id = "open:" .. s.key, title = s.text, subtitle = "Enter to resume", glyph = "history", score = 900 - i })
      end
    end
    if #rows == 0 then
      rows[1] = { id = "", title = ok and "No sessions found" or "Could not run mb-agent-sessions", glyph = "mood-empty" }
    end
    launcher.setResults(text, rows)
  end)
end

-- The short sleep lets the launcher close first, as in the keys plugin.
function onActivate(id)
  if id == "panel" then
    noctalia.runAsync({ "sh", "-c", "sleep 0.2; exec noctalia msg panel-toggle mabox/agents:main" })
    return
  end
  local agent, dir = string.match(id or "", "^startin:(%a+):(/.+)$")
  if agent and LABEL[agent] then
    noctalia.runAsync({ "sh", "-c", 'sleep 0.2; exec "$@"', "sh", "mb-agent-sessions", "--start", agent, dir })
    return
  end
  local kind, arg = string.match(id or "", "^(%a+):([%w:%-]+)$")
  if kind == "start" then
    noctalia.runAsync({ "sh", "-c", 'sleep 0.2; exec "$@"', "sh", "mb-agent-sessions", "--start", arg })
  elseif kind == "open" then
    noctalia.runAsync({ "sh", "-c", 'sleep 0.2; exec "$@"', "sh", "mb-agent-sessions", "--open", arg })
  end
end
