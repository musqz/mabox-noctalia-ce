--!nonstrict
-- Shows and hides the pinned window (a layer) on its saved side; mb-pinned and the window itself send the events.
local side = require("./lib/side.luau")
local shown = false

local function hide()
  noctalia.layer.hide("pinned-left")
  noctalia.layer.hide("pinned-right")
  shown = false
end

local function show()
  hide()
  local s = side.get("places")
  noctalia.layer.configure("pinned-" .. s, { exclusiveZone = side.docked("places") and side.ZONE or 0 })
  noctalia.layer.show("pinned-" .. s)
  shown = true
end

function onIpc(event)
  if event == "show" then
    show()
  elseif event == "hide" then
    hide()
  elseif event == "toggle" then
    if shown then
      hide()
    else
      show()
    end
  end
end
