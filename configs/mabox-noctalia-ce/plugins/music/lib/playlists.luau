--!nonstrict
-- Playlists are plain .m3u files in ~/.config/mabox/mb-music/playlists/, so mpv plays them directly and users can edit them by hand.
-- Python reads and writes them: a Luau callback gets 25 ms of CPU time.

local PY = [==[
import json, os, re, sys
mode, folder = sys.argv[1], sys.argv[2]

def clean(name):
    return re.sub(r"\s+", " ", name.replace("/", "-")).strip().lstrip(".")

def read(path):
    tracks, title = [], None
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return tracks
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("#EXTINF:"):
            title = line.split(",", 1)[1].strip() if "," in line else None
        elif line and not line.startswith("#"):
            tracks.append({"title": title or line, "url": line})
            title = None
    return tracks

def write(path, tracks):
    body = "#EXTM3U\n" + "".join("#EXTINF:-1," + " ".join(t["title"].split()) + "\n" + t["url"] + "\n" for t in tracks)
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(body)
    os.replace(path + ".tmp", path)

if mode == "load":
    out = []
    try:
        names = sorted(f[:-4] for f in os.listdir(folder) if f.endswith(".m3u"))
    except OSError:
        names = []
    names.sort(key=lambda n: (n != "Favourites", n.lower()))
    for n in names:
        tracks = read(os.path.join(folder, n + ".m3u"))
        out.append({"name": n, "tracks": tracks, "playlist": [t["url"] for t in tracks]})
    print(json.dumps(out, ensure_ascii=False))
else:
    name = clean(sys.argv[3])
    if not name:
        sys.exit(1)
    path = os.path.join(folder, name + ".m3u")
    if mode == "add":
        os.makedirs(folder, exist_ok=True)
        tracks = read(path)
        have = {t["url"] for t in tracks}
        for t in json.loads(sys.argv[4]):
            if t["url"] not in have:
                tracks.append(t)
                have.add(t["url"])
        write(path, tracks)
        print(name)
    elif mode == "remove":
        write(path, [t for t in read(path) if t["url"] != sys.argv[4]])
    elif mode == "delete":
        os.remove(path)
]==]

local M = {}

M.dir = noctalia.getenv("HOME") .. "/.config/mabox/mb-music/playlists"

-- One python run at a time: two runs reading the same .m3u would lose one of the changes.
local queue, running = {}, false

local function pump()
  if running or #queue == 0 then
    return
  end
  running = true
  local job = table.remove(queue, 1)
  noctalia.runAsync({ "python3", "-I", "-c", PY, table.unpack(job.args) }, function(r)
    running = false
    job.onDone(r.exitCode == 0, r.stdout)
    pump()
  end)
end

local function run(args, onDone)
  table.insert(queue, { args = args, onDone = onDone })
  pump()
end

-- onDone gets { {name=, tracks={ {title=, url=} }, playlist={ url }} }, Favourites first.
function M.load(onDone)
  run({ "load", M.dir }, function(ok, out)
    local good, data = pcall(noctalia.json.decode, out or "")
    onDone(ok and good and data or nil)
  end)
end

-- entries is a list of {title=, url=}; a missing playlist is created. onDone gets ok and the file name used (no slashes).
function M.add(name, entries, onDone)
  run({ "add", M.dir, name, noctalia.json.encode(entries) }, function(ok, out)
    onDone(ok, noctalia.string.trim(out or ""))
  end)
end

function M.remove(name, url, onDone)
  run({ "remove", M.dir, name, url }, onDone)
end

function M.delete(name, onDone)
  run({ "delete", M.dir, name }, onDone)
end

return M
