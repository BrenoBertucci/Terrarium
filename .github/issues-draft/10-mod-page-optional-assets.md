## Problem

Two optional asset paths need the same story on every surface a player
reads (catalog blurb, `description.md`, README, FEATURES):

1. **X/Y GUI pack** — `tools/extract_xy_assets.py`
2. **Roamer Gen-2 sheets** — `tools/install_roamer_sprites.py`

If only the GitHub README says it, catalog users never see it and file
"sprites unreadable" bugs that are install steps.

## Wanted

- Catalog / publish `description.md` has a short **Optional setup** section
  with both commands and one-line why the files are not in the zip.
- `mod.card` / known list no longer claims roamers are *only* front-pic
  bakes without mentioning the optional pack.
- Release notes for the next version repeat the installer line.

## Related

- Existing X/Y issue drafts under `.github/issues-draft/01-03`
- `assets/roamers/CREDITS.md`, `tools/extract_xy_assets.py`
