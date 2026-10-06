# The CRT lab's server: assets/crt/crt.glsl run in WebGL 1 over real frames
# of the game, with LOVE's own GLSL preamble around it.
#
#   py tools/crt_lab/serve.py <love.dll> <out dir> [port]
#
# WebGL 1 compiles through ANGLE's ESSL 1.00 front end, which is as strict as
# the compiler on a Mali -- so a pass that runs here is a pass a phone will
# link, and a look tuned here is a look tuned in seconds instead of a game
# boot. GET /preamble.json is the preamble cut out of love.dll (the GLSL
# table up to _shaderCodeToGLSL, the same bytes LOVE wraps a shader in);
# POST /save/<name> writes the posted bytes to <out dir>/<name>.
import http.server
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LAB = os.path.dirname(os.path.abspath(__file__))
DLL, OUT = sys.argv[1], sys.argv[2]
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 8765


def preamble():
    d = open(DLL, "rb").read()
    i = d.find(b"local GLSL = {}")
    j = d.find(b"local function getLanguageTarget", i)
    src = d[i:j].decode("latin-1")
    out = {}
    for key, body in re.findall(r"(GLSL\.SYNTAX|GLSL\.UNIFORMS|GLSL\.FUNCTIONS) = \[\[(.*?)\]\]", src, re.S):
        out[key.split(".")[1]] = body
    pix = src[src.find("GLSL.PIXEL = {"):]
    for key, body in re.findall(r"\b(HEADER|FUNCTIONS|MAIN) = \[\[(.*?)\]\]", pix, re.S):
        out.setdefault("PIXEL_" + key, body)
    return out


# lib/CRT.lua's own CRT.uniforms, run through lupa with a stub mod namespace,
# so the lab draws with exactly the numbers the game sends. `room` picks an
# hour and the GLOW row through stub DayNight / Glow modules.
LUA_STUB = r"""
local ROOT, HOUR, GLOW = ...
love = { graphics = {}, timer = {}, math = {} }
local V = { mod = { id = "TERRARIUM", options = { get = function() return nil end } } }
local MIX = { day = { day = 1 }, dusk = { dusk = 1 }, night = { night = 1 }, golden = { golden = 1 } }
local cache = {
  DayNight = { time = function() return 0 end, mix = function() return MIX[HOUR] or MIX.day end,
               lampColor = function() return { 1.0, 0.84, 0.5 } end },
  Glow = { enabled = function() return GLOW end },
  Weather = { flash = function() return 0 end },
}
function V.require(name)
  if cache[name] ~= nil then return cache[name] end
  local v = assert(loadfile(ROOT .. "/lib/" .. name .. ".lua"))(V)
  cache[name] = v
  return v
end
return V.require("CRT")
"""
_crt = None


def lua_to_py(v):
    if hasattr(v, "items"):
        d = {k: lua_to_py(x) for k, x in v.items()}
        if not d:
            return []
        if all(isinstance(k, int) for k in d):
            return [d[i] for i in range(1, len(d) + 1)]
        return d
    return v


def uniforms(q):
    import lupa.lua51 as lua51
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    crt = rt.execute(LUA_STUB, ROOT.replace("\\", "/"), q.get("room", "day"), q.get("glow", "1") == "1")
    room = crt.roomTarget()
    room.flash = float(q.get("flash", 0))
    P = crt.preset(q.get("preset", "home"), q.get("lite", "0") == "1")
    anim = crt.moment(q["anim"], float(q.get("t", 0))) if q.get("anim") else None
    env = rt.table_from({
        "W": int(q["w"]), "H": int(q["h"]), "sp": float(q["sp"]), "top": float(q.get("top", 0)),
        "frame": int(q.get("frame", 0)), "seed": float(q.get("seed", 0.37)),
        "clock": float(q.get("clock", 0)), "bezel": q.get("bezel", "0") == "1",
        "anim": anim, "room": room, "dt": 1 / 60})
    return lua_to_py(crt.uniforms(P, env))


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_bytes(self, data, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/uniforms":
            from urllib.parse import parse_qsl
            q = dict(parse_qsl(self.path.split("?", 1)[1] if "?" in self.path else ""))
            try:
                return self.send_bytes(json.dumps(uniforms(q)).encode(), "application/json")
            except Exception as e:
                return self.send_bytes(json.dumps({"error": str(e)}).encode(), "application/json")
        if path == "/preamble.json":
            return self.send_bytes(json.dumps(preamble()).encode(), "application/json")
        if path == "/glsl":
            return self.send_bytes(open(os.path.join(ROOT, "assets", "crt", "crt.glsl"), "rb").read(), "text/plain")
        if path in ("/", "/index.html"):
            return self.send_bytes(open(os.path.join(LAB, "index.html"), "rb").read(), "text/html")
        if path.startswith("/frames/"):
            f = os.path.normpath(os.path.join(ROOT, path[len("/frames/"):]))
            if f.startswith(ROOT) and os.path.isfile(f):
                return self.send_bytes(open(f, "rb").read(), "image/png")
        self.send_error(404)

    def do_POST(self):
        if not self.path.startswith("/save/"):
            return self.send_error(404)
        name = os.path.basename(self.path[len("/save/"):])
        n = int(self.headers.get("Content-Length", 0))
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(self.rfile.read(n))
        self.send_bytes(b"ok", "text/plain")

    def log_message(self, *a):
        pass


os.makedirs(OUT, exist_ok=True)
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
