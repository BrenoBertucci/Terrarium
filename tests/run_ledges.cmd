@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_ledges
set POKEPORT_DRIVER=mods/TERRARIUM/tests/ledges_probe.lua
set POKEPORT_SPEED=4
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
echo starting %DATE% %TIME% > "%DS_PROBE_DIR%\launch.txt"
start /wait "" cmd /c "gen1recomp.exe --console > "%DS_PROBE_DIR%nsole.txt" 2>&1"
echo exited %ERRORLEVEL% %DATE% %TIME% >> "%DS_PROBE_DIR%\launch.txt"
