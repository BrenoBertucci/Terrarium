@echo off
setlocal
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_void
set POKEPORT_DRIVER=C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp\tests\void_rung_probe.lua
set POKEPORT_SPEED=4
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
echo DRIVER=%POKEPORT_DRIVER% > "%DS_PROBE_DIR%\launch.txt"
echo starting %DATE% %TIME% >> "%DS_PROBE_DIR%\launch.txt"
start /wait "" gen1recomp.exe --console
echo exited %ERRORLEVEL% %DATE% %TIME% >> "%DS_PROBE_DIR%\launch.txt"
