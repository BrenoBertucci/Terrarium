-- Check: ModSetting:translate -- a row's words follow the LANGUAGE row,
-- its stored values never do. Plain Lua 5.1, no game: run from the repo
-- root (`luajit tests/modsetting_translate_check.lua`).
local stored = { language = "pt", daytime = "dusk" }
local modules = {}
local V = { mod = { id = "TERRARIUM", options = {
  get = function(_, key) return stored[key] end } } }
function V.require(name)
  if modules[name] == nil then
    modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  end
  return modules[name]
end

local ModSetting = V.require("ModSetting")
local function fresh()
  return ModSetting.new("daytime", "DAYTIME", { "sync", "day", "dusk" },
                        { "SYNC", "DAY", "DUSK" })
    :translate("HORARIO", { "SINCRONO", "DIA", "CREPUSCULO" })
end

local s = fresh()
local row = s:row()
assert(row.label == "HORARIO", row.label)
assert(row.value() == "CREPUSCULO", row.value())
assert(s:get() == "dusk", "the stored value is untouched")
local schema = s:schema("help")
assert(schema.label == "HORARIO" and schema.choices[3][1] == "CREPUSCULO"
       and schema.choices[3][2] == "dusk")

stored.language = "en"
V.require("Lang").setting.index = nil      -- re-read, as a switch would
row = fresh():row()
assert(row.label == "DAYTIME", row.label)
assert(row.value() == "DUSK", row.value())

-- a row with no Portuguese face stays English under PORTUGUES
stored.language = "pt"
V.require("Lang").setting.index = nil
local plain = ModSetting.new("k", "PLAIN", { "a" }, { "A" })
assert(plain:row().label == "PLAIN" and plain:row().value() == "A")

print("modsetting_translate_check: ok")
