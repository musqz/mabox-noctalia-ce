--!nonstrict
-- M-CE logo for panel headers. ui.image can't tint, so the file is written in the theme colors;
-- the file name carries the colors so a theme change loads a fresh file.
local M = "M80 240H16V16h224v224h-64V80h-16v160H96V80H80z"
local FRAME = "M0 0v256h256V0Zm16 16h224v224h-64V80h-16v160H96V80H80v160H16Z"
local logoFile, logoKey = nil, nil

local function path()
  local c1 = noctalia.getColor("primary")
  local c2 = noctalia.getColor("surface_container_highest") or noctalia.getColor("surface_variant")
  local dir = noctalia.pluginDataDir()
  if not (c1 and c2 and dir) then
    return nil
  end
  local key = string.sub(c1, 2) .. string.sub(c2, 2)
  if key ~= logoKey then
    noctalia.mkdirAll(dir)
    local file = dir .. "/mabox-ce-" .. key .. ".svg"
    local body = '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256">'
      .. '<rect width="256" height="256" fill="' .. c2 .. '"/>'
      .. '<path fill="' .. c1 .. '" d="' .. M .. '"/>'
      .. '<path fill="' .. c2 .. '" d="' .. FRAME .. '"/>'
      .. '<rect x="28" y="150" width="200" height="68" rx="6" fill="' .. c2 .. '"/>'
      .. '<text x="128" y="208" font-family="DejaVu Sans, Liberation Sans, Arial, sans-serif" font-size="62" font-weight="700" letter-spacing="6" text-anchor="middle" fill="' .. c1 .. '">CE</text></svg>'
    if not noctalia.writeFile(file, body) then
      return nil
    end
    if logoFile then
      noctalia.removeFile(logoFile)
    end
    logoFile, logoKey = file, key
  end
  return logoFile
end

return function()
  return ui.image({ path = path() or "/usr/share/icons/mabox-logo.svg", width = 24, height = 24, fit = "contain" })
end
