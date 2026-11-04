--!nonstrict
local open, tick = require("./lib/capture.luau")("left")
open()
function update()
  tick()
end
