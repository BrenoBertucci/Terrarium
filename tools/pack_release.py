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
#   python tools/pack_release.py 1.33.0-beta
import io, os, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = sys.argv[1] if len(sys.argv) > 1 else "1.34.5-beta"
PREV = os.path.join(ROOT, "publish-zip", "TERRARIUM-1.32.0-beta.zip")
OUT = os.path.join(ROOT, "publish-zip", "TERRARIUM-%s.zip" % VERSION)

DROP_PREFIXES = ("probe_out_", "publish-zip/")

ADDED = [
    "lib/RenderTarget.lua",
    "lib/Device.lua",
    "lib/AutoQuality.lua",
    "lib/Diag.lua",
    "tests/diag_probe.lua",
    "tests/phone_repro_probe.lua",
    "tests/run_diag.cmd",
    "tests/run_phone_repro.cmd",
    "tools/essl1_check.py",
    "tests/mali_cost_probe.lua",
    "tests/visual_ab_probe.lua",
    "tests/autoquality_offline.lua",
    "tests/run_mali_cost.cmd",
    "tests/run_visual_ab.cmd",
    "tests/run_gpu_compat.cmd",
    "tools/run_autoquality_offline.py",
    "tools/pack_release.py",
]

prev = zipfile.ZipFile(PREV)
names = [n[len("TERRARIUM/"):] for n in prev.namelist() if not n.endswith("/")]
keep = [n for n in names if not n.startswith(DROP_PREFIXES)]
for n in ADDED:
    if n not in keep:
        keep.append(n)

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

# ------- AND THE CHECK THAT MAKES THE LIST ABOVE SAFE
#
# The list is hand-maintained, and a hand-maintained list of files is a list
# that will one day be missing the one that matters.  It nearly was: the first
# 1.34 zip left out lib/Diag.lua, which main.lua requires unconditionally --
# so the mod would not have loaded AT ALL on the device it was built for.
#
# Every lib/*.lua in the repo is required by something, so every one of them
# has to ship.  This is not a style rule, it is the difference between a mod
# and a black screen.
missing_lib = []
for f in sorted(os.listdir(os.path.join(ROOT, "lib"))):
    if f.endswith(".lua") and ("lib/" + f) not in keep:
        missing_lib.append("lib/" + f)
if missing_lib:
    print("REFUSING TO PACK: %d lib module(s) would not ship:" % len(missing_lib))
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
    print("MISSING FROM THE REPO (%d):" % len(missing))
    for m in missing[:20]:
        print("   ", m)
    sys.exit(1)
