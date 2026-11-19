--!nonstrict
local m = require("./lib/player-body.luau")(true)
function onClose()
  m.onClose()
end
function onOpen()
  m.onOpen()
end
