"""Install Gen-2-style overworld roamer sheets into assets/roamers/.

These pixels are NOT in the repository. Same rule as the X/Y GUI pack
(tools/extract_xy_assets.py): crediting an author is not the same as holding
a licence from them, and the underlying art is Nintendo's and Game Freak's
whichever way it travels. See assets/roamers/CREDITS.md.

This script downloads the PokéPC Followers pack (ShockSlayer / Crystal Clear
lineage, packaged for Gen1Recomp) and renames its follower sheets into the
ids lib/RoamerArt.lua expects:

    assets/roamers/SANDSHREW.png
    assets/roamers/MR_MIME.png
    ...

Without them the mod still draws wild/town mons: RoamerArt falls back to a
greyscale bake from each species' battle front pic. The feature stays; the
art is worse.

Usage (from the mod root, or anywhere):

    python tools/install_roamer_sprites.py
    python tools/install_roamer_sprites.py --from C:/path/to/PokePCFollowers
    python tools/install_roamer_sprites.py --dry-run

Needs: Python 3, Pillow for the 16x96 check (optional but recommended),
and network access unless --from points at an already-downloaded tree/zip.
"""

from __future__ import annotations

import argparse
import io
import pathlib
import shutil
import sys
import tempfile
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / "assets" / "roamers"

# Default download: GitHub archive of the follower mod that already has
# 16x96 walker sheets for all 151 Gen 1 species under assets/sprites/.
DEFAULT_ZIP = (
    "https://github.com/gamecorner-033/PokePCFollowers"
    "/archive/refs/heads/main.zip"
)

# Engine species ids, National dex order (1..151). Matches Gen1Recomp's
# pokemon table keys, including the awkward ones.
SPECIES = [
    "BULBASAUR", "IVYSAUR", "VENUSAUR", "CHARMANDER", "CHARMELEON",
    "CHARIZARD", "SQUIRTLE", "WARTORTLE", "BLASTOISE", "CATERPIE",
    "METAPOD", "BUTTERFREE", "WEEDLE", "KAKUNA", "BEEDRILL",
    "PIDGEY", "PIDGEOTTO", "PIDGEOT", "RATTATA", "RATICATE",
    "SPEAROW", "FEAROW", "EKANS", "ARBOK", "PIKACHU",
    "RAICHU", "SANDSHREW", "SANDSLASH", "NIDORAN_F", "NIDORINA",
    "NIDOQUEEN", "NIDORAN_M", "NIDORINO", "NIDOKING", "CLEFAIRY",
    "CLEFABLE", "VULPIX", "NINETALES", "JIGGLYPUFF", "WIGGLYTUFF",
    "ZUBAT", "GOLBAT", "ODDISH", "GLOOM", "VILEPLUME",
    "PARAS", "PARASECT", "VENONAT", "VENOMOTH", "DIGLETT",
    "DUGTRIO", "MEOWTH", "PERSIAN", "PSYDUCK", "GOLDUCK",
    "MANKEY", "PRIMEAPE", "GROWLITHE", "ARCANINE", "POLIWAG",
    "POLIWHIRL", "POLIWRATH", "ABRA", "KADABRA", "ALAKAZAM",
    "MACHOP", "MACHOKE", "MACHAMP", "BELLSPROUT", "WEEPINBELL",
    "VICTREEBEL", "TENTACOOL", "TENTACRUEL", "GEODUDE", "GRAVELER",
    "GOLEM", "PONYTA", "RAPIDASH", "SLOWPOKE", "SLOWBRO",
    "MAGNEMITE", "MAGNETON", "FARFETCHD", "DODUO", "DODRIO",
    "SEEL", "DEWGONG", "GRIMER", "MUK", "SHELLDER",
    "CLOYSTER", "GASTLY", "HAUNTER", "GENGAR", "ONIX",
    "DROWZEE", "HYPNO", "KRABBY", "KINGLER", "VOLTORB",
    "ELECTRODE", "EXEGGCUTE", "EXEGGUTOR", "CUBONE", "MAROWAK",
    "HITMONLEE", "HITMONCHAN", "LICKITUNG", "KOFFING", "WEEZING",
    "RHYHORN", "RHYDON", "CHANSEY", "TANGELA", "KANGASKHAN",
    "HORSEA", "SEADRA", "GOLDEEN", "SEAKING", "STARYU",
    "STARMIE", "MR_MIME", "SCYTHER", "JYNX", "ELECTABUZZ",
    "MAGMAR", "PINSIR", "TAUROS", "MAGIKARP", "GYARADOS",
    "LAPRAS", "DITTO", "EEVEE", "VAPOREON", "JOLTEON",
    "FLAREON", "PORYGON", "OMANYTE", "OMASTAR", "KABUTO",
    "KABUTOPS", "AERODACTYL", "SNORLAX", "ARTICUNO", "ZAPDOS",
    "MOLTRES", "DRATINI", "DRAGONAIR", "DRAGONITE", "MEWTWO",
    "MEW",
]

