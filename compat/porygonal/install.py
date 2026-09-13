#!/usr/bin/env python3
"""Install (or remove) Terrarium's renderer adapter inside an installed Porygonal.

Porygonal picks its renderer from a hardcoded CANDIDATES list in
renderers/renderer_manager.lua, so shipping the adapter file is only half of
it: the manager has to be told the candidate exists.  Both halves are done
here, idempotently, and both are undone by --uninstall.

    python install.py [--porygonal <path>] [--uninstall] [--dry-run]

The manager edit is a five-line insertion into CANDIDATES.  The original file
is kept beside it as renderer_manager.lua.pre-terrarium so --uninstall can put
it back untouched, and so a Porygonal update that overwrites the manager is
visible as a missing backup rather than a silently lost patch.
"""

import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

DEFAULT_PORYGONAL = (
    r"C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps"
    r"\PokemonRedBlueYellow-Gen1RecompProject-Recomp\mods"
    r"\PORYGONAL_OVERWORLD_CHARACTERS")

MANAGER = os.path.join("renderers", "renderer_manager.lua")
BACKUP = MANAGER + ".pre-terrarium"
ADAPTER_DIR = os.path.join("renderers", "terrarium")

# The last entry of upstream's CANDIDATES list, used as the anchor: appending
# after it keeps Terrarium's entry out of the middle of the file, so a
# re-applied patch is one contiguous block at a predictable place.
ANCHOR = """\
    {
        name = "Battle Art Voxel",
        path = "renderers/battle_art_voxel/battle_art_voxel_adapter.lua"
    }
"""

ENTRY = """\
    {
        name = "Battle Art Voxel",
        path = "renderers/battle_art_voxel/battle_art_voxel_adapter.lua"
    },

    -- Terrarium (a Dramatic Shape Voxel Mod fork).  Its own file rather than
    -- the Dramatic Shape one because detection is by exact mod id and three
    -- of the wrapped signatures gained a parameter after 1.8.2; see
    -- renderers/terrarium/TERRARIUM_README.txt.
    {
        name = "Terrarium",
        path = "renderers/terrarium/terrarium_adapter.lua"
    }
"""

MARKER = 'path = "renderers/terrarium/terrarium_adapter.lua"'


def fail(message):
    print(message, file=sys.stderr)
    return 1


def install(root, dry_run):
    manager = os.path.join(root, MANAGER)
    if not os.path.isfile(manager):
        return fail("not a Porygonal install (no %s): %s" % (MANAGER, root))

    source_dir = os.path.join(HERE, ADAPTER_DIR)
    adapter = os.path.join(source_dir, "terrarium_adapter.lua")
    if not os.path.isfile(adapter):
        return fail("%s is missing -- run make_adapter.py first" % adapter)

    with open(manager, "r", encoding="utf-8") as handle:
        text = handle.read()

    if MARKER in text:
        print("candidate  : already registered")
    elif ANCHOR not in text:
        return fail(
            "renderer_manager.lua does not contain the expected CANDIDATES "
            "anchor.\nUpstream has moved; update ANCHOR/ENTRY in install.py "
            "rather than patching by hand.")
    else:
        if not dry_run:
            if not os.path.exists(os.path.join(root, BACKUP)):
                shutil.copy2(manager, os.path.join(root, BACKUP))
            with open(manager, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(text.replace(ANCHOR, ENTRY))
        print("candidate  : registered in %s" % MANAGER)

    target_dir = os.path.join(root, ADAPTER_DIR)
    if not dry_run:
        os.makedirs(target_dir, exist_ok=True)
        for name in sorted(os.listdir(source_dir)):
            shutil.copy2(os.path.join(source_dir, name),
                         os.path.join(target_dir, name))
    print("adapter    : %s" % target_dir)
    print("\nEnable both mods, then check OPTION -> PORYGONAL: it should name")
    print("Terrarium as the active target mod.")
    return 0


def uninstall(root, dry_run):
    manager = os.path.join(root, MANAGER)
    backup = os.path.join(root, BACKUP)

    if os.path.isfile(backup):
        if not dry_run:
            shutil.copy2(backup, manager)
            os.remove(backup)
        print("candidate  : reverted from %s" % BACKUP)
    elif os.path.isfile(manager):
        with open(manager, "r", encoding="utf-8") as handle:
            text = handle.read()
        if MARKER in text and ENTRY in text:
            if not dry_run:
                with open(manager, "w", encoding="utf-8",
                          newline="\n") as handle:
                    handle.write(text.replace(ENTRY, ANCHOR))
            print("candidate  : removed (no backup found; unpatched in place)")
        else:
            print("candidate  : not registered")

    target_dir = os.path.join(root, ADAPTER_DIR)
    if os.path.isdir(target_dir):
        if not dry_run:
            shutil.rmtree(target_dir)
        print("adapter    : removed %s" % target_dir)
    else:
        print("adapter    : not present")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--porygonal", default=DEFAULT_PORYGONAL,
                    help="path to the installed Porygonal mod folder")
    ap.add_argument("--uninstall", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = args.porygonal
    if not os.path.isdir(root):
        return fail("no such directory: %s" % root)

    print("porygonal  : %s" % root)
    if args.uninstall:
        return uninstall(root, args.dry_run)
    return install(root, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
