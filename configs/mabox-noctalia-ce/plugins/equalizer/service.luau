--!nonstrict
-- Re-applies the saved equalizer state when Noctalia starts.
local eq = require("./lib/eq.luau")
local state = eq.load()
local args = table.concat(eq.gainArgs(state.gains), " ")
local script = 'for i in 1 2 3 4 5 6; do mb-eq gains ' .. args .. ' && break; sleep 2; done' .. (state.on and "; mb-eq on" or "")
noctalia.runAsync({ "sh", "-c", script })
