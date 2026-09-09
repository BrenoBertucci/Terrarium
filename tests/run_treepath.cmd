@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_treepath
set DS_PROBE_TAG=%1
if "%DS_PROBE_TAG%"=="" set DS_PROBE_TAG=tp
set POKEPORT_DRIVER=mods/TERRARIUM/tests/treepath_probe.lua
set POKEPORT_SPEED=4
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
"%CD%\gen1recomp.exe" --console > "%DS_PROBE_DIR%\console_%DS_PROBE_TAG%.txt" 2>&1
echo exited %ERRORLEVEL%
