--!nonstrict
local open, handleKey = require("./lib/system.luau")()
function onOpen()
  open()
end
function onKey(chord, pressed)
  if pressed then
    handleKey(chord)
  end
end
