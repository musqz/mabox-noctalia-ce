--!nonstrict
local open, tick = require("./lib/notes.luau")("left")
open()
function update()
  tick()
end
