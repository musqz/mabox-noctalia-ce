--!nonstrict
local open, tick = require("./lib/capture.luau")("left")
function onOpen()
  open()
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
