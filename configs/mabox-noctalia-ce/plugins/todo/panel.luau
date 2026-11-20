--!nonstrict
local open, key = require("./lib/todo.luau")()
function onOpen(context)
  open(context)
end
function onKey(chord, pressed)
  if pressed then
    key(chord)
  end
end
