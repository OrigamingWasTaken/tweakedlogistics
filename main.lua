local core = dofile("/tweakedlogistics/lib/core.lua")
local storage = dofile("/tweakedlogistics/lib/storage.lua")
local logistics = dofile("/tweakedlogistics/lib/logistics.lua")
local crafting = dofile("/tweakedlogistics/lib/crafting.lua")
local dashboard = dofile("/tweakedlogistics/lib/dashboard.lua")
local nicknames = dofile("/tweakedlogistics/lib/nicknames.lua")
local server = dofile("/tweakedlogistics/lib/server.lua")
local cli = dofile("/tweakedlogistics/lib/cli.lua")
local cards = dofile("/tweakedlogistics/lib/cards.lua")

local cfg = core.config("/tweakedlogistics.config")

storage.init(core, cfg)
logistics.init(core, storage, cfg)
crafting.init(core, storage, cfg)
logistics.setCrafting(crafting)
nicknames.init(cfg)
cards.init(cfg)
server.init(core, storage, logistics, crafting, nicknames, cards, cfg)
dashboard.init(core, storage, logistics, crafting, server, cfg)
cli.init(core, storage, logistics, crafting, nicknames, server, dashboard, cfg)

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

local modemFound = core.findModem() ~= nil
print("Server: " .. (modemFound and "enabled" or "no modem"))
print("")
term.setTextColor(colors.lightGray)
print("Type 'help' for commands.")
print("")

parallel.waitForAll(
    storage.loop,
    crafting.loop,
    dashboard.loop,
    server.loop,
    cli.run
)
