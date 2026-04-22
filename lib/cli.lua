local cli = {}

local _core = nil
local _storage = nil
local _logistics = nil
local _crafting = nil
local _nicknames = nil
local _server = nil
local _dashboard = nil
local _config = nil

function cli.init(core, storage, logistics, crafting, nicknames, server, dashboard, config)
    _core = core
    _storage = storage
    _logistics = logistics
    _crafting = crafting
    _nicknames = nicknames
    _server = server
    _dashboard = dashboard
    _config = config
end

local function printColor(text, color)
    term.setTextColor(color)
    print(text)
    term.setTextColor(colors.white)
end

local function printHelp()
    printColor("Storage:", colors.yellow)
    print("  stock         Show all items + counts")
    print("  status        System overview")
    print("  scan          Force inventory rescan")
    printColor("Crafting:", colors.yellow)
    print("  processors    List machines")
    print("  add-processor Register a machine")
    print("                (asks: type, input, output)")
    print("  remove-processor <id>")
    print("  jobs          Active crafting jobs")
    printColor("Dashboard:", colors.yellow)
    print("  panels        Show monitor assignments")
    print("  set-panel     Assign panel to monitor")
    printColor("Network:", colors.yellow)
    print("  inventories   All chests on network")
    print("  nickname <inv> <name>")
    print("  nicknames     List all nicknames")
    print("  clients       Connected virtual blocks")
    print("  reconnect     Reconnect all clients")
    print("  update-client <id>  Update one client")
    printColor("System:", colors.yellow)
    print("  update [force]  Check/install updates")
    print("  help          This screen")
    print("  exit          Stop and return to shell")
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

    local serverVersion = nil
    if fs.exists("/tweakedlogistics/.version") then
        local h = fs.open("/tweakedlogistics/.version", "r")
        if h then
            serverVersion = h.readAll()
            h.close()
        end
    end

    for _, client in ipairs(clients) do
        local ver = client.version and client.version:sub(1, 7) or "?"
        local name = client.blockType or "unknown"
        local short = name:gsub("virtual_", "")
        local mismatch = serverVersion and client.version and client.version ~= serverVersion
        term.setTextColor(colors.white)
        write("#" .. client.id .. " " .. short .. " ")
        if mismatch then
            printColor(ver .. " MISMATCH", colors.red)
        else
            printColor(ver, colors.green)
        end
    end
end

local function cmdScan()
    print("Scanning...")
    _storage.scan()
    local s = _storage.getStatus()
    printColor("Found " .. s.uniqueTypes .. " item types in " .. s.inventories .. " inventories (" .. s.lastScanMs .. "ms)", colors.green)
end

local function cmdReconnect()
    if not _server then
        print("Server not running.")
        return
    end
    print("Broadcasting reconnect to all computers...")
    _server.broadcastReconnect()
    printColor("Reconnect sent.", colors.green)
end

local function cmdUpdateClient(args)
    if not _server then
        print("Server not running.")
        return
    end
    local id = args[1]
    if not id then
        write("Client ID: ")
        id = read()
    end
    local num = tonumber(id)
    if not num then
        printColor("Invalid ID.", colors.red)
        return
    end
    _server.updateClient(num)
    printColor("Update sent to #" .. num, colors.green)
end

local function cmdPanels()
    local panelConfig = _config.get("dashboard.panels") or {}
    local monitors = {}
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "monitor") then
            table.insert(monitors, name)
        end
    end

    if #monitors == 0 then
        print("No monitors found.")
        return
    end

    printColor(string.format("%-25s %s", "Monitor", "Panel"), colors.yellow)
    for _, monName in ipairs(monitors) do
        local panel = panelConfig[monName] or "stock_overview (default)"
        local nick = _nicknames and _nicknames.get(monName)
        local display = nick and (monName .. " (" .. nick .. ")") or monName
        print(string.format("%-25s %s", display:sub(1, 25), panel))
    end
end

