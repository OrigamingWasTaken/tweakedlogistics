local vlib = dofile("/tweakedlogistics/virtual/lib.lua")

local CONFIG_PATH = "/virtual_restocker.config"
local BLOCK_TYPE = "virtual_restocker"

local function resolveInventory(sideOrName)
    if peripheral.hasType(sideOrName, "inventory") then
        local wrapped = peripheral.wrap(sideOrName)
        if wrapped then
            local name = peripheral.getName(wrapped)
            if name then return name end
        end
    end
    return sideOrName
end

local function listLocalInventories()
    local found = {}
    local sides = {"left", "right", "top", "bottom", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.hasType(side, "inventory") then
            local wrapped = peripheral.wrap(side)
            local name = peripheral.getName(wrapped)
            table.insert(found, { side = side, name = name })
        end
    end
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "inventory") then
            local already = false
            for _, f in ipairs(found) do
                if f.name == name then already = true break end
            end
            if not already then
                table.insert(found, { side = nil, name = name })
            end
        end
    end
    return found
end

local function setup()
    vlib.loadConfig(CONFIG_PATH)
    if not vlib.setupScreen("Restocker") then return false end

    local cfg = vlib.getConfig()

    term.setTextColor(colors.white)
    print("")

    if not cfg.item then
        write("Item to restock (e.g. minecraft:iron_ingot): ")
        cfg.item = read()
        if not cfg.item or cfg.item == "" then return false end
    end

    if not cfg.target then
        write("Target count: ")
        local num = tonumber(read())
        if not num then return false end
        cfg.target = num
    end

    if not cfg.destination then
        local invs = listLocalInventories()
        if #invs > 0 then
            print("")
            term.setTextColor(colors.yellow)
            print("Available inventories:")
            term.setTextColor(colors.white)
            for i, inv in ipairs(invs) do
                local label = inv.name
                if inv.side then
                    label = label .. " (" .. inv.side .. ")"
                end
                print("  " .. i .. ". " .. label)
            end
            print("")
            write("Pick inventory (number or name): ")
            local input = read()
            local num = tonumber(input)
            if num and invs[num] then
                cfg.destination = invs[num].name
            elseif input and input ~= "" then
                cfg.destination = resolveInventory(input)
            else
                return false
            end
        else
            write("Destination inventory name: ")
            cfg.destination = read()
            if not cfg.destination or cfg.destination == "" then return false end
            cfg.destination = resolveInventory(cfg.destination)
        end
    end

    if not cfg.interval then
        cfg.interval = 10
    end

    vlib.saveConfig()

    local ok = vlib.register(BLOCK_TYPE, {
        item = cfg.item,
        target = cfg.target,
        destination = cfg.destination,
    })

    if ok then
        term.setTextColor(colors.green)
        print("Registered with server!")
    else
        term.setTextColor(colors.yellow)
        print("Server did not acknowledge, continuing anyway...")
    end

    sleep(1)
    return true
end

local function countItemInInventory(invName, itemName)
    local total = 0
    local ok, contents = pcall(peripheral.call, invName, "list")
    if ok and contents then
        for _, slot in pairs(contents) do
            if slot.name == itemName then
                total = total + slot.count
            end
        end
    end
    return total
end

local function drawStatus(cfg, current, status)
    term.clear()
    term.setCursorPos(1, 1)

    term.setTextColor(colors.cyan)
    print("=== Virtual Restocker ===")
    print("")

    term.setTextColor(colors.white)
    print("Item:        " .. (cfg.item:match(":(.+)") or cfg.item))
    print("Target:      " .. cfg.target)
    print("Destination: " .. cfg.destination)
    print("")

    local pct = cfg.target > 0 and math.floor(current / cfg.target * 100) or 0

    term.setTextColor(colors.white)
    write("Current:     ")

    if current >= cfg.target then
        term.setTextColor(colors.green)
    elseif current > 0 then
        term.setTextColor(colors.yellow)
    else
        term.setTextColor(colors.red)
    end
    print(current .. " / " .. cfg.target .. " (" .. pct .. "%)")

    print("")
    term.setTextColor(colors.white)
    write("Status:      ")
    if status == "ok" then
        term.setTextColor(colors.green)
        print("Stocked")
    elseif status == "requesting" then
        term.setTextColor(colors.yellow)
        print("Requesting...")
    elseif status == "short" then
        term.setTextColor(colors.red)
        print("Storage short")
    else
        term.setTextColor(colors.lightGray)
        print("Checking...")
    end

    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, 12)
    print("Checking every " .. cfg.interval .. "s")
    print("Ctrl+T to stop")
end

local function mainLoop()
    local cfg = vlib.getConfig()

    while true do
        local current = countItemInInventory(cfg.destination, cfg.item)
        local status = "ok"

        if current < cfg.target then
            status = "requesting"
            drawStatus(cfg, current, status)

            local deficit = cfg.target - current
            vlib.send({
                type = "request_items",
                item = cfg.item,
                count = deficit,
                destination = cfg.destination,
            })

            local reply = vlib.receive(5)
            if reply and reply.type == "items_delivered" then
                if reply.delivered >= deficit then
                    status = "ok"
                else
                    status = "short"
                end
            else
                status = "short"
            end

            current = countItemInInventory(cfg.destination, cfg.item)
        end

        drawStatus(cfg, current, status)
        sleep(cfg.interval or 10)
    end
end

if setup() then
    mainLoop()
end
