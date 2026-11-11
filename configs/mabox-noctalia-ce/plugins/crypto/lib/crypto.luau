--!nonstrict
-- State and price fetching for the crypto panel; mb-crypto does the HTTP.
local M = {}

M.COINS = {
  { sym = "LTC" },
  { sym = "BTC" },
  { sym = "ETH" },
  { sym = "XMR" },
  { sym = "DOGE" },
  { sym = "SOL" },
}

M.CURRENCIES = { "eur", "usd" }

local function path()
  local dir = noctalia.pluginDataDir()
  return dir and dir .. "/state.json" or nil
end

function M.load()
  local state = { amount = "100", currency = "eur", coin = 1, prices = {}, pricesCur = "", pricesAt = 0 }
  local p = path()
  local raw = p and noctalia.readFile(p)
  local data = raw and noctalia.json.decode(raw)
  if type(data) == "table" then
    for k, v in pairs(data) do
      if type(v) == type(state[k]) then
        state[k] = v
      end
    end
  end
  if state.coin < 1 or state.coin > #M.COINS then
    state.coin = 1
  end
  return state
end

-- Writes only the given fields over the file, so another open view's changes are not overwritten.
function M.save(state, fields)
  local p = path()
  if not p then
    return
  end
  local disk = M.load()
  for _, k in ipairs(fields) do
    disk[k] = state[k]
  end
  noctalia.writeFile(p, noctalia.json.encode(disk, true) .. "\n")
end

M.INPUT = { "amount", "currency", "coin" }
M.PRICES = { "prices", "pricesCur", "pricesAt" }

function M.currencyIndex(state)
  for i, c in ipairs(M.CURRENCIES) do
    if c == state.currency then
      return i
    end
  end
  return 1
end

-- Fetches prices for the selected currency; cb(ok) after the state is updated.
function M.fetchPrices(state, cb)
  local cur = state.currency
  noctalia.runAsync({ "mb-crypto", "prices", cur }, function(result)
    local data = result.exitCode == 0 and noctalia.json.decode(result.stdout or "")
    if type(data) ~= "table" then
      cb(false)
      return
    end
    state.prices = data
    state.pricesCur = cur
    state.pricesAt = os.time()
    M.save(state, M.PRICES)
    cb(true)
  end)
end

-- Price of one coin in the selected currency, or nil when the cache is for another currency.
function M.price(state)
  if state.pricesCur ~= state.currency then
    return nil
  end
  return tonumber(state.prices[M.COINS[state.coin].sym])
end

function M.fmt(n)
  if n >= 1000 then
    return string.format("%.2f", n)
  end
  if n >= 1 then
    return string.format("%.4f", n)
  end
  return string.format("%.8f", n)
end

return M