FRAME_W, FRAME_H, FRAMES = 16, 16, 6
SHEET_H = FRAME_H * FRAMES  # 96


def log(msg: str) -> None:
    print(msg, flush=True)


def find_sprites_dir(root: pathlib.Path) -> pathlib.Path | None:
    """Locate assets/sprites under a pack root or any nested extract."""
    candidates = [
        root / "assets" / "sprites",
        root / "sprites",
    ]
    for c in candidates:
        if c.is_dir():
            return c
    # zip extracts as PokePCFollowers-main/...
    for child in root.rglob("assets/sprites"):
        if child.is_dir():
            return child
    return None


def download_zip(url: str, dest: pathlib.Path) -> None:
    log(f"downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "Terrarium-install-roamer-sprites/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    dest.write_bytes(data)
    log(f"  wrote {dest} ({len(data):,} bytes)")


def extract_zip(zip_path: pathlib.Path, out_dir: pathlib.Path) -> pathlib.Path:
    log(f"extracting {zip_path.name}")
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(out_dir)
    return out_dir


def resolve_source(species: str, dex: int, sprites: pathlib.Path) -> pathlib.Path | None:
    """Prefer species-named files, then dex-numbered, then case variants."""
    names = [
        f"follower_{species}.png",
        f"follower_{dex:03d}.png",
        f"{species}.png",
    ]
    for name in names:
        p = sprites / name
        if p.is_file():
            return p
    # case-insensitive fallback on case-sensitive filesystems
    lower = {p.name.lower(): p for p in sprites.glob("*.png")}
    for name in names:
        hit = lower.get(name.lower())
        if hit is not None:
            return hit
    return None


def check_sheet(path: pathlib.Path) -> tuple[bool, str]:
    """Return (ok, message). Pillow optional: without it, only existence."""
    try:
        from PIL import Image
    except ImportError:
        return True, "Pillow not installed -- skipped size check"

    with Image.open(path) as im:
        w, h = im.size
    if w != FRAME_W or h != SHEET_H:
        return False, f"expected {FRAME_W}x{SHEET_H}, got {w}x{h}"
    return True, f"{w}x{h}"


def install(sprites: pathlib.Path, dest: pathlib.Path, dry_run: bool) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    ok_n = 0
    missing: list[str] = []
    bad: list[str] = []

    for i, species in enumerate(SPECIES, start=1):
        src = resolve_source(species, i, sprites)
        if src is None:
            missing.append(species)
            continue
        target = dest / f"{species}.png"
        good, msg = check_sheet(src)
        if not good:
            bad.append(f"{species}: {msg} ({src.name})")
            continue
        if dry_run:
            log(f"  would copy {src.name} -> {target.name}  [{msg}]")
        else:
            shutil.copy2(src, target)
        ok_n += 1

    log("")
    log(f"installed {ok_n} / {len(SPECIES)} sheets into {dest}")
    if missing:
        log(f"missing ({len(missing)}): {', '.join(missing)}")
    if bad:
        log(f"rejected ({len(bad)}):")
        for line in bad:
            log(f"  {line}")
    if ok_n == len(SPECIES):
        log("all 151 species present.")
        return 0
    if ok_n == 0:
        log("nothing installed.")
        return 2
    log("partial install -- missing species fall back to the front-pic bake.")
    return 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--from",
        dest="source",
        metavar="PATH",
        help="local PokePCFollowers folder or .zip (skip download)",
    )
    ap.add_argument(
        "--url",
        default=DEFAULT_ZIP,
        help="zip URL when downloading (default: GitHub main archive)",
    )
    ap.add_argument(
        "--dest",
        type=pathlib.Path,
        default=DEST,
        help=f"output directory (default: {DEST})",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="list what would be copied, write nothing",
    )
    args = ap.parse_args(argv)

    tmp: tempfile.TemporaryDirectory[str] | None = None
    try:
        if args.source:
            src_path = pathlib.Path(args.source).expanduser().resolve()
            if not src_path.exists():
                log(f"not found: {src_path}")
                return 2
            if src_path.is_file() and src_path.suffix.lower() == ".zip":
                tmp = tempfile.TemporaryDirectory(prefix="roamers_")
                root = extract_zip(src_path, pathlib.Path(tmp.name))
            else:
                root = src_path
        else:
            tmp = tempfile.TemporaryDirectory(prefix="roamers_")
            tdir = pathlib.Path(tmp.name)
            zip_path = tdir / "pokepcfollowers.zip"
            try:
                download_zip(args.url, zip_path)
            except Exception as exc:  # noqa: BLE001 -- report and exit
                log(f"download failed: {exc}")
                log("pass --from PATH if you already have the pack unzipped.")
                return 2
            root = extract_zip(zip_path, tdir)

        sprites = find_sprites_dir(root)
        if sprites is None:
            log(f"no assets/sprites under {root}")
            return 2
        log(f"using sprites at {sprites}")
        return install(sprites, args.dest.resolve(), args.dry_run)
    finally:
        if tmp is not None:
            tmp.cleanup()


if __name__ == "__main__":
    sys.exit(main())
