--!nonstrict
-- Crypto view shared by the dropdown (pinned = false) and the pinned window (pinned = "left" or "right").
local crypto = require("./crypto.luau")
local pinSide = require("./side.luau")

local REFRESH = 15

return function(pinned)
local state = crypto.load()
local offline = false
local busy = false
local lastTry = 0
local addr = ""
local addrCheck = nil
local addrRun = 0
local render

local function refresh()
  if busy then
    return
  end
  busy = true
  lastTry = os.time()
  crypto.fetchPrices(state, function(ok)
    busy = false
    offline = not ok
    render()
  end)
end

local function stale()
  return os.time() - lastTry >= REFRESH and (os.time() - state.pricesAt >= REFRESH or state.pricesCur ~= state.currency)
end

local function clock(t)
  return os.date("%H:%M", t)
end

-- Number only, so it can be selected and copied; nil when there is nothing to show.
local function converted()
  local price = crypto.price(state)
  local amount = string.match(state.amount, "^%s*%d+[.,]?%d*%s*$") and tonumber((string.gsub(state.amount, ",", ".")))
  if not price or price <= 0 or not amount then
    return nil
  end
  return crypto.fmt(amount / price)
end

local function infoLine()
  local price = crypto.price(state)
  if not price then
    return offline and "Offline" or "Fetching..."
  end
  local line = string.format("1 %s = %s %s", crypto.COINS[state.coin].sym, crypto.fmt(price), string.upper(state.currency))
  if offline then
    return line .. ", offline, last update " .. clock(state.pricesAt)
  end
  return line .. ", updated " .. clock(state.pricesAt)
end

local function setCurrency(cur)
  state.currency = cur
  crypto.save(state, crypto.INPUT)
  render()
  refresh()
end

local function setCoin(i)
  state.coin = i
  crypto.save(state, crypto.INPUT)
  render()
end

-- Selects do not work in a layer, so the pinned window uses a typed code and chips.
local function currencyControl()
  local currencies = crypto.CURRENCIES
  if pinned then
    return ui.input({ key = "cur", value = string.upper(state.currency), placeholder = "EUR", controlSize = "sm", width = 80, frameVisible = true,
      onChange = function(v)
        local code = string.lower(string.match(v, "^%s*(.-)%s*$"))
        if code ~= state.currency and table.find(currencies, code) then
          setCurrency(code)
        end
      end })
  end
  local upper = {}
  for i, c in ipairs(currencies) do
    upper[i] = string.upper(c)
  end
  return ui.select({ key = "cur", options = upper, selectedIndex = crypto.currencyIndex(state) - 1,
    onChange = function(idx) setCurrency(currencies[tonumber(idx) + 1]) end })
end

local function coinControl()
  if pinned then
    local rows = {}
    for r = 0, 1 do
      local chips = {}
      for i = r * 3 + 1, r * 3 + 3 do
        table.insert(chips, ui.button({ key = "coin" .. i, text = crypto.COINS[i].sym, controlSize = "sm", flexGrow = 1,
          variant = i == state.coin and "primary" or "outline", onClick = function() setCoin(i) end }))
      end
      table.insert(rows, ui.row({ key = "coins" .. r, gap = 6 }, chips))
    end
    return ui.column({ key = "coinchips", gap = 6 }, rows)
  end
  local names = {}
  for i, c in ipairs(crypto.COINS) do
    names[i] = c.sym
  end
  return ui.select({ key = "coin", options = names, selectedIndex = state.coin - 1, onChange = function(idx) setCoin(tonumber(idx) + 1) end })
end

-- Offline format and checksum check (LTC, BTC, DOGE) through mb-crypto; says nothing about who owns the address.
local function checkAddress(text)
  addr = string.match(text, "^%s*(.-)%s*$")
  addrRun += 1
  local run = addrRun
  -- Shorter than any address: nothing to check yet, so no flicker while typing.
  if #addr < 26 then
    addrCheck = nil
    render()
    return
  end
  noctalia.runAsync({ "mb-crypto", "check", addr }, function(result)
    if run ~= addrRun then
      return
    end
    local out = noctalia.string.trim(result.stdout or "")
    addrCheck = { ok = result.exitCode == 0, text = out ~= "" and out or "Could not check" }
    render()
  end)
end

local function addressRows()
  local rows = {
    ui.label({ text = "Check an address (LTC, BTC, DOGE)", fontSize = 12, color = "on_surface_variant" }),
    ui.input({ key = "addr", value = addr, placeholder = "Paste an address", controlSize = "sm", frameVisible = true, onChange = checkAddress }),
  }
  if addrCheck then
    table.insert(rows, ui.label({ key = "addrres", text = addrCheck.text, fontSize = 12, color = addrCheck.ok and "primary" or "error" }))
  end
  return rows
end

local function resultRow()
  local num = converted()
  if not num then
    return ui.label({ text = crypto.price(state) and "Type an amount" or "No price yet", color = "on_surface_variant" })
  end
  -- value is the initial text only; a new key per number makes the box show the new one.
  return ui.row({ key = "result", gap = 6, align = "center" }, {
    ui.input({ key = "res-" .. num, value = num, controlSize = "sm", flexGrow = 1, frameVisible = true, tooltip = "Select and copy" }),
    ui.label({ text = crypto.COINS[state.coin].sym, color = "primary" }),
  })
end

local function header()
  local btns = { ui.label({ text = "Crypto", flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh price", onClick = refresh }),
    ui.button({ glyph = "external-link", variant = "ghost", controlSize = "sm", tooltip = "Open kraken.com prices",
      onClick = function() noctalia.runAsync({ "setsid", "-f", "xdg-open", "https://www.kraken.com/prices" }) end }) }
  if pinned then
    table.insert(btns, pinSide.dockButton("crypto", pinned, render))
    table.insert(btns, ui.button({ glyph = "arrows-left-right", variant = "ghost", controlSize = "sm", tooltip = "Move to the other side", onClick = function() pinSide.swap("crypto", pinned) end }))
  else
    table.insert(btns, ui.button({ glyph = "pin", variant = "ghost", controlSize = "sm", tooltip = "Pin window", onClick = function()
      panel.close()
      pinSide.toggle("crypto")
    end }))
  end
  table.insert(btns, ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() pinSide.close("crypto", pinned) end }))
  return ui.row({ gap = 8, align = "center" }, btns)
end

render = function()
  pinSide.render(pinned, ui.column({ gap = 10, padding = 12, flexGrow = pinned and 1 or nil }, {
    header(),
    ui.column({ key = "card", fill = "surface_variant", radius = 10, padding = 12, gap = 8, border = "primary", borderWidth = 1 }, {
      ui.row({ key = "inputs", gap = 6, align = "center" }, {
        ui.input({ key = "amount", value = state.amount, placeholder = "Amount", controlSize = "sm", flexGrow = 1, frameVisible = true,
          onChange = function(v)
            state.amount = v
            crypto.save(state, crypto.INPUT)
            render()
          end }),
        currencyControl(),
      }),
      coinControl(),
      resultRow(),
      ui.label({ text = infoLine(), fontSize = 12, color = "on_surface_variant" }),
    }),
    ui.column({ key = "addrcard", fill = "surface_variant", radius = 10, padding = 12, gap = 6, border = "primary", borderWidth = 1 }, addressRows()),
  }))
end

local function open()
  addr, addrCheck = "", nil
  addrRun += 1
  state = crypto.load()
  render()
  if stale() then
    refresh()
  end
  if not pinned then
    panel.setWantsSecondTicks(true)
  end
end

local function tick()
  if not busy and stale() then
    refresh()
  end
end

return open, tick
end
