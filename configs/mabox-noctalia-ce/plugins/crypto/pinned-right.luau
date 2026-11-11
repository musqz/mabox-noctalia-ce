--!nonstrict
local open, tick = require("./lib/view.luau")("right")
open()
function update()
  tick()
end
