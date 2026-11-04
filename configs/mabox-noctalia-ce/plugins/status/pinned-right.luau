--!nonstrict
local open, tick = require("./lib/status.luau")("right")
open()
function update()
  tick()
end
