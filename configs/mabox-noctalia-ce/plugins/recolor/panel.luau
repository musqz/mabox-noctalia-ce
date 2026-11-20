--!nonstrict
local m = require("./lib/recolor.luau")()
function onOpen()
  m.onOpen()
end
function update()
  m.update()
end
