"""Records tests/reef_film_probe.lua with OBS Studio.

    py tools/record_film.py [--encoder qsv|x264] [--keep-open]

OBS is driven over its own websocket (obs-websocket 5, built in since OBS 28)
with a socket and two hashes -- no package to install. Everything it touches
is put back: the websocket server goes off again and global.ini (the profile
and scene collection OBS reopens with) is restored from a backup, so the next
time the user opens OBS by hand it is theirs, untouched.

Order matters. OBS goes up first and minimized, so the game takes the focus
last; the game's driver writes READY when the world is standing and then waits
for a file called GO, which is written once the recorder is actually rolling.
That way there is no black frame at the head and no rush at the tail.
"""
import base64
import ctypes
import ctypes.wintypes as wt
import hashlib
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

OBS_EXE = Path(r"C:\Program Files\obs-studio\bin\64bit\obs64.exe")
OBS_CFG = Path(os.environ["APPDATA"]) / "obs-studio"
WS_CFG = OBS_CFG / "plugin_config" / "obs-websocket" / "config.json"
GLOBAL_INI = OBS_CFG / "global.ini"
# which profile and collection OBS reopens with lives HERE, not in global.ini
USER_INI = OBS_CFG / "user.ini"
PROFILE = COLLECTION = "TerrariumFilm"

ROOT = Path(__file__).resolve().parent.parent
GAME = Path(r"C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp")
PROBE_DIR = ROOT / "probe_out_film"
VIDEO_DIR = ROOT / "video"
ENCODER = "qsv"
KEEP_OPEN = False
for i, a in enumerate(sys.argv[1:]):
    if a == "--encoder":
        ENCODER = sys.argv[i + 2]
    elif a == "--keep-open":
        KEEP_OPEN = True


