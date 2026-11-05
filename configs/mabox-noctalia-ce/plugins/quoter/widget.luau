--!nonstrict
-- Quoter desktop widget: a random `quote|author` line from /usr/share/mabox/quotes.txt.
-- ~/.config/quoter/quoter.conf may hold one line: the path of another quotes file.

local TICK_MS = 600000

local CMD = [[
f=/usr/share/mabox/quotes.txt
c="${XDG_CONFIG_HOME:-$HOME/.config}/quoter/quoter.conf"
if [ -r "$c" ]; then p=$(head -n1 "$c" | tr -d '\r'); p=${p/#\~/$HOME}; [ -r "$p" ] && f=$p; fi
grep -v '^[[:space:]]*$' "$f" 2>/dev/null | shuf -n1
]]

local quote, author = "", ""

local render

local function pick()
  noctalia.runAsync(CMD, function(r)
    local line = string.gsub(r.stdout or "", "[\r\n]+$", "")
    local q, a = string.match(line, "^(.*)|(.*)$")
    q = string.gsub(q or line, '^%s*"(.-)"%s*$', "%1")
    if q ~= "" then
      quote, author = q, noctalia.string.trim(a or "")
    elseif quote == "" then
      quote = "No quotes found in the quotes file."
    end
    render()
  end)
end

render = function()
  local body = {}
  if quote ~= "" then
    table.insert(body, ui.label({ text = quote, fontSize = 13, color = "on_surface" }))
    if author ~= "" then
      table.insert(body, ui.label({ text = "- " .. author, fontSize = 11, color = "primary" }))
    end
  end
  desktopWidget.render(ui.column({
    gap = 6,
    padding = 12,
    width = 300,
    fill = "surface/0.85",
    radius = 8,
    border = "outline",
    borderWidth = 1,
  }, body))
end

function update()
  pick()
end

noctalia.setUpdateInterval(TICK_MS)
desktopWidget.setWantsSecondTicks(false)
render()
pick()
