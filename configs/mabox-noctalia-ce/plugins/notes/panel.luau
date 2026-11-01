--!nonstrict
local open, tick, close = require("./lib/notes.luau")(false)
function onOpen(context)
  open(context)
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
function onClose()
  close()
end
