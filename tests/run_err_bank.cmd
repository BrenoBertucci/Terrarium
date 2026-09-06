@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_err_bank
set POKEPORT_DRIVER=mods/TERRARIUM/tests/ledges_err_probe.lua
set POKEPORT_SPEED=4
set LEDGES_MODE=bank
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
echo starting %DATE% %TIME% > "%DS_PROBE_DIR%\launch.txt"
start /wait "" gen1recomp.exe --console
echo exited %ERRORLEVEL% %DATE% %TIME% >> "%DS_PROBE_DIR%\launch.txt"
