--!nonstrict
local open, tick = require("./lib/places.luau")("left")
open()
function update()
  tick()
end
