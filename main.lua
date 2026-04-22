local core = dofile("/tweakedlogistics/lib/core.lua")
local storage = dofile("/tweakedlogistics/lib/storage.lua")
local logistics = dofile("/tweakedlogistics/lib/logistics.lua")
local crafting = dofile("/tweakedlogistics/lib/crafting.lua")
local dashboard = dofile("/tweakedlogistics/lib/dashboard.lua")
local nicknames = dofile("/tweakedlogistics/lib/nicknames.lua")
local server = dofile("/tweakedlogistics/lib/server.lua")
local cli = dofile("/tweakedlogistics/lib/cli.lua")

local cfg = core.config("/tweakedlogistics.config")

storage.init(core, cfg)
logistics.init(core, storage, cfg)
crafting.init(core, storage, cfg)
logistics.setCrafting(crafting)
nicknames.init(cfg)
server.init(core, storage, logistics, crafting, nicknames, cfg)
dashboard.init(core, storage, logistics, crafting, cfg)
cli.init(core, storage, logistics, crafting, nicknames, server, dashboard, cfg)

local savedProcessors = cfg.get("crafting.processors")
if type(savedProcessors) == "table" then
    for _, proc in ipairs(savedProcessors) do
        storage.excludeInventory(proc.input)
        storage.excludeInventory(proc.output)
    end
end

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.cyan)
print("=== TweakedLogistics ===")
term.setTextColor(colors.white)
print("")
print("Running initial scan...")
storage.scan()
local status = storage.getStatus()
print("Found " .. status.uniqueTypes .. " item types in " .. status.inventories .. " inventories")

local modemFound = false
for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
    if peripheral.hasType(side, "modem") then
        modemFound = true
        break
    end
end
print("Server: " .. (modemFound and "enabled" or "no modem"))

local rules = logistics.getRules()
print("Rules: " .. #rules .. " active")
print("")
term.setTextColor(colors.lightGray)
print("Type 'help' for commands.")
print("")

parallel.waitForAll(
    storage.loop,
    logistics.loop,
    crafting.loop,
    dashboard.loop,
    server.loop,
    cli.run
)
