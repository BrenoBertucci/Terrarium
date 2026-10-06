@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_perf
set POKEPORT_DRIVER=mods/TERRARIUM/tests/perf_attribution_probe.lua
set POKEPORT_SPEED=1
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
start /wait "" gen1recomp.exe --console
