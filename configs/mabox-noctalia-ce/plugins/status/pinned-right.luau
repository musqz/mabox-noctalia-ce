--!nonstrict
local open, tick = require("./lib/status.luau")("right")
function onOpen()
  open()
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
