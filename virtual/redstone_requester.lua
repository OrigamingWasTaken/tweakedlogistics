local vlib = dofile("/tweakedlogistics/virtual/lib.lua")

local CONFIG_PATH = "/virtual_requester.config"
local BLOCK_TYPE = "virtual_redstone_requester"

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
    if not vlib.setupScreen("Redstone Requester") then return false end

    local cfg = vlib.getConfig()

    term.setTextColor(colors.white)
    print("")

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

    if not cfg.mode then
        cfg.mode = "allow_partial"
    end

    if not cfg.slots then
        cfg.slots = {}
        print("")
        printError("Configure request slots (up to 9). Leave blank to finish.")
        for i = 1, 9 do
            write("Slot " .. i .. " item: ")
            local item = read()
            if not item or item == "" then break end
            write("Slot " .. i .. " count: ")
            local count = tonumber(read())
            if not count then break end
            table.insert(cfg.slots, { name = item, count = count })
        end
    end

    if #cfg.slots == 0 then
        term.setTextColor(colors.red)
        print("No slots configured!")
        return false
    end

    vlib.saveConfig()

    local ok = vlib.register(BLOCK_TYPE, {
        destination = cfg.destination,
        mode = cfg.mode,
        slots = cfg.slots,
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

local function drawScreen(cfg, lastResult, waiting)
    term.clear()
    term.setCursorPos(1, 1)

    term.setTextColor(colors.cyan)
    print("=== Virtual Redstone Requester ===")
    print("")

    term.setTextColor(colors.white)
    print("Destination: " .. cfg.destination)
    print("Mode: " .. cfg.mode)
    print("")

    term.setTextColor(colors.yellow)
    print("Request slots:")
    for i, slot in ipairs(cfg.slots) do
        local name = slot.name:match(":(.+)") or slot.name
        term.setTextColor(colors.white)
        print("  " .. i .. ". " .. name .. " x" .. slot.count)
    end

    print("")
    if waiting then
        term.setTextColor(colors.yellow)
        print(">> Sending requests...")
    elseif lastResult then
        term.setTextColor(lastResult.allOk and colors.green or colors.red)
        print(">> " .. lastResult.message)
    else
        term.setTextColor(colors.lightGray)
        print("Waiting for redstone signal...")
    end

    local w, h = term.getSize()
    term.setCursorPos(1, h - 1)
    term.setTextColor(colors.lightGray)
    print("Redstone signal or Enter to trigger")
    term.setCursorPos(1, h)
    print("Ctrl+T to stop")
end

local function pullFromSources(destination, sources)
    local total = 0
    for _, source in ipairs(sources) do
        local ok, moved = pcall(
            peripheral.call, destination, "pullItems",
            source.inv, source.slot, source.count
        )
        if ok and moved then
            total = total + moved
        end
    end
    return total
end

local function doRequest(cfg)
    local allOk = true
    local messages = {}

    for _, slot in ipairs(cfg.slots) do
        vlib.send({
            type = "locate_items",
            item = slot.name,
            count = slot.count,
        })

        local reply = vlib.receive(5)
        if reply and reply.type == "item_sources" and #reply.sources > 0 then
            local pulled = pullFromSources(cfg.destination, reply.sources)
            local name = slot.name:match(":(.+)") or slot.name
            if pulled >= slot.count then
                table.insert(messages, name .. ": " .. pulled .. " OK")
            else
                table.insert(messages, name .. ": " .. pulled .. "/" .. slot.count)
                allOk = false
            end
        else
            local name = slot.name:match(":(.+)") or slot.name
            table.insert(messages, name .. ": not available")
            allOk = false
        end
    end

    return {
        allOk = allOk,
        message = allOk and "All delivered!" or table.concat(messages, ", "),
    }
end

local function mainLoop()
    local cfg = vlib.getConfig()
    local lastResult = nil

    drawScreen(cfg, nil, false)

    while true do
        local event, p1, p2, p3 = os.pullEvent()

        vlib.checkEvent(event, p1, p2)

        if event == "redstone" then
            local signaled = false
            for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
                if redstone.getInput(side) then
                    signaled = true
                    break
                end
            end
            if signaled then
                drawScreen(cfg, nil, true)
                lastResult = doRequest(cfg)
                drawScreen(cfg, lastResult, false)
            end

        elseif event == "key" and p1 == keys.enter then
            drawScreen(cfg, nil, true)
            lastResult = doRequest(cfg)
            drawScreen(cfg, lastResult, false)
        end
    end
end

if setup() then
    mainLoop()
end
