--!nonstrict
-- Theme-colored copy of the Mabox logo (ui.image can't tint); the file name carries the colors.

local LOGO_OUTER = "M67.733.927A66.806 66.806 0 0 0 .927 67.733a66.806 66.806 0 0 0 66.806 66.807 66.806 66.806 0 0 0 66.807-66.807A66.806 66.806 0 0 0 67.733.927Zm0 12.282a54.524 54.524 0 0 1 54.525 54.524 54.524 54.524 0 0 1-54.525 54.525A54.524 54.524 0 0 1 13.21 67.733 54.524 54.524 0 0 1 67.733 13.21ZM38.1 38.1v59.267h16.933V55.033h4.234v42.334H76.2V55.033h4.233v42.334h16.934V38.1Z"
local LOGO_INNER = "M67.733 13.209A54.524 54.524 0 0 0 13.21 67.733a54.524 54.524 0 0 0 54.524 54.525 54.524 54.524 0 0 0 54.525-54.525A54.524 54.524 0 0 0 67.733 13.21ZM38.1 38.1h59.267v59.267H80.433V55.033H76.2v42.334H59.267V55.033h-4.234v42.334H38.1Z"
local logoFile, logoKey = nil, nil

local function logo()
  local c1 = noctalia.getColor("primary")
  local c2 = noctalia.getColor("surface_container_highest") or noctalia.getColor("surface_variant")
  local dir = noctalia.pluginDataDir()
  if not (c1 and c2 and dir) then
    return "/usr/share/icons/mabox-logo.svg"
  end
  local key = string.sub(c1, 2) .. string.sub(c2, 2)
  if key ~= logoKey then
    noctalia.mkdirAll(dir)
    local path = dir .. "/logo-" .. key .. ".svg"
    local body = '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 135.467 135.467">'
      .. '<path fill="' .. c1 .. '" d="' .. LOGO_OUTER .. '"/>'
      .. '<path fill="' .. c2 .. '" d="' .. LOGO_INNER .. '"/></svg>'
    if not noctalia.writeFile(path, body) then
      return "/usr/share/icons/mabox-logo.svg"
    end
    if logoFile then
      noctalia.removeFile(logoFile)
    end
    logoFile, logoKey = path, key
  end
  return logoFile
end

return { logo = logo }
