--!nonstrict
local m = require("./lib/recolor.luau")(true)
function onOpen()
  m.onOpen()
end
function update()
  m.update()
end