# ------- the websocket, by hand
class OBSWS:
    def __init__(self, password, host="127.0.0.1", port=4455):
        self.sock = socket.create_connection((host, port), timeout=15)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            f"GET / HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            f"Sec-WebSocket-Version: 13\r\n\r\n".encode())
        self.buf = b""
        while b"\r\n\r\n" not in self.buf:
            self.buf += self.sock.recv(4096)
        self.buf = self.buf.split(b"\r\n\r\n", 1)[1]
        hello = self._read()["d"]
        ident = {"op": 1, "d": {"rpcVersion": hello["rpcVersion"]}}
        auth = hello.get("authentication")
        if auth:
            secret = base64.b64encode(
                hashlib.sha256((password + auth["salt"]).encode()).digest()).decode()
            ident["d"]["authentication"] = base64.b64encode(
                hashlib.sha256((secret + auth["challenge"]).encode()).digest()).decode()
        self._write(ident)
        while self._read()["op"] != 2:
            pass
        self.n = 0

    def _recv(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("obs closed the socket")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _read(self):
        while True:
            b1, b2 = self._recv(2)
            opcode, length = b1 & 0x0F, b2 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._recv(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._recv(8))[0]
            payload = self._recv(length)
            if opcode == 1:
                return json.loads(payload)
            if opcode == 8:
                raise ConnectionError("obs closed the connection")
            # ping: answer it and keep waiting for something to say
            if opcode == 9:
                self._frame(0xA, payload)

    def _frame(self, opcode, payload):
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        header = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        self.sock.sendall(header + mask + masked)

    def _write(self, obj):
        self._frame(1, json.dumps(obj).encode())

    def call(self, request, data=None, tolerate=False):
        self.n += 1
        rid = f"r{self.n}"
        self._write({"op": 6, "d": {"requestType": request, "requestId": rid,
                                    "requestData": data or {}}})
        while True:
            msg = self._read()
            if msg["op"] == 7 and msg["d"]["requestId"] == rid:
                status = msg["d"]["requestStatus"]
                if not status["result"] and not tolerate:
                    raise RuntimeError(f"{request}: {status.get('comment', status)}")
                return msg["d"].get("responseData") or {}


# ------- the game's window, for OBS to capture by name
def game_window(pid):
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def each(hwnd, _):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            title = ctypes.create_unicode_buffer(512)
            klass = ctypes.create_unicode_buffer(512)
            user32.GetWindowTextW(hwnd, title, 512)
            user32.GetClassNameW(hwnd, klass, 512)
            rect = wt.RECT()
            user32.GetClientRect(hwnd, ctypes.byref(rect))
            if title.value and rect.right > 200:
                found.append((title.value, klass.value,
                              rect.right - rect.left, rect.bottom - rect.top))
        return True

    user32.EnumWindows(each, 0)
    return found[0] if found else None


# ------- a profile and a scene collection of OUR OWN, written before OBS runs
#
# --profile and --collection only SWITCH to ones OBS already knows. Asking for
# names that do not exist does not create them: OBS shrugs and keeps the
# user's, and then every setting this script sends lands in THEIR setup. (It
# did, once. Their scene collection had to be picked back out of a .bak.)
def ensure_setup():
    scenes = OBS_CFG / "basic/scenes"
    mine = scenes / f"{COLLECTION}.json"
    if not mine.exists():
        # modelled on whatever collection is already there, so every field OBS
        # expects is one OBS itself wrote
        template = next((s for s in scenes.glob("*.json")), None)
        if template is None:
            raise SystemExit("no scene collection to model one on -- open OBS once")
        col = json.loads(template.read_text(encoding="utf-8"))
        col["name"] = COLLECTION
        for src in col.get("sources", []):
            if src.get("id") == "window_capture":
                src["settings"] = {"window": "", "method": 2, "priority": 2,
                                   "cursor": False, "client_area": True,
                                   "capture_audio": True}
            if src.get("id") == "scene":
                for item in src.get("settings", {}).get("items", []):
                    item["pos"] = {"x": 0.0, "y": 0.0}
                    item["scale"] = {"x": 1.0, "y": 1.0}
                    item["bounds_type"] = 0
            # the window brings its own sound; the desktop's would double it
            if src.get("id") in ("wasapi_output_capture", "wasapi_input_capture"):
                src["muted"] = True
        mine.write_text(json.dumps(col, indent=4), encoding="utf-8")
        print("wrote scene collection", mine.name)
    prof = OBS_CFG / "basic/profiles" / PROFILE
    if not (prof / "basic.ini").exists():
        prof.mkdir(parents=True, exist_ok=True)
        (prof / "basic.ini").write_text(f"""[General]
Name={PROFILE}

[Output]
Mode=Simple

[SimpleOutput]
FilePath={str(VIDEO_DIR).replace(chr(92), chr(92) * 2)}
RecFormat2=hybrid_mp4
RecQuality=HQ
RecEncoder={ENCODER}
RecAudioEncoder=aac
RecTracks=1
RecRB=false

[Video]
BaseCX=1536
BaseCY=864
OutputCX=1536
OutputCY=864
FPSType=0
FPSCommon=60
ScaleType=bicubic
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial

[Audio]
SampleRate=48000
ChannelSetup=Stereo
""", encoding="utf-8")
        print("wrote profile", PROFILE)


def main():
    VIDEO_DIR.mkdir(exist_ok=True)
    PROBE_DIR.mkdir(exist_ok=True)
    for stale in ("READY", "GO"):
        (PROBE_DIR / stale).unlink(missing_ok=True)

    ensure_setup()

    backup = VIDEO_DIR / "obs-backup"
    backup.mkdir(exist_ok=True)
    shutil.copy2(GLOBAL_INI, backup / "global.ini")
    shutil.copy2(USER_INI, backup / "user.ini")
    shutil.copy2(WS_CFG, backup / "websocket-config.json")
    ws_cfg = json.loads(WS_CFG.read_text(encoding="utf-8"))
    password = ws_cfg.get("server_password", "")
    was_on = ws_cfg.get("server_enabled", False)
    if not was_on:
        ws_cfg["server_enabled"] = True
        WS_CFG.write_text(json.dumps(ws_cfg, indent=2), encoding="utf-8")
        print("obs-websocket: turned on for this recording")

    # OBS leaves a .sentinel behind while it runs and deletes it on a clean
    # exit; finding one at startup it puts up a "crash or unclean shutdown"
    # dialog and waits -- forever, as far as a script is concerned, and the
    # websocket never comes up. (--disable-shutdown-check does not cover it.)
    sentinel = OBS_CFG / ".sentinel"      # a folder, one empty file per run
    if sentinel.is_dir():
        for stamp in sentinel.iterdir():
            stamp.unlink(missing_ok=True)
    # ...and NOT minimized to the tray: a tray icon has no window to send a
    # close to, so the only way out is a hard kill, which leaves the sentinel
    # for next time. The game takes the focus back anyway, and WGC capture
    # does not care what is in front.
    obs = subprocess.Popen(
        [str(OBS_EXE), "--disable-updater", "--disable-shutdown-check",
         "--profile", PROFILE, "--collection", COLLECTION],
        cwd=str(OBS_EXE.parent))
    ws = None
    for _ in range(60):
        time.sleep(1)
        try:
            ws = OBSWS(password)
            break
        except (ConnectionError, OSError):
            continue
    if ws is None:
        raise SystemExit("could not reach obs-websocket on 4455")
    print("obs:", ws.call("GetVersion")["obsVersion"])
    if ws.call("GetProfileList")["currentProfileName"] != PROFILE:
        ws.call("SetCurrentProfile", {"profileName": PROFILE})
        time.sleep(2)
    if ws.call("GetSceneCollectionList")["currentSceneCollectionName"] != COLLECTION:
        ws.call("SetCurrentSceneCollection", {"sceneCollectionName": COLLECTION})
        time.sleep(3)
    print("profile:", ws.call("GetProfileList")["currentProfileName"],
          "| collection:", ws.call("GetSceneCollectionList")["currentSceneCollectionName"])

    env = dict(os.environ)
    env.update({"POKEPORT_VERSION": "yellow",
                "DS_PROBE_DIR": str(PROBE_DIR),
                "POKEPORT_DRIVER": "mods/TERRARIUM/tests/reef_film_probe.lua",
                "POKEPORT_SPEED": "1"})
    game = subprocess.Popen([str(GAME / "gen1recomp.exe")], cwd=str(GAME), env=env)
    print("game started, waiting for the world to stand up...")
    ready = PROBE_DIR / "READY"
    for _ in range(600):
        if ready.exists():
            break
        if game.poll() is not None:
            raise SystemExit("the game quit before it was ready")
        time.sleep(1)
    if not ready.exists():
        raise SystemExit("the driver never said READY")

    win = game_window(game.pid)
    if not win:
        raise SystemExit("could not find the game's window")
    title, klass, cw, ch = win
    print(f"window: {title!r} {klass} {cw}x{ch}")
    # point the capture at the window that is actually up (OBS names a window
    # "title:class:exe", with colons in the title escaped)
    match = f"{title.replace(':', '#3A')}:{klass}:gen1recomp.exe"
    for name in [i["inputName"] for i in ws.call("GetInputList")["inputs"]
                 if i["inputKind"] == "window_capture"]:
        ws.call("SetInputSettings", {"inputName": name,
                                     "inputSettings": {"window": match, "method": 2,
                                                       "priority": 2, "cursor": False,
                                                       "client_area": True,
                                                       "capture_audio": True}})
    time.sleep(2)

    try:
        ws.call("StartRecord")
    except RuntimeError as err:                 # an encoder this box lacks
        print("start refused:", err, "-- falling back to x264")
        ws.call("SetProfileParameter", {"parameterCategory": "SimpleOutput",
                                        "parameterName": "RecEncoder",
                                        "parameterValue": "x264"})
        time.sleep(1)
        ws.call("StartRecord")
    time.sleep(2)
    if not ws.call("GetRecordStatus")["outputActive"]:
        raise SystemExit("obs says the recording is not running -- read its log")
    print("recording")
    (PROBE_DIR / "GO").write_text("go", encoding="utf-8")

    while game.poll() is None:
        time.sleep(1)
    time.sleep(1.5)
    out = ws.call("StopRecord")
    print("saved:", out.get("outputPath"))

    if not KEEP_OPEN:
        time.sleep(2)
        subprocess.run(["taskkill", "/IM", "obs64.exe"], capture_output=True)
        for _ in range(20):
            if obs.poll() is not None:
                break
            time.sleep(1)
        if obs.poll() is None:
            subprocess.run(["taskkill", "/F", "/IM", "obs64.exe"], capture_output=True)
        time.sleep(1)
        shutil.copy2(backup / "global.ini", GLOBAL_INI)
        shutil.copy2(backup / "user.ini", USER_INI)
        if not was_on:
            ws_cfg["server_enabled"] = False
            WS_CFG.write_text(json.dumps(ws_cfg, indent=2), encoding="utf-8")
        print("obs put back the way it was")
    return out.get("outputPath")


if __name__ == "__main__":
    main()
