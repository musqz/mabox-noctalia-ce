--!nonstrict
local open, handleKey = require("./lib/configs.luau")("right")
function onOpen()
  open()
end
function onKey(chord, pressed)
  if pressed then
    handleKey(chord)
  end
end
