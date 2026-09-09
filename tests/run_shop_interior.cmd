@echo off
setlocal
rem The Poke Mart interior probe (tests/shop_interior_probe.lua).
rem
rem The launchers in this folder assume the mod is already in the build --
rem tools\deploy.cmd is what mirrors lib/ tests/ assets/ data/ into
rem mods\TERRARIUM. This one calls it, because a probe that is being
rem written in the same session as the kit it photographs is the exact
rem case where running last week's copy is silent and wrong.
rem
rem   SHOP_MAP   VIRIDIAN_MART (default) | PEWTER_MART | CERULEAN_MART
rem              | LAVENDER_MART | CELADON_MART_1F | ...
rem   SHOP_TAG   filename stem for the log and the PNGs
rem   SHOP_AB    0 to skip the SHOP-row-off half
rem
rem Viridian, the default:
rem   tests\run_shop_interior.cmd
rem Another town -- set the vars on their own lines first, then run it
rem (REM does not escape the ampersand, so no one-liners in here):
rem   set SHOP_MAP=PEWTER_MART
rem   set SHOP_TAG=shop_pewter
rem   tests\run_shop_interior.cmd

set POKEPORT_VERSION=yellow
set DS_PROBE_DIR=C:\Users\breno\Downloads\GBA\Terrarium\probe_out_shop
set POKEPORT_DRIVER=mods/TERRARIUM/tests/shop_interior_probe.lua
set POKEPORT_SPEED=4
if "%SHOP_MAP%"=="" set SHOP_MAP=VIRIDIAN_MART
if "%SHOP_TAG%"=="" set SHOP_TAG=shop
if "%SHOP_LEVEL%"=="" set SHOP_LEVEL=4
if "%SHOP_AB%"=="" set SHOP_AB=1

call C:\Users\breno\Downloads\GBA\Terrarium\tools\deploy.cmd

cd /d C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp
mkdir "%DS_PROBE_DIR%" 2>nul
echo starting %SHOP_MAP% tag=%SHOP_TAG% %DATE% %TIME% > "%DS_PROBE_DIR%\launch.txt"
start /wait "" gen1recomp.exe --console
echo exited %ERRORLEVEL% %DATE% %TIME% >> "%DS_PROBE_DIR%\launch.txt"
echo.
echo ---- %DS_PROBE_DIR%\%SHOP_TAG%_probe.log ----
type "%DS_PROBE_DIR%\%SHOP_TAG%_probe.log" 2>nul | findstr /C:"ALL CHECKS PASSED" /C:"FAILURES" /C:"SKIPPED" /C:"SHOPKIT ABSENT" /C:"  - "
