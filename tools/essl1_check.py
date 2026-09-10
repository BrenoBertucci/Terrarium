# The GLES2 rules this shader has to obey, checked as text, on every build.
#
# Two of the three bugs that have ever taken the 3D mode off a phone were
# invisible on every desktop in the room, because the region that carries them
# is compiled only by a GLES driver:
#
#   1.31  a uniform declared in the region BOTH stages compile, with no
#         precision qualifier, is `highp` in the vertex stage (its default)
#         and `mediump` in the fragment stage (LOVE emits
#         `precision mediump float;` there).  GLSL ES 1.00 matches uniforms by
#         name AND precision, so that is a LINK ERROR -- and a refused link is
#         Voxel3D.available() == false, which is the whole mode gone in
#         silence.  The fix was VXHP on all 36 of them.  Nothing stopped the
#         37th from arriving unqualified; this does.
#
#   1.33  the fragment stage's DEFAULT precision is mediump on GLES, so every
#         varying and every local was fp16 on a phone while being fp32 on
#         every machine here -- and this shader works in world pixels, which
#         run into the thousands, where fp16 has a resolution of one.  A
#         player called it television interference.  The fix is one
#         `precision highp float;` inside
#         `#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)`.
#         BOTH halves of that condition are load-bearing and neither is
#         obvious: GL_FRAGMENT_PRECISION_HIGH is ALSO defined on desktop,
#         where LOVE #defines `highp` to nothing, so the statement compiles to
#         `precision  float;` and takes the whole shader down.  (It did,
#         twice, before the second half went in.)
#
# So: assert both, as text, from the same source the mod ships.  Runs in a
# second and needs no GPU, which is the only reason it will actually be run.
#
#   python tools/essl1_check.py
import io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = io.open(os.path.join(ROOT, "lib", "Voxel3D.lua"), encoding="utf-8").read()

m = re.search(r"local SHADER = \[\[(.*?)\n\]\]", SRC, re.S)
if not m:
    sys.exit("could not find `local SHADER = [[ ... ]]` in lib/Voxel3D.lua")
shader = m.group(1)
lines = shader.split("\n")

fails = []


