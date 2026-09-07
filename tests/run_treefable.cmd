@echo off
setlocal
rem Same driver as run_treevox.cmd, its own output folder: the two bakers'
rem probe runs must not overwrite each other's pictures.
set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_treefable
set DS_PROBE_TAG=%1
if "%DS_PROBE_TAG%"=="" set DS_PROBE_TAG=fable
set POKEPORT_DRIVER=mods/TERRARIUM/tests/treevox_probe.lua
set POKEPORT_SPEED=4
cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
"%CD%\gen1recomp.exe" --console > "%DS_PROBE_DIR%\console_%DS_PROBE_TAG%.txt" 2>&1
echo exited %ERRORLEVEL%
