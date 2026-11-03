--!nonstrict
local open, tick = require("./lib/capture.luau")("right")
function onOpen()
  open()
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