def check(ok, what, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  -- " + detail) if (detail and not ok) else ""))
    if not ok:
        fails.append(what)


print("== 1. fp32 reaches everything that carries a world coordinate ==")

# ------- TWO WAYS, BECAUSE ONE OF THEM IS NOT ENOUGH AND THE OTHER CAN BE
# ------- REFUSED
#
# `precision highp float;` has failed here in three distinct ways: it would
# not compile on desktop (LOVE #defines `highp` to nothing under #version
# 120), it took the 3D mode off the phone once that was guarded (LOVE
# forward-declares `effect` at its own mediump default BEFORE this file, and
# a definition that disagrees with its prototype is a compile error on GLES),
# and a Mali-G615 refused it outright even after that.
#
# And the alternative -- naming the declarations and raising those -- shipped
# as 1.34.2-beta, was ACCEPTED by that same Mali, and did not fix the static,
# because the shadow lookup's locals were not on the list.
#
# So the shader now carries both, as two rungs, and this file asserts the
# shape of each:
#
#   * the ONLY `precision` statements in the file sit behind BOTH
#     VX_GLOBAL_HP (so the ladder can drop them) and
#     `defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)` (so desktop
#     never sees them).  Both halves of that inner guard are load-bearing and
#     neither is obvious.
#   * every declaration on the named list still carries VXFP.
prec_lines = [(i, l.strip()) for i, l in enumerate(lines, 1)
              if l.strip().startswith("precision ")]
guard_ok = re.search(r"#if\s+defined\(VX_GLOBAL_HP\)\s*&&\s*defined\(PIXEL\)\s*\n"
                     r"#if\s+defined\(GL_ES\)\s*&&\s*defined\(GL_FRAGMENT_PRECISION_HIGH\)\s*\n"
                     r"precision highp float;", shader) is not None
check(bool(prec_lines) and guard_ok,
      "the %d `precision` statement(s) sit behind VX_GLOBAL_HP + GL_ES + "
      "GL_FRAGMENT_PRECISION_HIGH" % len(prec_lines),
      "found: " + "; ".join("line %d: %s" % p for p in prec_lines[:4]))

# and nothing outside that block: the guard is only worth having if it is the
# only door.  Counted by depth so a second, unguarded statement anywhere else
# in the file fails this rather than hiding behind the first one's PASS.
depth, guarded, loose = 0, 0, []
for i, raw in enumerate(lines, 1):
    t = raw.strip()
    if t.startswith("#if"):
        depth += 1
        if "VX_GLOBAL_HP" in t:
            depth = 1000          # inside the one block we allow
    elif t.startswith("#endif"):
        depth = 0 if depth >= 1000 and depth <= 1001 else max(0, depth - 1)
    elif t.startswith("precision "):
        if depth >= 1000:
            guarded += 1
        else:
            loose.append("line %d: %s" % (i, t))
check(not loose, "all %d of them are inside that one block" % guarded,
      "; ".join(loose[:4]))

check(re.search(r"#ifdef\s+FRAG_HIGHP\s*\n\s*#define\s+VXFP\s+"
                r"LOVE_HIGHP_OR_MEDIUMP\s*\n\s*#else\s*\n\s*#define\s+VXFP\s*\n",
                shader) is not None,
      "VXFP is LOVE_HIGHP_OR_MEDIUMP behind FRAG_HIGHP, and nothing without it",
      "FRAG_HIGHP is what lets Voxel3D.shader() drop the whole idea")

# The declarations that actually carry a world coordinate or a packed depth,
# named one by one: a list is the only way this stays honest as the shader
# grows -- and the shadow half of it is here because leaving it out is
# precisely what made 1.34.2-beta a wasted release.
WANT = {
    "varying VXFP vec3 vSun": "the sun lookup (shadow acne)",
    "float voxelHash(VXFP vec3 p)": "the fog stipple and the ground grain",
    "float mistHash(VXFP vec2 p)": "the mist's sin hash",
    "float mistNoise(VXFP vec2 p)": "the mist's value noise",
    "VXFP vec2 wz": "the water's own hash",
    "uniform VXFP Image sunMap": "the two-byte depth pack (samplers default to lowp)",
    "uniform VXFP float sunBias": "the depth compare's offset",
    "uniform VXFP vec2 sunTexel": "the filter's step, in shadow-map texels",
    "VXFP float sunDepth(VXFP vec2 uv)": "unpacking 16 bits of depth out of two bytes",
    "VXFP vec4 c = Texel(sunMap, uv)": "and holding them while it does",
    "VXFP float sunlight(VXFP vec3 p)": "the lit fraction itself",
    "VXFP float z = p.z - sunBias": "the value step() compares -- the acne, exactly",
}
missing = [w for w in WANT if w not in shader]
check(not missing, "all %d fp32-critical declarations carry VXFP" % len(WANT),
      "missing: " + "; ".join("%s (%s)" % (m, WANT[m]) for m in missing))

# ------- AND THE PROTOTYPE RULE THAT KILLED 1.34.0
#
# Kept, and load-bearing again now that a rung raises the default: this is
# the qualifier that stops that rung from repeating 1.34.0 exactly.
sig = re.search(r"vec4\s+effect\s*\(([^)]*)\)\s*\{", shader)
params = [p.strip() for p in sig.group(1).split(",")] if sig else []
SAMPLER_PARAM = re.compile(r"(Image|ArrayImage|CubeImage|VolumeImage)\b")
floaty = [p for p in params if not SAMPLER_PARAM.match(p)]
check(bool(floaty) and all(p.startswith("mediump ") for p in floaty),
      "effect() pins its float parameters to mediump, matching LOVE's prototype",
      "got: " + " | ".join(floaty))

print()
print("== 2. every uniform both stages compile carries an explicit precision ==")

# The scan has to know where it is.  Two things it must not flag, both learned
# by flagging them:
#   * a uniform inside `#ifdef VERTEX` (or PIXEL) is compiled by one stage and
#     has no counterpart to disagree with -- the four camera matrices live
#     there;
#   * a SAMPLER carries no float precision anybody links on, and LOVE's own
#     MainTex is declared without one.
SAMPLERS = ("Image", "ArrayImage", "CubeImage", "VolumeImage", "DepthImage",
            "DepthArrayImage", "DepthCubeImage", "sampler2D", "samplerCube")
QUALIFIED = ("VXHP", "highp", "mediump", "lowp", "LOVE_HIGHP_OR_MEDIUMP")

bad, total, stack = [], 0, []
for i, raw in enumerate(lines, 1):
    t = raw.strip()
    if t.startswith("#if"):
        stage = "VERTEX" if "VERTEX" in t else ("PIXEL" if "PIXEL" in t else None)
        stack.append(stage)
        continue
    if t.startswith("#endif"):
        if stack:
            stack.pop()
        continue
    if t.startswith("#el"):
        continue
    mm = re.match(r"uniform\s+(\S+)\s+", t)
    if not mm:
        continue
    if any(s for s in stack):          # inside a stage-specific block
        continue
    qual = mm.group(1)
    if qual in SAMPLERS:
        continue
    total += 1
    if qual not in QUALIFIED:
        bad.append("line %d: %s" % (i, t[:52]))

check(not bad, "all %d shared float uniforms are qualified" % total,
      "; ".join(bad[:6]))

print()
print("== 3. what the fp32 default is protecting ==")
# Not a failure: these are correct once the fragment stage is highp.  Named so
# that whoever ever has to drop that statement knows what breaks first.
hashes = re.findall(r"fract\(sin\(dot\([^;]*?\)\s*\*\s*([0-9.]+)\)", shader)
worst = max(hashes, key=float) if hashes else None
print("  note  %d sin-hashes in the shader (largest multiplier %s)"
      % (len(hashes), worst or "-"))
print("        sin() of a world coordinate is meaningless at fp16, and these")
print("        multiply the result by tens of thousands on purpose")

print()
if fails:
    print("%d FAILED" % len(fails))
    sys.exit(1)
print("ALL PASS")
