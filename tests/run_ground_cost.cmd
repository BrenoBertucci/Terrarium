@echo off
setlocal
set POKEPORT_VERSION=yellow
if "%DS_PROBE_DIR%"=="" set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_ground_cost
set POKEPORT_DRIVER=mods/TERRARIUM/tests/ground_cost_probe.lua
set POKEPORT_SPEED=4
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
copy /y options.lua options.lua.ground-cost.bak >nul
start /wait "" gen1recomp.exe --console
copy /y options.lua.ground-cost.bak options.lua >nul
del options.lua.ground-cost.bak
