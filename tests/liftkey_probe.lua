-- The LIFT KEY: the loaded save carries it, and lib/StoryFixes.lua drops the
-- ball for a save where the grunt was beaten on sight. Nothing is saved.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/liftkey_probe.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  local function check(ok, m) log((ok and "PASS " or "FAIL ") .. m) end
  for _ = 1, 1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  local function settle(n)
    for _ = 1, n do
      for _, d in ipairs({ "up", "down", "left", "right" }) do game.input.state[d] = false end
      game.input.pressQueue = {}
      coroutine.yield()
    end
  end
  local save = game.save
  log("map " .. tostring(game.overworld.map.def.id))
  check((save.inventory.LIFT_KEY or 0) == 1, "the save carries the LIFT KEY: " .. tostring(save.inventory.LIFT_KEY))
  check(game.data.items and game.data.items.LIFT_KEY ~= nil, "and the engine knows the item")
  check(save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY == true, "the event is marked done")
  local toggles = save.objectToggles.ROCKET_HIDEOUT_B4F or {}
  check(toggles.ROCKETHIDEOUTB4F_LIFT_KEY ~= true, "no second key lies on the floor")
  -- now the stuck state, in memory only: beaten on sight, never dropped
  save.inventory.LIFT_KEY = nil
  save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY = nil
  save.itemsTaken.ROCKET_HIDEOUT_B4F_obj_9 = nil
  game.overworld:setMap("ROCKET_HIDEOUT_B4F", 12, 4, "up")
  settle(120)
  check(save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY == true, "stuck save: the fix set the event")
  local t = save.objectToggles.ROCKET_HIDEOUT_B4F or {}
  check(t.ROCKETHIDEOUTB4F_LIFT_KEY == true, "and showed the ball: " .. tostring(t.ROCKETHIDEOUTB4F_LIFT_KEY))
  local seen = false
  for _, n in ipairs(game.overworld.npcs or {}) do
    if n.cellX == 10 and n.cellY == 2 and not n.hidden then seen = true end
  end
  log("ball standing at (10,2): " .. tostring(seen))
  file:close()
  love.event.quit()
end
