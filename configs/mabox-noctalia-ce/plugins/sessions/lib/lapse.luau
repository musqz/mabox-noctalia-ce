--!nonstrict
-- "Click again" confirmations that fall back to normal by themselves: arm(state, key, secs, onLapse).
-- armed() also checks the clock, so a render after the time is up never shows the question.

local tokens = {}

local M = {}

function M.arm(state, key, secs, onLapse)
  local token = (tokens[key] or 0) + 1
  tokens[key] = token
  state[key] = os.time() + secs
  noctalia.runAsync({ "sh", "-c", "sleep " .. secs }, function()
    if tokens[key] == token and state[key] then
      state[key] = nil
      onLapse()
    end
  end)
end

function M.armed(state, key)
  return state[key] ~= nil and os.time() < state[key]
end

function M.disarm(state, key)
  tokens[key] = (tokens[key] or 0) + 1
  state[key] = nil
end

return M
