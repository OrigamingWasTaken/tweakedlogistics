local cli = {}

local _core = nil
local _storage = nil
local _logistics = nil
local _crafting = nil
local _nicknames = nil
local _server = nil
local _config = nil

function cli.init(core, storage, logistics, crafting, nicknames, server, config)
    _core = core
    _storage = storage
    _logistics = logistics
    _crafting = crafting
    _nicknames = nicknames
    _server = server
    _config = config
end

local function printColor(text, color)
    term.setTextColor(color)
    print(text)
    term.setTextColor(colors.white)
end

local function printHelp()
    term.setTextColor(colors.yellow)
    write("Storage:    ")
    term.setTextColor(colors.white)
    print("stock, status, scan")
    term.setTextColor(colors.yellow)
    write("Logistics:  ")
    term.setTextColor(colors.white)
    print("rules, add-rule, remove-rule <id>")
    term.setTextColor(colors.yellow)
    write("Crafting:   ")
    term.setTextColor(colors.white)
    print("processors, add-processor, remove-processor <id>, jobs")
    term.setTextColor(colors.yellow)
    write("Network:    ")
    term.setTextColor(colors.white)
    print("inventories, nickname <inv> <name>, nicknames, clients")
    term.setTextColor(colors.yellow)
    write("System:     ")
    term.setTextColor(colors.white)
    print("update, help, exit")
end

local EPIC_ITEMS = {
    ["minecraft:mace"] = true,
    ["minecraft:dragon_egg"] = true,
    ["minecraft:end_crystal"] = true,
}

local RARE_ITEMS = {
    ["minecraft:nether_star"] = true,
    ["minecraft:elytra"] = true,
    ["minecraft:trident"] = true,
    ["minecraft:totem_of_undying"] = true,
    ["minecraft:enchanted_golden_apple"] = true,
}

local UNCOMMON_ITEMS = {
    ["minecraft:golden_apple"] = true,
    ["minecraft:experience_bottle"] = true,
    ["minecraft:dragon_breath"] = true,
}

local function getItemColor(item)
    if EPIC_ITEMS[item.name] then return colors.purple end
    if RARE_ITEMS[item.name] then return colors.cyan end
    if item.enchantments and #item.enchantments > 0 then return colors.cyan end
    if UNCOMMON_ITEMS[item.name] then return colors.yellow end
    if item.customName then return colors.lightGray end
    return colors.white
end

