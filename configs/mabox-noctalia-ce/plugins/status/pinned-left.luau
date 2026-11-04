--!nonstrict
local open, tick = require("./lib/status.luau")("left")
open()
function update()
  tick()
end
