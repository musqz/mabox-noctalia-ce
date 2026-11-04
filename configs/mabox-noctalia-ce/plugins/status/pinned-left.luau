--!nonstrict
local open, tick, handleKey = require("./lib/status.luau")("left")
function onOpen()
  open()
  panel.setWantsSecondTicks(true)
end
function update()
  tick()
end
function onKey(chord, pressed)
  if pressed then
    handleKey(chord)
  end
end
