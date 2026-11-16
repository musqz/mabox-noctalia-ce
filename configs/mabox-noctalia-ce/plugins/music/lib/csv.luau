--!nonstrict
-- The mb-music CSV is parsed and edited by python: a Luau callback gets 25 ms of CPU time and the file loop used to exceed it.

local PY = [==[
import json, re, sys
mode, path = sys.argv[1], sys.argv[2]
try:
    raw = open(path, encoding="utf-8", errors="surrogateescape").read()
except OSError:
    raw = ""
if mode == "search":
    import urllib.parse, urllib.request
    name, tag = sys.argv[3], sys.argv[4]
    params = {"limit": "40", "hidebroken": "true", "order": "votes", "reverse": "true"}
    if name:
        params["name"] = name
    if tag:
        params["tag"] = tag
    out = None
    for host in ("de1", "nl1", "at1"):
        try:
            req = urllib.request.Request(
                "https://" + host + ".api.radio-browser.info/json/stations/search?" + urllib.parse.urlencode(params),
                headers={"User-Agent": "mabox-noctalia-ce"},
            )
            out = json.load(urllib.request.urlopen(req, timeout=6))
            break
        except Exception:
            continue
    if out is None:
        sys.exit(1)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    rows = []
    for s in out:
        url = s.get("url_resolved") or s.get("url") or ""
        name = " ".join((s.get("name") or "").split()).lstrip("# ")
        if name and re.match(r"^https?://\S+$", url):
            rows.append({"name": name, "url": url, "country": s.get("countrycode") or "", "codec": s.get("codec") or "", "bitrate": s.get("bitrate") or 0})
    print(json.dumps(rows, ensure_ascii=False))
elif mode == "addstation":
    import csv, io
    import os
    group, name, url = sys.argv[3], sys.argv[4], sys.argv[5]
    name = name.lstrip("# ")
    group = group.lstrip("# ")
    try:
        raw = open(path, encoding="utf-8", errors="surrogateescape", newline="").read()
    except OSError:
        raw = ""
    eol = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.split(eol)
    if lines and lines[-1] == "":
        lines.pop()
    def fmt(*fields):
        buf = io.StringIO()
        csv.writer(buf, lineterminator="").writerow(fields)
        return buf.getvalue()
    entry = fmt(name, url)
    start = None
    for i, l in enumerate(lines):
        row = next(csv.reader([l]), [])
        if len(row) >= 2 and row[1].strip() == "-" and row[0].strip() == group:
            start = i
            break
    if start is None:
        lines += [fmt(group, "-"), entry]
    else:
        def header(l):
            row = next(csv.reader([l]), [])
            return len(row) >= 2 and row[1].strip() == "-"
        at = next((i for i in range(start + 1, len(lines)) if header(lines[i])), len(lines))
        while at - 1 > start and lines[at - 1] == "":
            at -= 1
        lines.insert(at, entry)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write(eol.join(lines) + eol)
    os.replace(path + ".tmp", path)
elif mode == "radio":
    import csv
    cats, cur = [], None
    for row in csv.reader(l for l in raw.splitlines() if l and not l.startswith("#")):
        if len(row) < 2:
            continue
        name, url = row[0].strip(), row[1].strip()
        if url == "-":
            cur = {"name": name, "tracks": []}
            cats.append(cur)
        elif cur is not None and re.match(r"^https?://", url):
            cur["tracks"].append({"title": name, "url": url})
    for c in cats:
        c["playlist"] = [t["url"] for t in c["tracks"]]
    print(json.dumps({"cats": cats, "all": [u for c in cats for u in c["playlist"]]}))
elif mode == "list":
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
    open(path, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(lines) + "\n")
]==]

local M = {}

M.path = noctalia.getenv("HOME") .. "/.config/mabox/mb-music/yt_music_list.csv"

-- onDone gets nil when python failed, else the categories in file order, { {name=, header=, tracks={ {title=, url=} }, playlist={ url }, urls={ [url]=true }} },
-- and the list of all playable urls.
function M.list(onDone)
  noctalia.runAsync({ "python3", "-I", "-c", PY, "list", M.path }, function(r)
    local data = r.exitCode == 0 and noctalia.json.decode(r.stdout or "") or nil
    if data then
      onDone(data.cats, data.all)
    else
      onDone(nil, nil)
    end
  end)
end

-- PyRadio's stations.csv: same result as list.
M.radioPath = noctalia.getenv("HOME") .. "/.config/pyradio/stations.csv"

function M.radio(onDone)
  noctalia.runAsync({ "python3", "-I", "-c", PY, "radio", M.radioPath }, function(r)
    local data = r.exitCode == 0 and noctalia.json.decode(r.stdout or "") or nil
    if data then
      onDone(data.cats, data.all)
    else
      onDone(nil, nil)
    end
  end)
end

-- onDone gets nil when no server answered, else { {name=, url=, country=, codec=, bitrate=} } sorted by votes.
function M.search(name, tag, onDone)
  noctalia.runAsync({ "python3", "-I", "-c", PY, "search", M.radioPath, name, tag }, function(r)
    local ok, data = pcall(noctalia.json.decode, r.stdout or "")
    onDone(r.exitCode == 0 and ok and data or nil)
  end)
end

-- Appends the station to the group's end in stations.csv; an unknown group is created.
function M.addStation(group, name, url, onDone)
  noctalia.runAsync({ "python3", "-I", "-c", PY, "addstation", M.radioPath, group, name, url }, function(r)
    onDone(r.exitCode == 0)
  end)
end

-- header is the category's line in the file, "" for a new category called name.
function M.add(header, name, entry, onDone)
  noctalia.mkdirAll(string.match(M.path, "^(.*)/[^/]*$"))
  noctalia.runAsync({ "python3", "-I", "-c", PY, "add", M.path, header, name, entry }, function(r)
    onDone(r.exitCode == 0, r.exitCode)
  end)
end

return M
