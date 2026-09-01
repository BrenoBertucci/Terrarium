-- Headless draw-guard: same assertions as bagxy_headless.lua
local HERE = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or ".")
dofile(HERE .. "/bagxy_headless.lua")
