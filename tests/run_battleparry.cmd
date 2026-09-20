@echo off
setlocal
rem Run tools\deploy.cmd first: the game loads mods\TERRARIUM, not this tree.
rem Speed 1, not 4: the parry is a frame-timing feature and the probe presses
rem inside an eight-frame band. Fast-forward is exactly the thing that would
rem make a passing run mean nothing.
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_battleparry
set POKEPORT_DRIVER=C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp\mods\TERRARIUM\tests\battleparry_probe.lua
set POKEPORT_SPEED=1
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
"%CD%\gen1recomp.exe" --console > "%DS_PROBE_DIR%\console.txt" 2>&1
