--!nonstrict
local m = require("./lib/panel-body.luau")(true)
function onOpen()
  m.onOpen()
end
function onKey(chord, pressed)
  m.onKey(chord, pressed)
end
