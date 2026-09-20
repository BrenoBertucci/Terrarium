-- Story events the engine can leave stuck, put right where they stand.
--
-- ------- the LIFT KEY (Rocket Hideout B4F, Yellow)
--
-- In Yellow the grunt drops the LIFT KEY the instant his battle ends, and
-- the engine (0.2.57, data/scripts/story3.lua) does that in the callback of
-- his TALK handler. But he is a trainer with a line of sight: walk into it
-- and the battle starts from the sighting, the talk handler never runs, the
-- win is recorded -- and every talk after that only reprints "I dropped the
-- LIFT KEY!" because he is already beaten. No ball, no elevator, no Silph
-- Scope, no way on. (Red and Blue drop it on the first talk AFTER the win,
-- so they are not caught by this.)
--
-- The repair is the event's own two lines, run whenever the player stands
-- on that floor with the grunt beaten and the key never dropped: set
-- EVENT_ROCKET_DROPPED_LIFT_KEY and show the ball. A save that is already
-- past it is untouched, and so is one where the talk path did its job.

-- the mod namespace (see main.lua)
local V = ...

local StoryFixes = {}

local MAP, BALL = "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_LIFT_KEY"
local GRUNT = "ROCKET_HIDEOUT_B4F_obj_4"
local FLAG = "EVENT_ROCKET_DROPPED_LIFT_KEY"

local failed = false

local function liftKey(Game, ow)
  local save = Game.save
  local def = ow.map and ow.map.def
  if not (save and def and (def.id or def.name) == MAP) then return end
  if save.version ~= "yellow" then return end
  local flags, beaten = save.flags, save.defeatedTrainers
  if not (flags and beaten and beaten[GRUNT]) or flags[FLAG] then return end
  flags[FLAG] = true
  -- somebody who already carries the key needs no ball on the floor
  if (save.inventory and save.inventory.LIFT_KEY or 0) > 0 then return end
  require("src.script.Commands").show_object(
    { game = Game, save = save, overworld = ow }, MAP, BALL)
  if V.mod and V.mod.log then
    V.mod.log:info("StoryFixes: the LIFT KEY never dropped -- dropped it")
  end
end

function StoryFixes.update()
  if failed then return end
  local ok, err = pcall(function()
    local Game = require("src.core.Game")
    local ow = Game and Game.overworld
    if ow and Game.stack and Game.stack:top() == ow then liftKey(Game, ow) end
  end)
  if not ok then
    failed = true
    if V.mod and V.mod.log then
      V.mod.log:warn("StoryFixes failed: %s -- off for this session", tostring(err))
    end
  end
end

return StoryFixes
