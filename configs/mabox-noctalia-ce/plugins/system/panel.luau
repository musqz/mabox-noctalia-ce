--!nonstrict
local open, handleKey = require("./lib/system.luau")()
function onOpen()
  noctalia.runAsync({ "noctalia", "msg", "panel-close", "mabox/system:system-keep" }) -- a persistent copy gives way, so a hotkey never opens a second panel
  open()
end
function onKey(chord, pressed)
  if pressed then
    handleKey(chord)
  end
end
