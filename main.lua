local core = dofile("/tweakedlogistics/lib/core.lua")
local storage = dofile("/tweakedlogistics/lib/storage.lua")
local logistics = dofile("/tweakedlogistics/lib/logistics.lua")
local crafting = dofile("/tweakedlogistics/lib/crafting.lua")
local dashboard = dofile("/tweakedlogistics/lib/dashboard.lua")

local cfg = core.config("/tweakedlogistics.config")

storage.init(core, cfg)
logistics.init(core, storage, cfg)
crafting.init(core, storage, cfg)
logistics.setCrafting(crafting)
dashboard.init(core, storage, logistics, crafting, cfg)

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
print("Starting modules...")

parallel.waitForAll(
    storage.loop,
    logistics.loop,
    crafting.loop,
    dashboard.loop
)
