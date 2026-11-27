--!nonstrict
local m = require("./lib/sessions.luau")()
function onOpen()
  m.open()
end
function onKey(chord, pressed)
  if pressed then
    m.key(chord)
  end
end
