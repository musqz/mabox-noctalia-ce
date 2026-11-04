--!nonstrict
local open, tick = require("./lib/notes.luau")("right")
open()
function update()
  tick()
end
