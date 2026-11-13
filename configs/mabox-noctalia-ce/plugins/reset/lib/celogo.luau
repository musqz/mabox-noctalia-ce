--!nonstrict
-- Copy of ~/.icons/mabox-logo.svg (mb-logo picks the style, Noctalia's templates set the colors).
-- ui.image caches by path, so the copy's name carries a checksum of the content.

local FALLBACK = "/usr/share/icons/mabox-logo.svg"
local logoFile, logoBody, checked = nil, nil, 0

local function logo()
  -- Widgets render every tick; the file only changes when the theme or style does.
  if os.time() - checked < 5 then
    return logoFile or FALLBACK
  end
  checked = os.time()
  local home = noctalia.getenv("HOME")
  local dir = noctalia.pluginDataDir()
  local body = home and noctalia.readFile(home .. "/.icons/mabox-logo.svg")
  if not (body and body ~= "" and dir) then
    return FALLBACK
  end
  if body ~= logoBody then
    local sum = 0
    for i = 1, #body do
      sum = (sum * 31 + string.byte(body, i)) % 4294967291
    end
    noctalia.mkdirAll(dir)
    local path = dir .. "/logo-" .. string.format("%x-%d", sum, #body) .. ".svg"
    if not noctalia.writeFile(path, body) then
      return FALLBACK
    end
    if logoFile and logoFile ~= path then
      noctalia.removeFile(logoFile)
    end
    logoFile, logoBody = path, body
  end
  return logoFile
end

return function(size)
  return ui.image({ path = logo(), width = size or 24, height = size or 24, fit = "contain" })
end
