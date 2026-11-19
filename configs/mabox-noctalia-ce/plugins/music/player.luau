--!nonstrict
local m = require("./lib/player-body.luau")(false)
function onClose()
  m.onClose()
end
function onOpen()
  noctalia.runAsync({ "noctalia", "msg", "panel-close", "mabox/music:player-keep" }) -- a persistent copy gives way, so a hotkey never opens a second panel
  m.onOpen()
end
