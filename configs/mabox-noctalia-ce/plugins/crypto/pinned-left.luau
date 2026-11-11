--!nonstrict
local open, tick = require("./lib/view.luau")("left")
open()
function update()
  tick()
end
