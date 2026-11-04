--!nonstrict
local open, tick = require("./lib/capture.luau")("right")
open()
function update()
  tick()
end
