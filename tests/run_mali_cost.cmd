@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_mali
set POKEPORT_DRIVER=C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp\mods\TERRARIUM\tests\mali_cost_probe.lua
set POKEPORT_SPEED=1
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
echo starting %DATE% %TIME% > "%DS_PROBE_DIR%\launch.txt"
"%CD%\gen1recomp.exe" --console > "%DS_PROBE_DIR%\console.txt" 2>&1
echo exited %ERRORLEVEL% %DATE% %TIME% >> "%DS_PROBE_DIR%\launch.txt"
