--!nonstrict
local m = require("./lib/panel-body.luau")(false)
function onOpen()
  noctalia.runAsync({ "noctalia", "msg", "panel-close", "mabox/agents:main-keep" }) -- a persistent copy gives way, so a hotkey never opens a second panel
  m.onOpen()
end
function onKey(chord, pressed)
  m.onKey(chord, pressed)
end
