@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_treeshadow
set POKEPORT_DRIVER=mods/TERRARIUM/tests/treeshadow_probe.lua
set POKEPORT_SPEED=4
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
"%CD%\gen1recomp.exe" --console > "%DS_PROBE_DIR%\console.txt" 2>&1
echo exited %ERRORLEVEL%
