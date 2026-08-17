-- Voxel world mode: draw distance control for performance.
--
-- Controls how many adjacent maps (neighbors) are rendered, which significantly
-- affects performance on low-end PCs and mobile devices by reducing the amount
-- of world geometry that needs to be processed and displayed.
--
--   NEAR:  0 neighbors (current map only, best performance)
--   MILD:  2 neighbors (balanced quality/performance)
--   FAR:   4 neighbors (maximum view distance, best quality)

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local DrawDistance = {}

DrawDistance.KEY = "drawDistance"
DrawDistance.LABEL = "DRAW DIST"

-- Neighbor limits: how many adjacent maps to render based on distance setting
DrawDistance.NEIGHBOR_LIMITS = { 0, 2, 4 }  -- Near: 0 neighbors, Mild: 2 neighbors, Far: 4 neighbors

DrawDistance.setting = ModSetting.new(DrawDistance.KEY, DrawDistance.LABEL,
                                       { 0, 1, 2 },
                                       { "NEAR", "MILD", "FAR" })

function DrawDistance.level()
  return DrawDistance.setting:get() or 2  -- Default to FAR (index 2)
end

-- Get the neighbor limit for the current setting (how many adjacent maps to render)
function DrawDistance.neighborLimit()
  return DrawDistance.NEIGHBOR_LIMITS[DrawDistance.level() + 1] or 4
end

function DrawDistance.row()
  return DrawDistance.setting:row()
end

function DrawDistance.sync(value)
  DrawDistance.setting:sync(value)
end

return DrawDistance
