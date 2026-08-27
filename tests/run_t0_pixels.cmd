@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_t0_pix
set POKEPORT_DRIVER=C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp\mods\TERRARIUM\tests\t0_baseline_probe.lua
set T0_SKIP_COST=1
set POKEPORT_SPEED=4
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
echo starting %DATE% %TIME% > "%DS_PROBE_DIR%\launch.txt"
start /wait "" gen1recomp.exe --console
echo exited %ERRORLEVEL% %DATE% %TIME% >> "%DS_PROBE_DIR%\launch.txt"
