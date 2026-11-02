--!nonstrict
local open, tick = require("./lib/status.luau")(true)
function onOpen()
  open()
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
