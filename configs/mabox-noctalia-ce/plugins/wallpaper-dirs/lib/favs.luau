--!nonstrict
-- Noctalia's wallpaper favorites: [[wallpaper.favorite]] blocks in the state file settings.toml. There is no msg command
-- for them, so python edits only those blocks (temp file + rename) and the config is reloaded afterwards.
local M = {}

local PY = [=[import json, os, shutil, sys, tempfile
act, path = sys.argv[1], sys.argv[2]
base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
f = base + "/noctalia/settings.toml"
try:
    lines = open(f, errors="replace").read().split("\n")
except OSError:
    lines = []
HEAD = "[[wallpaper.favorite]]"

def blocks():
    out, i = [], 0
    while i < len(lines):
        if lines[i].strip() == HEAD:
            j = i + 1
            while j < len(lines) and lines[j].strip() != "" and not lines[j].strip().startswith("["):
                j += 1
            val = ""
            for l in lines[i + 1:j]:
                k, _, v = l.partition("=")
                if k.strip() == "path":
                    v = v.strip()
                    try:
                        val = json.loads(v) if v.startswith('"') else v.strip("'")
                    except ValueError:
                        val = v.strip('"')
            out.append((i, j, val))
            i = j
        else:
            i += 1
    return out

def theme():
    cur, t = None, {}
    for l in lines:
        s = l.strip()
        if s.startswith("["):
            cur = s
        elif cur == "[theme]" and "=" in s:
            k, _, v = s.partition("=")
            t[k.strip()] = v.strip()
    return t

def save():
    d = os.path.dirname(f)
    fd, tmp = tempfile.mkstemp(dir=d)
    with os.fdopen(fd, "w") as o:
        o.write("\n".join(lines))
    try:
        shutil.copymode(f, tmp)
    except OSError:
        pass
    os.replace(tmp, f)

if act == "list":
    for _, _, v in blocks():
        print(v)
elif act == "add":
    if any(v == path for _, _, v in blocks()):
        sys.exit(0)
    t = theme()
    src = t.get("source", '"wallpaper"').strip('"')
    new = ["    " + HEAD, '    palette_source = "' + src + '"', '    path = ' + json.dumps(path, ensure_ascii=False)]
    if "mode" in t:
        new.append("    theme_mode = " + t["mode"])
    extra = {"wallpaper": ("wallpaper_scheme", "wallpaper_scheme"), "builtin": ("builtin_palette", "builtin"),
             "community": ("community_palette", "community_palette"), "custom": ("custom_palette", "custom_palette")}
    if src in extra and extra[src][1] in t:
        new.append("    " + extra[src][0] + " = " + t[extra[src][1]])
    while lines and lines[-1].strip() == "":
        lines.pop()
    lines += [""] + [new[0]] + sorted(new[1:]) + [""]
    save()
elif act == "remove":
    hit = [(i, j) for i, j, v in blocks() if v == path]
    if not hit:
        sys.exit(0)
    for i, j in reversed(hit):
        del lines[i:j + 1 if j < len(lines) and lines[j].strip() == "" else j]
    save()]=]

local function run(args, cb)
  local cmd = { "python3", "-I", "-c", PY }
  for _, a in ipairs(args) do
    table.insert(cmd, a)
  end
  noctalia.runAsync(cmd, function(r)
    if r.exitCode == 0 then
      noctalia.runAsync({ "noctalia", "msg", "config-reload" }, function()
        cb(r)
      end)
    else
      cb(r)
    end
  end)
end

-- Reading needs no reload.
function M.list(cb)
  noctalia.runAsync({ "python3", "-I", "-c", PY, "list", "" }, function(r)
    local out = {}
    for l in string.gmatch(r.stdout or "", "[^\n]+") do
      table.insert(out, l)
    end
    cb(out)
  end)
end

function M.add(path, cb)
  run({ "add", path }, cb)
end

function M.remove(path, cb)
  run({ "remove", path }, cb)
end

function M.apply(path, cb)
  noctalia.runAsync({ "noctalia", "msg", "wallpaper-set", path }, cb)
end

-- The default wallpaper path.
function M.current(cb)
  noctalia.runAsync({ "noctalia", "msg", "wallpaper-get" }, function(r)
    cb(noctalia.string.trim(string.match(r.stdout or "", "[^\n]+") or ""))
  end)
end

return M
