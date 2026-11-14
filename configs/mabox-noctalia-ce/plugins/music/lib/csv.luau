--!nonstrict
-- The mb-music CSV is parsed and edited by python: a Luau callback gets 25 ms of CPU time and the file loop used to exceed it.

local PY = [==[
import json, re, sys
mode, path = sys.argv[1], sys.argv[2]
try:
    raw = open(path, encoding="utf-8", errors="replace").read()
except OSError:
    raw = ""
if mode == "list":
    cats, cur = [], None
    for line in re.split(r"[\r\n]+", raw):
        m = re.match(r"^(.*),([^,]*)$", line)
        if not m:
            continue
        title, url = m.group(1), m.group(2).strip()
        if url == "-":
            name = re.sub(r"^[^0-9A-Za-z]+", "", title).strip()
            cur = None if name.upper() == "END" else {"name": name, "header": line, "tracks": [], "urls": {}}
            if cur:
                cats.append(cur)
        elif cur is not None:
            cur["urls"][url] = True
            if re.match(r"^https?://", url):
                cur["tracks"].append({"title": title.strip(), "url": url})
    for c in cats:
        c["playlist"] = [t["url"] for t in c["tracks"]]
    print(json.dumps({"cats": cats, "all": [u for c in cats for u in c["playlist"]]}))
else:
    header, name, entry = sys.argv[3], sys.argv[4], sys.argv[5]
    lines = raw.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if header == "":
        lines += ["\U000F0EA2 " + name + ",-", entry]
    else:
        first = next((i for i, l in enumerate(lines) if l == header), None)
        if first is None:
            sys.exit(1)
        at = next((i for i in range(first + 1, len(lines)) if lines[i].endswith(",-")), len(lines))
        while at - 1 > first and lines[at - 1] == "":
            at -= 1
        lines.insert(at, entry)
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
]==]

local M = {}

M.path = noctalia.getenv("HOME") .. "/.config/mabox/mb-music/yt_music_list.csv"

-- onDone gets the categories in file order, { {name=, header=, tracks={ {title=, url=} }, playlist={ url }, urls={ [url]=true }} },
-- and the list of all playable urls.
function M.list(onDone)
  noctalia.runAsync({ "python3", "-I", "-c", PY, "list", M.path }, function(r)
    local data = r.exitCode == 0 and noctalia.json.decode(r.stdout or "") or nil
    onDone(data and data.cats or {}, data and data.all or {})
  end)
end

-- header is the category's line in the file, "" for a new category called name.
function M.add(header, name, entry, onDone)
  noctalia.mkdirAll(string.match(M.path, "^(.*)/[^/]*$"))
  noctalia.runAsync({ "python3", "-I", "-c", PY, "add", M.path, header, name, entry }, function(r)
    onDone(r.exitCode == 0)
  end)
end

return M
