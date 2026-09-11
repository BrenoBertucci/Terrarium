# Build the release zip.
#
# The inclusion rule is the NAMELIST OF THE PREVIOUS ZIP, not a fresh reading
# of .modkitignore: the ignore file has been re-interpreted wrong before, and
# a namelist is a fact about what actually shipped and worked.
#
# Two departures from that rule, both deliberate:
#
#   * the junk directories the 1.32.0-beta zip picked up by accident are
#     dropped -- probe_out_void, probe_out_void2 and, worst of all,
#     publish-zip/ (the previous release zips, inside the release zip). That
#     is 32 of the 50 MB, and none of it is the mod.
#   * files added since the last zip are picked up from an explicit list, so
#     a new module cannot be left out silently.
#
#   python tools/pack_release.py 1.36.0-beta
import io, os, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = sys.argv[1] if len(sys.argv) > 1 else "1.36.0-beta"
PREV = os.path.join(ROOT, "publish-zip", "TERRARIUM-1.35.0-beta.zip")
OUT = os.path.join(ROOT, "publish-zip", "TERRARIUM-%s.zip" % VERSION)

DROP_PREFIXES = ("probe_out_", "publish-zip/")

ADDED = [
    "lib/RenderTarget.lua",
    "lib/Device.lua",
    "lib/AutoQuality.lua",
    "lib/Diag.lua",
    "lib/BreathFX.lua",
    "lib/LeafFallFX.lua",
    "lib/LeafLitter.lua",
    "lib/PuddleFX.lua",
    "lib/RainOnFX.lua",
    "lib/SnowFallFX.lua",
    "lib/SnowField.lua",
    "assets/weather/snowflake.png",
    "lib/WakeFX.lua",
]

prev = zipfile.ZipFile(PREV)
names = [n[len("TERRARIUM/"):] for n in prev.namelist() if not n.endswith("/")]
keep = [n for n in names if not n.startswith(DROP_PREFIXES)]
for n in ADDED:
    if n not in keep:
        keep.append(n)

# Every lib/*.lua has to ship. The first 1.34 zip left out Diag.lua and
# the mod would not have loaded on the device it was built for.
injected = []
for f in sorted(os.listdir(os.path.join(ROOT, "lib"))):
    if f.endswith(".lua"):
        rel = "lib/" + f
        if rel not in keep:
            keep.append(rel)
            injected.append(rel)
if injected:
    print("injected lib modules: %d" % len(injected))
    for m in injected:
        print("   ", m)

missing, total = [], 0
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for rel in sorted(set(keep)):
        src = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.isfile(src):
            missing.append(rel)
            continue
        z.write(src, "TERRARIUM/" + rel)
        total += os.path.getsize(src)

missing_lib = [m for m in missing if m.startswith("lib/") and m.endswith(".lua")]
if missing_lib:
    print("REFUSING TO PACK: %d lib module(s) missing from the repo:" % len(missing_lib))
    for m in missing_lib:
        print("   ", m)
    sys.exit(1)

print("prev zip entries : %d" % len(names))
print("dropped as junk  : %d" % (len(names) - len([n for n in names if not n.startswith(DROP_PREFIXES)])))
print("added new files  : %d" % len(ADDED))
print("written          : %s" % OUT)
print("entries          : %d   (%d MB uncompressed, %d MB zipped)"
      % (len(set(keep)) - len(missing), total // 1024 // 1024,
         os.path.getsize(OUT) // 1024 // 1024))
if missing:
    print("skipped deleted since prev zip (%d):" % len(missing))
    for m in missing[:20]:
        print("   ", m)
    fatal = [m for m in missing if m in ADDED]
    if fatal:
        print("REFUSING TO PACK: ADDED files missing from the repo")
        for m in fatal:
            print("   ", m)
        sys.exit(1)
