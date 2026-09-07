@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_treefable\motion
set DS_FRAMES=%1
if "%DS_FRAMES%"=="" set DS_FRAMES=40
set POKEPORT_DRIVER=mods/TERRARIUM/tests/treefable_motion_probe.lua
set POKEPORT_SPEED=1
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
"%CD%\gen1recomp.exe" --console > "%DS_PROBE_DIR%\console.txt" 2>&1
echo exited %ERRORLEVEL%
