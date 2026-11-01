--!nonstrict
local open, tick = require("./lib/notes.luau")(true)
function onOpen()
  open()
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
