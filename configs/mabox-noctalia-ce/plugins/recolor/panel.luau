--!nonstrict
local m = require("./lib/recolor.luau")(false)
function onOpen()
  noctalia.runAsync({ "noctalia", "msg", "panel-close", "mabox/recolor:main-keep" }) -- a persistent copy gives way, so a hotkey never opens a second panel
  m.onOpen()
end
function update()
  m.update()
end
