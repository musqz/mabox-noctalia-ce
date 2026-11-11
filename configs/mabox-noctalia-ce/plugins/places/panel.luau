--!nonstrict
local open, tick, close, key = require("./lib/places.luau")(false)
function onOpen(context)
  open(context)
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
