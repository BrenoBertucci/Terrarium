# Create the three open issues for the X/Y interface work.
#
# Run `gh auth login` first -- it asks questions and cannot be run for you.
# Then:
#
#     powershell -File .github/issues-draft/create.ps1
#
# Safe to re-read before running: it prints what it will do and asks once.
# It does NOT delete this folder afterwards; the drafts are the record of
# what was filed.

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

$issues = @(
    @{ file = "01-battle-menu.md"
       title = "Battle command menu: English labels, hand-tuned HUD shift, one window size"
       labels = "bug,ui" },
    @{ file = "02-town-map.md"
       title = "Town map still draws at Game Boy resolution"
       labels = "enhancement,ui" },
    @{ file = "03-move-select.md"
       title = "Move select in X/Y art (capsules with type badge and PP)"
       labels = "enhancement,ui" }
)

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
& $gh issue list --repo $repo --limit 10
