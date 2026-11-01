--!nonstrict
local open, tick, _, key = require("./lib/notes.luau")(true)
function onOpen()
  open()
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
function onKey(chord, pressed)
  if pressed then
    key(chord)
  end
end
