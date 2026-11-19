--!nonstrict
local open, key = require("./lib/todo.luau")()
function onOpen(context)
  noctalia.runAsync({ "noctalia", "msg", "panel-close", "mabox/todo:main-keep" }) -- a persistent copy gives way, so a hotkey never opens a second panel
  open(context)
end
function onKey(chord, pressed)
  if pressed then
    key(chord)
  end
end
