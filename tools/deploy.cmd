@echo off
setlocal
set SRC=C:\Users\breno\Downloads\GBA\Terrarium
set DST=C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps\PokemonRedBlueYellow-Gen1RecompProject-Recomp\mods\TERRARIUM
robocopy "%SRC%\lib" "%DST%\lib" /MIR /NFL /NDL /NJH /NJS /NP >nul
robocopy "%SRC%\tests" "%DST%\tests" /MIR /NFL /NDL /NJH /NJS /NP >nul
robocopy "%SRC%\assets" "%DST%\assets" /MIR /XF *.glb /NFL /NDL /NJH /NJS /NP >nul
robocopy "%SRC%\data" "%DST%\data" /MIR /NFL /NDL /NJH /NJS /NP >nul
copy /Y "%SRC%\main.lua" "%DST%\main.lua" >nul
copy /Y "%SRC%\manifest.json" "%DST%\manifest.json" >nul
echo deployed
