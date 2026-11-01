--!nonstrict
local open, tick, close, key = require("./lib/notes.luau")(false)
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
function onKey(chord, pressed)
  if pressed then
    key(chord)
  end
end
