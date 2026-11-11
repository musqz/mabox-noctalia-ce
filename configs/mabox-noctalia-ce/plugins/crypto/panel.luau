--!nonstrict
local open, tick = require("./lib/view.luau")(false)
function onOpen()
  open()
end
function update()
  tick()
end