local function cmdStock()
    local items = _storage.getItems()
    if #items == 0 then
        print("No items in storage.")
        return
    end
    printColor(string.format("%-30s %s", "Item", "Count"), colors.yellow)
    for _, item in ipairs(items) do
        local nameColor = getItemColor(item)
        local name = item.displayName
        local suffix = ""
        if item.customName and item.baseName then
            local realName = item.baseName:match(":(.+)") or item.baseName
            suffix = " (" .. realName:gsub("_", " ") .. ")"
        end

        local display = name:sub(1, 30 - #suffix) .. suffix
        term.setTextColor(nameColor)
        write(string.format("%-30s ", display:sub(1, 30)))
        term.setTextColor(colors.white)
        print(tostring(item.count))
    end
    print("")
    print(#items .. " item types")
end

local function cmdStatus()
    local s = _storage.getStatus()
    printColor("System Status", colors.cyan)
    print("  Inventories: " .. s.inventories)
    print("  Total slots: " .. s.totalSlots)
    print("  Used slots:  " .. s.usedSlots)
    print("  Item types:  " .. s.uniqueTypes)
    print("  Last scan:   " .. s.lastScanMs .. "ms")
    if _server then
        local clients = _server.getClients()
        print("  Clients:     " .. #clients)
    end
end

local function cmdRules()
    local rules = _logistics.getRules()
    if #rules == 0 then
        print("No rules defined.")
        return
    end
    printColor(string.format("%-4s %-20s %-8s %-8s %s", "ID", "Item", "Target", "Current", "Status"), colors.yellow)
    for _, rule in ipairs(rules) do
        local name = rule.item:match(":(.+)") or rule.item
        local statusColor = colors.white
        if rule.status == "fulfilled" then statusColor = colors.green
        elseif rule.status == "short" then statusColor = colors.red end
        term.setTextColor(colors.white)
        write(string.format("%-4s %-20s %-8s %-8s ", rule.id, name:sub(1, 20), tostring(rule.target), tostring(rule.current)))
        printColor(rule.status, statusColor)
    end
end

local function cmdAddRule()
    printColor("Add Stock Rule", colors.cyan)
    write("Item name (e.g. minecraft:iron_ingot): ")
    local item = read()
    if not item or item == "" then return end

    write("Target count: ")
    local target = tonumber(read())
    if not target then print("Invalid number.") return end

    write("Destination inventory: ")
    local dest = read()
    if not dest or dest == "" then return end

    write("Priority (0-10, default 0): ")
    local prio = tonumber(read()) or 0

    local id = _logistics.addRule({
        item = item,
        target = target,
        destination = dest,
        priority = prio,
    })
    printColor("Rule added: #" .. id, colors.green)
end

local function cmdRemoveRule(id)
    if not id then
        write("Rule ID: ")
        id = read()
    end
    if not id or id == "" then return end
    _logistics.removeRule(id)
    printColor("Rule removed: #" .. id, colors.green)
end

local function cmdProcessors()
    local procs = _crafting.getProcessors()
    if #procs == 0 then
        print("No processors defined.")
        return
    end
    printColor(string.format("%-4s %-15s %-25s %s", "ID", "Type", "Input", "Status"), colors.yellow)
    for _, proc in ipairs(procs) do
        local inputName = _nicknames and _nicknames.getDisplay(proc.input) or proc.input
        local statusStr = proc.busy and "BUSY" or "IDLE"
        local statusColor = proc.busy and colors.orange or colors.green
        term.setTextColor(colors.white)
        write(string.format("%-4s %-15s %-25s ", proc.id, (proc.type or "?"):sub(1, 15), inputName:sub(1, 25)))
        printColor(statusStr, statusColor)
    end
end

local function cmdAddProcessor()
    printColor("Add Processor", colors.cyan)
    write("Type label (e.g. smelter, press): ")
    local procType = read()
    if not procType or procType == "" then return end

    write("Input inventory: ")
    local input = read()
    if not input or input == "" then return end

    write("Output inventory: ")
    local output = read()
    if not output or output == "" then return end

    local id = _crafting.addProcessor({
        type = procType,
        input = input,
        output = output,
    })
    printColor("Processor added: #" .. id, colors.green)
end

local function cmdRemoveProcessor(id)
    if not id then
        write("Processor ID: ")
        id = read()
    end
    if not id or id == "" then return end
    _crafting.removeProcessor(id)
    printColor("Processor removed: #" .. id, colors.green)
end

local function cmdJobs()
    local jobs = _crafting.getJobs()
    if #jobs == 0 then
        print("No active jobs.")
        return
    end
    printColor(string.format("%-4s %-25s %-8s %s", "ID", "Item", "Count", "Status"), colors.yellow)
    for _, job in ipairs(jobs) do
        local name = job.item:match(":(.+)") or job.item
        print(string.format("%-4s %-25s %-8d %s", job.id, name:sub(1, 25), job.count, job.status))
    end
end

local function cmdInventories()
    local invs = _core.findInventories("inventory")
    printColor(#invs .. " inventories on network:", colors.cyan)
    for _, name in ipairs(invs) do
        local nick = _nicknames and _nicknames.get(name)
        if nick then
            print("  " .. name .. " (" .. nick .. ")")
        else
            print("  " .. name)
        end
    end
end

local function cmdNickname(args)
    local invName = args[1]
    local label = args[2]
    if not invName then
        write("Inventory name: ")
        invName = read()
    end
    if not label then
        write("Nickname: ")
        label = read()
    end
    if not invName or invName == "" or not label or label == "" then return end
    _nicknames.set(invName, label)
    printColor("Nickname set: " .. invName .. " -> " .. label, colors.green)
end

local function cmdNicknames()
    local all = _nicknames.getAll()
    local count = 0
    for name, label in pairs(all) do
        print("  " .. name .. " -> " .. label)
        count = count + 1
    end
    if count == 0 then
        print("No nicknames set.")
    end
end

local function cmdClients()
    if not _server then
        print("Server not running.")
        return
    end
    local clients = _server.getClients()
    if #clients == 0 then
        print("No connected clients.")
        return
    end
    printColor(string.format("%-6s %-20s", "ID", "Type"), colors.yellow)
    for _, client in ipairs(clients) do
        print(string.format("%-6d %-20s", client.id, client.blockType or "unknown"))
    end
end

local function cmdScan()
    print("Scanning...")
    _storage.scan()
    local s = _storage.getStatus()
    printColor("Found " .. s.uniqueTypes .. " item types in " .. s.inventories .. " inventories (" .. s.lastScanMs .. "ms)", colors.green)
end

local function cmdUpdate()
    local currentHash = nil
    if fs.exists("/tweakedlogistics/.version") then
        local h = fs.open("/tweakedlogistics/.version", "r")
        if h then
            currentHash = h.readAll()
            h.close()
        end
    end

    print("Checking for updates...")
    local resp = http.get("https://api.github.com/repos/OrigamingWasTaken/tweakedlogistics/commits/main")
    if not resp then
        printColor("Failed to check for updates.", colors.red)
        return
    end

    local body = resp.readAll()
    resp.close()
    local data = textutils.unserializeJSON(body)
    if not data or not data.sha then
        printColor("Failed to parse update info.", colors.red)
        return
    end

    local latestHash = data.sha

    if currentHash and currentHash == latestHash then
        printColor("Already up to date.", colors.green)
        return
    end

    if currentHash then
        print("Current: " .. currentHash:sub(1, 7))
    else
        print("Current: unknown")
    end
    print("Latest:  " .. latestHash:sub(1, 7))

    if data.commit and data.commit.message then
        local msg = data.commit.message:match("^[^\n]+") or data.commit.message
        term.setTextColor(colors.lightGray)
        print("         " .. msg)
        term.setTextColor(colors.white)
    end

    print("")
    term.setTextColor(colors.yellow)
    write("Install update? (y/n): ")
    term.setTextColor(colors.white)
    local answer = read()
    if answer ~= "y" and answer ~= "Y" then
        print("Cancelled.")
        return
    end

    print("")
    print("Downloading installer...")
    local dlResp = http.get("https://raw.githubusercontent.com/OrigamingWasTaken/tweakedlogistics/main/install.lua")
    if not dlResp then
        printColor("Failed to download installer.", colors.red)
        return
    end
    local code = dlResp.readAll()
    dlResp.close()
    local fn, err = loadstring(code, "install.lua")
    if not fn then
        printColor("Failed to load installer: " .. tostring(err), colors.red)
        return
    end
    fn()
end

local function parseCommand(line)
    local parts = {}
    for word in line:gmatch("%S+") do
        table.insert(parts, word)
    end
    local cmd = parts[1]
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end
    return cmd, args
end

local function dispatchCommand(cmd, args)
    if cmd == "help" then printHelp()
    elseif cmd == "stock" then cmdStock()
    elseif cmd == "status" then cmdStatus()
    elseif cmd == "rules" then cmdRules()
    elseif cmd == "add-rule" then cmdAddRule()
    elseif cmd == "remove-rule" then cmdRemoveRule(args[1])
    elseif cmd == "processors" then cmdProcessors()
    elseif cmd == "add-processor" then cmdAddProcessor()
    elseif cmd == "remove-processor" then cmdRemoveProcessor(args[1])
    elseif cmd == "jobs" then cmdJobs()
    elseif cmd == "inventories" then cmdInventories()
    elseif cmd == "nickname" then cmdNickname(args)
    elseif cmd == "nicknames" then cmdNicknames()
    elseif cmd == "clients" then cmdClients()
    elseif cmd == "scan" then cmdScan()
    elseif cmd == "update" then cmdUpdate()
    elseif cmd == "exit" then return false
    else
        printColor("Unknown command: " .. cmd, colors.red)
        print("Type 'help' for commands.")
    end
    return true
end

function cli.run()
    local screenW, screenH = term.getSize()
    local lines = {}
    local lineColors = {}
    local scrollOffset = 0

    local function addLine(text, fg)
        table.insert(lines, text or "")
        table.insert(lineColors, fg or colors.white)
        if #lines > 500 then
            table.remove(lines, 1)
            table.remove(lineColors, 1)
        end
    end

    local function cliPrint(text, fg)
        text = tostring(text or "")
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            addLine(line, fg or colors.white)
        end
    end

    local function redraw()
        local viewH = screenH - 1
        local maxScroll = math.max(0, #lines - viewH)
        if scrollOffset > maxScroll then scrollOffset = maxScroll end
        if scrollOffset < 0 then scrollOffset = 0 end

        local startLine = #lines - viewH - scrollOffset + 1
        for y = 1, viewH do
            local idx = startLine + y - 1
            term.setCursorPos(1, y)
            term.setBackgroundColor(colors.black)
            if idx >= 1 and idx <= #lines then
                term.setTextColor(lineColors[idx] or colors.white)
                local l = lines[idx]
                if #l > screenW then l = l:sub(1, screenW) end
                term.write(l .. string.rep(" ", screenW - #l))
            else
                term.write(string.rep(" ", screenW))
            end
        end

        term.setCursorPos(1, screenH)
        term.setBackgroundColor(colors.black)
        if scrollOffset > 0 then
            term.setTextColor(colors.lightGray)
            local info = "[+" .. scrollOffset .. " lines] "
            term.write(info)
            term.setTextColor(colors.cyan)
            term.write("tl> ")
            term.setTextColor(colors.white)
        else
            term.setTextColor(colors.cyan)
            term.write("tl> ")
            term.setTextColor(colors.white)
            term.write(string.rep(" ", screenW - 4))
            term.setCursorPos(5, screenH)
        end
    end

    local origPrint = print
    local origWrite = write
    local origPrintError = printError

    local currentFg = colors.white
    local oldSetTextColor = term.setTextColor

    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            table.insert(parts, tostring(select(i, ...)))
        end
        local text = table.concat(parts, "\t")
        cliPrint(text, currentFg)
        scrollOffset = 0
        redraw()
    end

    write = function(text)
        text = tostring(text or "")
        if #lines == 0 then addLine("", colors.white) end
        lines[#lines] = lines[#lines] .. text
        lineColors[#lines] = currentFg
        redraw()
    end

    printError = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            table.insert(parts, tostring(select(i, ...)))
        end
        cliPrint(table.concat(parts, "\t"), colors.red)
        scrollOffset = 0
        redraw()
    end

    term.setTextColor = function(c)
        currentFg = c
        oldSetTextColor(c)
    end

    cliPrint("=== TweakedLogistics ===", colors.cyan)
    cliPrint("Type 'help' for commands.", colors.lightGray)
    cliPrint("", colors.white)
    redraw()

    local running = true
    while running do
        redraw()
        term.setCursorPos(5 + (scrollOffset > 0 and #("[+" .. scrollOffset .. " lines] ") or 0), screenH)
        term.setTextColor(colors.white)
        term.setCursorBlink(true)

        local inputBuf = ""
        local inputting = true
        while inputting do
            local event, p1, p2, p3 = os.pullEvent()

            if event == "char" then
                inputBuf = inputBuf .. p1
                scrollOffset = 0
                redraw()
                term.setCursorPos(5, screenH)
                term.setTextColor(colors.white)
                term.write(inputBuf)

            elseif event == "key" then
                if p1 == keys.enter then
                    inputting = false
                elseif p1 == keys.backspace then
                    if #inputBuf > 0 then
                        inputBuf = inputBuf:sub(1, #inputBuf - 1)
                        scrollOffset = 0
                        redraw()
                        term.setCursorPos(5, screenH)
                        term.setTextColor(colors.white)
                        term.write(inputBuf)
                    end
                elseif p1 == keys.pageUp then
                    scrollOffset = scrollOffset + (screenH - 2)
                    redraw()
                    term.setCursorPos(5, screenH)
                    term.setTextColor(colors.white)
                    term.write(inputBuf)
                elseif p1 == keys.pageDown then
                    scrollOffset = math.max(0, scrollOffset - (screenH - 2))
                    redraw()
                    term.setCursorPos(5, screenH)
                    term.setTextColor(colors.white)
                    term.write(inputBuf)
                end

            elseif event == "mouse_scroll" then
                if p1 == -1 then
                    scrollOffset = scrollOffset + 3
                elseif p1 == 1 then
                    scrollOffset = math.max(0, scrollOffset - 3)
                end
                redraw()
                term.setCursorPos(5, screenH)
                term.setTextColor(colors.white)
                term.write(inputBuf)
            end
        end

        term.setCursorBlink(false)

        cliPrint("tl> " .. inputBuf, colors.cyan)
        scrollOffset = 0

        if inputBuf ~= "" then
            local cmd, args = parseCommand(inputBuf)
            local cont = dispatchCommand(cmd, args)
            if cont == false then
                running = false
            end
        end
    end

    print = origPrint
    write = origWrite
    printError = origPrintError
    term.setTextColor = oldSetTextColor
    term.clear()
    term.setCursorPos(1, 1)
end

return cli
