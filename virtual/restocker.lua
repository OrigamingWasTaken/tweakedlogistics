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

local function pickInventory()
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
            return invs[num].name
        elseif input and input ~= "" then
            return resolveInventory(input)
        end
    else
        write("Destination inventory name: ")
        local input = read()
        if input and input ~= "" then
            return resolveInventory(input)
        end
    end
    return nil
end

local function setup()
    vlib.loadConfig(CONFIG_PATH)
    if not vlib.setupScreen("Restocker") then return false end

    local cfg = vlib.getConfig()

    term.setTextColor(colors.white)
    print("")

    if not cfg.destination then
        cfg.destination = pickInventory()
        if not cfg.destination then return false end
    end

    if not cfg.slots then
        cfg.slots = {}
        print("")
        write("Item to restock: ")
        local item = read()
        if not item or item == "" then return false end
        write("Target count: ")
        local count = tonumber(read())
        if not count then return false end
        table.insert(cfg.slots, { item = item, target = count })
        print("")
        term.setTextColor(colors.lightGray)
        print("Edit " .. CONFIG_PATH .. " to add more items.")
        term.setTextColor(colors.white)
    end

    if #cfg.slots == 0 then
        term.setTextColor(colors.red)
        print("No items configured!")
        return false
    end

    if not cfg.interval then
        cfg.interval = 10
    end

    vlib.saveConfig()

    local items = {}
    for _, slot in ipairs(cfg.slots) do
        table.insert(items, slot.item)
    end
    local ok = vlib.register(BLOCK_TYPE, {
        items = items,
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

local function matchesItem(slotName, itemName)
    if slotName == itemName then return true end
    if not itemName:find(":") then
        if slotName == "minecraft:" .. itemName then return true end
        if slotName:match(":(.+)") == itemName then return true end
    end
    return false
end

local function countItemInInventory(invName, itemName)
    local total = 0
    local ok, contents = pcall(peripheral.call, invName, "list")
    if ok and contents then
        for _, slot in pairs(contents) do
            if matchesItem(slot.name, itemName) then
                total = total + slot.count
            end
        end
    end
    return total
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

local function drawBar(mon_y, w, current, target)
    local barW = w - 4
    local filled = target > 0 and math.floor((current / target) * barW + 0.5) or 0
    if filled > barW then filled = barW end

    local pct = target > 0 and math.floor(current / target * 100) or 0
    local barColor
    if pct >= 100 then barColor = colors.green
    elseif pct >= 50 then barColor = colors.yellow
    else barColor = colors.red end

    term.setCursorPos(3, mon_y)
    term.setBackgroundColor(barColor)
    term.write(string.rep(" ", filled))
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", barW - filled))
    term.setBackgroundColor(colors.black)
end

local function drawStatus(cfg, slotData, overallStatus)
    term.clear()
    term.setCursorPos(1, 1)
    local w, h = term.getSize()

    term.setTextColor(colors.cyan)
    print("=== Virtual Restocker ===")

    local destName = (cfg.destination:match(":(.+)") or cfg.destination)
    term.setTextColor(colors.lightGray)
    print("Dest: " .. destName)
    print("")

    local row = 4
    for i, sd in ipairs(slotData) do
        if row + 2 > h - 3 then break end
        local itemName = (sd.item:match(":(.+)") or sd.item):gsub("_", " ")
        local pct = sd.target > 0 and math.floor(sd.current / sd.target * 100) or 0

        term.setCursorPos(1, row)
        if sd.current >= sd.target then
            term.setTextColor(colors.green)
        elseif sd.current > 0 then
            term.setTextColor(colors.yellow)
        else
            term.setTextColor(colors.red)
        end
        term.write(" " .. itemName .. " ")
        term.setTextColor(colors.white)
        term.write(sd.current .. "/" .. sd.target .. " " .. pct .. "%")
        row = row + 1

        drawBar(row, w, sd.current, sd.target)
        row = row + 1
    end

    row = row + 1
    if row <= h - 2 then
        term.setCursorPos(1, row)
        term.setTextColor(colors.white)
        write("Status:  ")
        if overallStatus == "ok" then
            term.setTextColor(colors.green)
            print("All stocked")
        elseif overallStatus == "requesting" then
            term.setTextColor(colors.yellow)
            print("Requesting...")
        elseif overallStatus == "short" then
            term.setTextColor(colors.red)
            print("Storage short")
        end

        term.setCursorPos(1, row + 1)
        term.setTextColor(colors.white)
        write("Server:  ")
        if vlib.isConnected() then
            term.setTextColor(colors.green)
            print("Connected")
        else
            term.setTextColor(colors.red)
            print("DISCONNECTED")
        end
    end

    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, h)
    term.write("Every " .. cfg.interval .. "s | Ctrl+T to stop")
end

local function mainLoop()
    local cfg = vlib.getConfig()

    while true do
        local slotData = {}
        local overallStatus = "ok"
        local statusItems = {}

        for _, slot in ipairs(cfg.slots) do
            local current = countItemInInventory(cfg.destination, slot.item)
            local sd = { item = slot.item, target = slot.target, current = current }
            table.insert(slotData, sd)

            if current < slot.target then
                local deficit = slot.target - current
                drawStatus(cfg, slotData, "requesting")

                vlib.send({
                    type = "locate_items",
                    item = slot.item,
                    count = deficit,
                })

                local reply = vlib.receiveType("item_sources", 5)
                if reply and #reply.sources > 0 then
                    local pulled = pullFromSources(cfg.destination, reply.sources)
                    sd.current = countItemInInventory(cfg.destination, slot.item)
                    if sd.current < sd.target then
                        overallStatus = "short"
                    end
                else
                    overallStatus = "short"
                end
            end

            table.insert(statusItems, { item = sd.item, current = sd.current, target = sd.target })
        end

        if overallStatus == "ok" then
            vlib.playSound("success")
        end

        drawStatus(cfg, slotData, overallStatus)
        vlib.setStatus({ slots = statusItems })
        vlib.heartbeat()
        drawStatus(cfg, slotData, overallStatus)

        local waitTimer = os.startTimer(cfg.interval or 10)
        local alarmTimer = os.startTimer(2)
        while true do
            local event, p1, p2 = os.pullEvent()
            if event == "timer" and p1 == waitTimer then
                break
            elseif event == "timer" and p1 == alarmTimer then
                vlib.playAlarm()
                alarmTimer = os.startTimer(2)
            end
            vlib.checkEvent(event, p1, p2)
        end
    end
end

if setup() then
    mainLoop()
end