local function cmdSetPanel(args)
    local monName = args[1]
    local panelId = args[2]

    if not monName then
        local monitors = {}
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            if peripheral.hasType(name, "monitor") then
                table.insert(monitors, name)
            end
        end
        if #monitors == 0 then
            print("No monitors found.")
            return
        end
        printColor("Monitors:", colors.yellow)
        for i, name in ipairs(monitors) do
            print("  " .. i .. ". " .. name)
        end
        write("Pick monitor (number or name): ")
        local input = read()
        local num = tonumber(input)
        if num and monitors[num] then
            monName = monitors[num]
        elseif input and input ~= "" then
            monName = input
        else
            return
        end
    end

    if not panelId then
        local types = _dashboard.getPanelTypes()
        printColor("Panel types:", colors.yellow)
        for i, t in ipairs(types) do
            print("  " .. i .. ". " .. t)
        end
        write("Pick panel (number or name): ")
        local input = read()
        local num = tonumber(input)
        if num and types[num] then
            panelId = types[num]
        elseif input and input ~= "" then
            panelId = input
        else
            return
        end
    end

    local panelConfig = _config.get("dashboard.panels") or {}
    panelConfig[monName] = panelId
    _config.set("dashboard.panels", panelConfig)
    printColor("Set " .. monName .. " -> " .. panelId, colors.green)
end

local function cmdUpdate(force)
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

    if currentHash and currentHash == latestHash and not force then
        printColor("Already up to date. Use 'update force' to reinstall.", colors.green)
        return
    end

    if force then
        printColor("Forcing reinstall...", colors.yellow)
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

    if _server then
        local clients = _server.getClients()
        if #clients > 0 then
            print("")
            print("Updating " .. #clients .. " connected client(s)...")
            local count = _server.broadcastUpdate()
            printColor("Sent update command to " .. count .. " client(s)", colors.green)
        end
    end

    print("")
    print("Updating server...")
    local dlResp = http.get("https://raw.githubusercontent.com/OrigamingWasTaken/tweakedlogistics/main/install.lua?cb=" .. os.epoch("utc"))
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
    print("")
    print("Rebooting...")
    sleep(1)
    os.reboot()
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
    elseif cmd == "processors" then cmdProcessors()
    elseif cmd == "add-processor" then cmdAddProcessor()
    elseif cmd == "remove-processor" then cmdRemoveProcessor(args[1])
    elseif cmd == "jobs" then cmdJobs()
    elseif cmd == "inventories" then cmdInventories()
    elseif cmd == "nickname" then cmdNickname(args)
    elseif cmd == "nicknames" then cmdNicknames()
    elseif cmd == "clients" then cmdClients()
    elseif cmd == "scan" then cmdScan()
    elseif cmd == "panels" then cmdPanels()
    elseif cmd == "set-panel" then cmdSetPanel(args)
    elseif cmd == "reconnect" then cmdReconnect()
    elseif cmd == "update-client" then cmdUpdateClient(args)
    elseif cmd == "update" then cmdUpdate(args[1] == "force")
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
            while #line > screenW do
                addLine(line:sub(1, screenW), fg or colors.white)
                line = line:sub(screenW + 1)
            end
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
    local lineOpen = false

    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            table.insert(parts, tostring(select(i, ...)))
        end
        local text = table.concat(parts, "\t")
        if lineOpen then
            lines[#lines] = lines[#lines] .. text
            lineColors[#lines] = currentFg
            lineOpen = false
        else
            cliPrint(text, currentFg)
        end
        scrollOffset = 0
        redraw()
    end

    write = function(text)
        text = tostring(text or "")
        if not lineOpen then
            addLine("", colors.white)
            lineOpen = true
        end
        lines[#lines] = lines[#lines] .. text
        lineColors[#lines] = currentFg
        scrollOffset = 0
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
    local s = _storage.getStatus()
    cliPrint("Found " .. s.uniqueTypes .. " items in " .. s.inventories .. " inventories", colors.white)
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
