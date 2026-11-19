--!nonstrict
local m = require("./lib/snippets-body.luau")(false)
function onKey(chord, pressed)
  m.onKey(chord, pressed)
end
function onOpen()
  noctalia.runAsync({ "noctalia", "msg", "panel-close", "mabox/insert:snippets-keep" }) -- a persistent copy gives way, so a hotkey never opens a second panel
  m.onOpen()
end
