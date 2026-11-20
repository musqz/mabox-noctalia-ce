--!nonstrict
local m = require("./lib/player-body.luau")()
function onClose()
  m.onClose()
end
function onOpen()
  m.onOpen()
end
