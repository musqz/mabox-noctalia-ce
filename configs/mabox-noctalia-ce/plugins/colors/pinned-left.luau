--!nonstrict
local open, handleKey = require("./lib/picker.luau")("left")
function onOpen()
  open()
end
function onKey(chord, pressed)
  if pressed then
    handleKey(chord)
  end
end
