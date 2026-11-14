--!nonstrict
-- Shows and hides the black cover layer: noctalia msg plugin mabox/configs:blank all show|hide
function onIpc(event)
  if event == "show" then
    noctalia.layer.configure("cover", { exclusiveZone = -1 })
    noctalia.layer.show("cover")
  elseif event == "hide" then
    noctalia.layer.hide("cover")
  end
end
