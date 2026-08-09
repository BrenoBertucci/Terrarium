# File open GitHub issues from the drafts in this folder.
#
# Run `gh auth login` first -- it asks questions and cannot be run unattended
# if you are not already logged in. Then, from the mod root:
#
#     powershell -File .github/issues-draft/create.ps1
#
# Safe to re-read before running: it prints what it will do and asks once.
# It does NOT delete this folder afterwards; the drafts are the record of
# what was filed.
#
# Pass -OnlyNew to skip the original X/Y trio (01-03) if those are already open.

param(
  [switch]$OnlyNew
)

$ErrorActionPreference = "Stop"
$gh = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) {
    $c = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $c) { throw "gh not found -- winget install GitHub.cli" }
    $gh = $c.Source
}

& $gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "not logged in -- run: gh auth login" }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = "BrenoBertucci/Terrarium"

$all = @(
    @{ file = "01-battle-menu.md"
       title = "Battle command menu: English labels, hand-tuned HUD shift, one window size"
       labels = "bug,ui" },
    @{ file = "02-town-map.md"
       title = "Town map still draws at Game Boy resolution"
       labels = "enhancement,ui" },
    @{ file = "03-move-select.md"
       title = "Move select in X/Y art (capsules with type badge and PP)"
       labels = "enhancement,ui" },
    @{ file = "04-roamer-bake-verify.md"
       title = "Verify REV 3 roamer front-pic bake in-game (Sandshrew / Growlithe)"
       labels = "bug,graphics" },
    @{ file = "05-purge-stale-roamer-bakes.md"
       title = "Purge stale derived roamer sheets when RoamerArt.REV bumps"
       labels = "enhancement,graphics" },
    @{ file = "06-ambient-tier2.md"
       title = "Ambient audio Tier 2 (stream, frogs, cicadas, fire, snow_wind, shop)"
       labels = "enhancement,audio" },
    @{ file = "07-ambient-ear-pass.md"
       title = "Ear-pass ambient gains and loop seams under map music"
       labels = "enhancement,audio" },
    @{ file = "08-pokepc-followers-bridge.md"
       title = "Optional: resolve roamer art from installed PokePC Followers mod"
       labels = "enhancement,graphics" },
    @{ file = "09-ambient-tier3-oneshots.md"
       title = "Ambient Tier 3 one-shots (door, wind gust, distant thunder)"
       labels = "enhancement,audio" },
    @{ file = "10-mod-page-optional-assets.md"
       title = "Catalog / mod page: surface optional asset installers (X/Y + roamers)"
       labels = "documentation" }
)

$issues = if ($OnlyNew) {
    $all | Where-Object { $_.file -match '^(0[4-9]|10)-' }
} else {
    $all
}

Write-Host "About to open $($issues.Count) issues on $repo :" -ForegroundColor Cyan
foreach ($i in $issues) { Write-Host "  - $($i.title)" }
$answer = Read-Host "`nProceed? (y/N)"
if ($answer -ne "y") { Write-Host "nothing created."; exit 0 }

foreach ($i in $issues) {
    $body = Join-Path $here $i.file
    if (-not (Test-Path $body)) { Write-Warning "missing $($i.file)"; continue }
    # --label fails the whole call if a label does not exist on the repo, so
    # the labelled attempt falls back to an unlabelled one rather than
    # leaving some issues filed and some not.
    & $gh issue create --repo $repo --title $i.title --body-file $body --label $i.labels
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "labels '$($i.labels)' rejected -- filing without labels"
        & $gh issue create --repo $repo --title $i.title --body-file $body
    }
}

Write-Host "`ndone. Listing:" -ForegroundColor Cyan
& $gh issue list --repo $repo --limit 20
