--!nonstrict
-- Keyboard cursor over the stops a panel registers while rendering. Keep this file identical in every plugin's lib/.
-- The panel lists the chords it feeds to key() in capture_keys (plugin.toml).
local M = {}

local stops = {}
local cursor = nil
local goal = nil -- row kept across sideways moves so left/right come back to the same place

function M.begin()
  stops = {}
end

-- row/col are positions in any consistent unit; the cursor is kept by id so it survives re-renders.
function M.stop(id, row, col, action)
  table.insert(stops, { id = id, row = row, col = col, action = action })
end

local function find()
  for _, s in ipairs(stops) do
    if s.id == cursor then
      return s
    end
  end
end

function M.sel(id)
  return cursor == id
end

-- nil when there is no cursor or it points at a stop that is no longer rendered.
function M.reveal()
  return find() and cursor or nil
end

function M.clear()
  cursor = nil
  goal = nil
end

-- Returns true when the cursor moved.
function M.move(dir)
  if #stops == 0 then
    return false
  end
  local cur = find()
  goal = goal or (cur and cur.row)
  if not cur then
    local first = dir == "up" and stops[#stops] or stops[1]
    cursor, goal = first.id, first.row
    return true
  end
  local best, bestScore
  for _, s in ipairs(stops) do
    local score
    if dir == "down" and s.col == cur.col and s.row > cur.row then
      score = s.row - cur.row
    elseif dir == "up" and s.col == cur.col and s.row < cur.row then
      score = cur.row - s.row
    elseif dir == "right" and s.col > cur.col then
      score = (s.col - cur.col) * 1000 + math.abs(s.row - goal)
    elseif dir == "left" and s.col < cur.col then
      score = (cur.col - s.col) * 1000 + math.abs(s.row - goal)
    end
    if score and (not bestScore or score < bestScore) then
      best, bestScore = s, score
    end
  end
  if not best then
    return false
  end
  cursor = best.id
  if dir == "up" or dir == "down" then
    goal = best.row
  end
  return true
end

-- Handles the arrow and enter chords; returns "moved", "ran" or nil for anything else.
function M.key(chord)
  local jump = string.match(chord, "^alt%+shift%+(%a+)$")
  if jump == "up" or jump == "down" then
    local moved = false
    for _ = 1, 5 do
      moved = M.move(jump) or moved
    end
    return moved and "moved" or nil
  end
  local dir = string.match(chord, "^alt%+(%a+)$") or chord
  if dir == "up" or dir == "down" or dir == "left" or dir == "right" then
    return M.move(dir) and "moved" or nil
  elseif chord == "alt+enter" then
    local cur = find()
    if cur and cur.action then
      cur.action()
      return "ran"
    end
  end
  return nil
end

return M
