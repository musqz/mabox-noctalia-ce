--!nonstrict
local open, _, close = require("./lib/notes.luau")(false)
function onOpen(context)
  open(context)
end
function onClose()
  close()
end
