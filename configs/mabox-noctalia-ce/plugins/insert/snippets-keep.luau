--!nonstrict
local m = require("./lib/snippets-body.luau")(true)
function onKey(chord, pressed)
  m.onKey(chord, pressed)
end
function onOpen()
  m.onOpen()
end
