local vlib = dofile("/tweakedlogistics/virtual/lib.lua")

local CONFIG_PATH = "/virtual_terminal.config"
local BLOCK_TYPE = "virtual_terminal"

local function findDiskDrive()
    for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
        if peripheral.hasType(side, "drive") then
            return side
        end
    end
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "drive") then
            return name
        end
    end
    return nil
end

local function setup()
    vlib.loadConfig(CONFIG_PATH)
    if not vlib.setupScreen("Terminal") then return false end

    local cfg = vlib.getConfig()

    term.setTextColor(colors.white)
    print("")

    if not cfg.mode then
        print("Terminal mode:")
        print("  1. Item terminal (redeem/balance)")
        print("  2. Door terminal (access cards)")
        print("  3. Both")
        print("")
        write("Choose (1-3): ")
        local choice = tonumber(read())
        if choice == 1 then cfg.mode = "items"
        elseif choice == 2 then cfg.mode = "door"
        else cfg.mode = "both" end
    end

    if not cfg.driveName then
        cfg.driveName = findDiskDrive()
    end

    if (cfg.mode == "items" or cfg.mode == "both") and not cfg.outputChest then
        print("")
        term.setTextColor(colors.yellow)
        print("Select output chest for items:")
        term.setTextColor(colors.white)
        local chest = vlib.pickInventory()
        if chest then
            cfg.outputChest = chest
        end
    end

    if (cfg.mode == "items" or cfg.mode == "both") and not cfg.reserveChest then
        print("")
        term.setTextColor(colors.yellow)
        print("Select reserve chest for used cards:")
        print("(blank to eject instead)")
        term.setTextColor(colors.white)
        local chest = vlib.pickInventory()
        if chest then
            cfg.reserveChest = chest
        end
    end

    if (cfg.mode == "items" or cfg.mode == "both") and cfg.reserveChest and not cfg.driveOutput then
        print("")
        term.setTextColor(colors.yellow)
        print("Select drive output (hopper below drive):")
        term.setTextColor(colors.white)
        local inv = vlib.pickInventory()
        if inv then
            cfg.driveOutput = inv
        end
    end

    if (cfg.mode == "door" or cfg.mode == "both") then
        if not cfg.zone then
            write("Zone name (e.g. main_door): ")
            cfg.zone = read()
            if not cfg.zone or cfg.zone == "" then cfg.zone = "default" end
        end
        if not cfg.redstoneSide then
            write("Redstone side for door: ")
            local side = read()
            if side and side ~= "" then
                cfg.redstoneSide = side
            end
        end
        if not cfg.redstoneDuration then
            cfg.redstoneDuration = 3
        end
    end

    vlib.saveConfig()

    local ok = vlib.register(BLOCK_TYPE, {
        zone = cfg.zone,
        outputChest = cfg.outputChest,
        redstoneSide = cfg.redstoneSide,
        redstoneDuration = cfg.redstoneDuration,
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

local function drawIdle(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Terminal ===")
    print("")
    term.setTextColor(colors.white)
    print("Zone: " .. (cfg.zone or "default"))
    print("")
    term.setTextColor(colors.yellow)
    print("Insert card...")
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setTextColor(colors.lightGray)
    term.write("Server: " .. (vlib.isConnected() and "Connected" or "DISCONNECTED"))
end

local function handleAccess(cfg, response)
    term.clear()
    term.setCursorPos(1, 1)
    if response.granted then
        term.setTextColor(colors.green)
        print("ACCESS GRANTED")
        print("")
        term.setTextColor(colors.white)
        print(response.label or "")
        vlib.playSound("success")

        if cfg.redstoneSide then
            redstone.setOutput(cfg.redstoneSide, true)
            sleep(response.duration or cfg.redstoneDuration or 3)
            redstone.setOutput(cfg.redstoneSide, false)
        else
            sleep(3)
        end
    else
        term.setTextColor(colors.red)
        print("ACCESS DENIED")
        vlib.playSound("error")
        sleep(2)
    end
end

local function handleRedemptionBalance(cfg, response, diskId, driveName)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== " .. (response.label or "Card") .. " ===")
    print("")

    if not response.items or next(response.items) == nil then
        term.setTextColor(colors.lightGray)
        print("Card is empty.")
        sleep(2)
        return
    end

    local itemList = {}
    for name, count in pairs(response.items) do
        if count > 0 then
            table.insert(itemList, { name = name, count = count })
        end
    end

    if #itemList == 0 then
        term.setTextColor(colors.lightGray)
        print("Card is empty.")
        sleep(2)
        return
    end

    if response.cardType == "redemption" then
        term.setTextColor(colors.yellow)
        print("Redeeming all items...")
        print("")

        for _, item in ipairs(itemList) do
            local displayName = (item.name:match(":(.+)") or item.name):gsub("_", " ")
            term.setTextColor(colors.white)
            print("  " .. displayName .. " x" .. item.count)

            vlib.send({
                type = "card_withdraw",
                diskId = diskId,
                item = item.name,
                count = item.count,
            })
            local reply = vlib.receiveType("card_delivered", 10)
            if reply and reply.count > 0 then
                term.setTextColor(colors.green)
                print("    Delivered " .. reply.count .. "!")
            elseif reply and reply.count == 0 then
                term.setTextColor(colors.red)
                print("    Not in stock!")
            else
                term.setTextColor(colors.red)
                print("    No response")
            end
        end

        print("")
        term.setTextColor(colors.green)
        print("Done!")
        vlib.playSound("success")

        if driveName then
            print("Reclaiming card...")
            disk.eject(driveName)
            sleep(0.5)
            if cfg.driveOutput and cfg.reserveChest then
                local ok, contents = pcall(peripheral.call, cfg.driveOutput, "list")
                if ok and contents then
                    for slot, _ in pairs(contents) do
                        pcall(peripheral.call, cfg.driveOutput, "pushItems", cfg.reserveChest, slot)
                    end
                end
            end
        end
        sleep(2)

    elseif response.cardType == "balance" then
        term.setTextColor(colors.yellow)
        print("Available items:")
        print("")
        for i, item in ipairs(itemList) do
            local displayName = (item.name:match(":(.+)") or item.name):gsub("_", " ")
            term.setTextColor(colors.white)
            print("  " .. i .. ". " .. displayName .. " (x" .. item.count .. ")")
        end

        print("")
        write("Pick item (number): ")
        local choice = tonumber(read())
        if not choice or not itemList[choice] then
            print("Cancelled.")
            sleep(1)
            return
        end

        local selected = itemList[choice]
        write("How many? (max " .. selected.count .. "): ")
        local amount = tonumber(read())
        if not amount or amount <= 0 then
            print("Cancelled.")
            sleep(1)
            return
        end
        if amount > selected.count then amount = selected.count end

        print("")
        print("Withdrawing...")
        vlib.send({
            type = "card_withdraw",
            diskId = diskId,
            item = selected.name,
            count = amount,
        })

        local reply = vlib.receiveType("card_delivered", 10)
        if reply and reply.count > 0 then
            term.setTextColor(colors.green)
            print("Delivered " .. reply.count .. "!")
            vlib.playSound("success")
        else
            term.setTextColor(colors.red)
            print("Delivery failed.")
            vlib.playSound("error")
        end

        print("")
        term.setTextColor(colors.lightGray)
        print("Remove your card.")
        sleep(3)
    end
end

local function mainLoop()
    local cfg = vlib.getConfig()
    local driveName = cfg.driveName or findDiskDrive()

    while true do
        drawIdle(cfg)
        local heartbeatTimer = os.startTimer(30)

        while true do
            local event, p1, p2 = os.pullEvent()
            vlib.checkEvent(event, p1, p2)

            if event == "disk" then
                break
            elseif event == "timer" and p1 == heartbeatTimer then
                vlib.heartbeat()
                drawIdle(cfg)
                heartbeatTimer = os.startTimer(30)
            end
        end

        if not driveName or not disk.isPresent(driveName) then
            sleep(0.5)
        else
            local diskId = disk.getID(driveName)
            if not diskId then
                term.clear()
                term.setCursorPos(1, 1)
                term.setTextColor(colors.red)
                print("Invalid disk.")
                sleep(2)
            else
                vlib.send({
                    type = "card_scan",
                    diskId = diskId,
                    terminalId = os.getComputerID(),
                })

                local response = vlib.receive(5)
                if not response then
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.red)
                    print("Server not responding.")
                    sleep(2)
                elseif response.type == "card_denied" then
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.red)
                    print("Card denied: " .. (response.reason or "unknown"))
                    vlib.playSound("error")
                    sleep(2)
                elseif response.type == "card_access" then
                    handleAccess(cfg, response)
                elseif response.type == "card_data" then
                    handleRedemptionBalance(cfg, response, diskId, driveName)
                end
            end
        end

        while driveName and disk.isPresent(driveName) do
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.lightGray)
            print("Remove your card...")
            sleep(1)
        end
    end
end

if setup() then
    mainLoop()
end
