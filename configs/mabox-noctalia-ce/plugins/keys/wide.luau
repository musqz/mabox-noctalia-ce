--!nonstrict
local open, handleKey = require("./lib/keys.luau")(true)
function onOpen()
  open()
end
function onKey(chord, pressed)
  if pressed then
    handleKey(chord)
  end
end
