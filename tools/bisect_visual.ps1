# Bisseção do "post quebrado" — reverte por grupo, sincroniza e deixa você olhar.
#
# NADA aqui é destrutivo. Existe uma cópia completa da árvore de trabalho em
#   C:\Users\breno\Downloads\GBA\Terrarium-BACKUP-<data>
# e todo estado revertido volta com  .\tools\bisect_visual.ps1 restore
#
# USO — rode um passo, abra o jogo, olhe, volte aqui:
#
#   .\tools\bisect_visual.ps1 step1     só iluminação/post volta ao commit
#   .\tools\bisect_visual.ps1 step2     + clima e chão
#   .\tools\bisect_visual.ps1 step3     tudo que não está commitado sai
#   .\tools\bisect_visual.ps1 head      volta commits até antes desta sessão
#   .\tools\bisect_visual.ps1 restore   devolve TUDO como estava agora
#
# A pergunta que cada passo responde:
#   step1 conserta  -> está em RayFX / Sky / Voxel3D / VoxelScene
#   step2 conserta  -> está em Weather / GroundFX
#   step3 conserta  -> está no que não foi commitado, mas fora dos de cima
#   nenhum conserta -> está num COMMIT, não na árvore de trabalho: use `head`

param([Parameter(Position = 0)][string]$Cmd = "")

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $PSScriptRoot
$BUILD = "C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp\mods\TERRARIUM"
$BACKUP = Get-ChildItem "C:\Users\breno\Downloads\GBA" -Directory |
          Where-Object { $_.Name -like "Terrarium-BACKUP-*" } |
          Sort-Object Name -Descending | Select-Object -First 1

$POST    = @("lib/RayFX.lua", "lib/Sky.lua", "lib/Voxel3D.lua", "lib/VoxelScene.lua")
$WEATHER = @("lib/Weather.lua", "lib/GroundFX.lua")

function Sync {
  robocopy "$ROOT\lib" "$BUILD\lib" /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  robocopy "$ROOT\assets" "$BUILD\assets" /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  Write-Host "  sincronizado para o build" -ForegroundColor DarkGray
}

function Compile {
  $py = "C:\Users\breno\AppData\Local\Programs\Python\Python311\python.exe"
  & $py -c @"
from lupa import LuaRuntime
import pathlib, glob
b = pathlib.Path(r'$BUILD')
lua = LuaRuntime(); bad = 0
for p in sorted(glob.glob(str(b/'lib'/'*.lua')) + [str(b/'main.lua')]):
    try: lua.compile(pathlib.Path(p).read_text(encoding='utf-8-sig'))
    except Exception as e: print('  COMPILE FAIL', pathlib.Path(p).name, str(e)[:80]); bad += 1
print('  erros de compilacao:', bad)
"@
}

Set-Location $ROOT

switch ($Cmd) {
  "step1" {
    Write-Host "STEP 1 - revertendo SO iluminacao/post ao commit" -ForegroundColor Cyan
    git checkout -- $POST
    Sync; Compile
    Write-Host "Abra o jogo. O post voltou ao normal?" -ForegroundColor Yellow
  }
  "step2" {
    Write-Host "STEP 2 - + clima e chao" -ForegroundColor Cyan
    git checkout -- $POST $WEATHER
    Sync; Compile
    Write-Host "Abra o jogo. Agora sim?" -ForegroundColor Yellow
  }
  "step3" {
    Write-Host "STEP 3 - toda a arvore de trabalho volta ao commit" -ForegroundColor Cyan
    git checkout -- lib/
    Sync; Compile
    Write-Host "Abra o jogo. Se AINDA estiver quebrado, o problema esta num COMMIT." -ForegroundColor Yellow
  }
  "head" {
    Write-Host "Voltando a arvore ao commit anterior a esta sessao (4eb4dcf)" -ForegroundColor Cyan
    Write-Host "  (so os arquivos de lib -- assets e tests ficam)" -ForegroundColor DarkGray
    git checkout 4eb4dcf -- lib/
    Sync; Compile
    Write-Host "Abra o jogo. Isso e o mod antes da sessao inteira." -ForegroundColor Yellow
  }
  "restore" {
    if (-not $BACKUP) { Write-Host "BACKUP nao encontrado!" -ForegroundColor Red; exit 1 }
    Write-Host "Restaurando tudo de $($BACKUP.FullName)" -ForegroundColor Green
    robocopy $BACKUP.FullName $ROOT /MIR /XD .git /NFL /NDL /NJH /NJS /NP | Out-Null
    Sync; Compile
    Write-Host "Arvore de trabalho de volta ao estado de agora." -ForegroundColor Green
  }
  default {
    Write-Host "Backup encontrado: $($BACKUP.FullName)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  .\tools\bisect_visual.ps1 step1    so iluminacao/post"
    Write-Host "  .\tools\bisect_visual.ps1 step2    + clima e chao"
    Write-Host "  .\tools\bisect_visual.ps1 step3    tudo nao-commitado"
    Write-Host "  .\tools\bisect_visual.ps1 head     antes da sessao inteira"
    Write-Host "  .\tools\bisect_visual.ps1 restore  desfaz tudo isso"
  }
}
