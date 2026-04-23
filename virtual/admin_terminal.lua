local vlib = dofile("/tweakedlogistics/virtual/lib.lua")

local CONFIG_PATH = "/virtual_admin.config"
local BLOCK_TYPE = "virtual_admin_terminal"

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
    if not vlib.setupScreen("Admin Terminal") then return false end

    local cfg = vlib.getConfig()

    if not cfg.driveName then
        cfg.driveName = findDiskDrive()
        if not cfg.driveName then
            term.setTextColor(colors.red)
            print("No disk drive found!")
            return false
        end
    end

    if not cfg.reserveChest then
        print("")
        term.setTextColor(colors.yellow)
        print("Select reserve chest (blank floppies):")
        term.setTextColor(colors.white)
        cfg.reserveChest = vlib.pickInventory()
    end

    if not cfg.inputBarrel then
        print("")
        term.setTextColor(colors.yellow)
        print("Select input barrel (admin drops cards):")
        term.setTextColor(colors.white)
        cfg.inputBarrel = vlib.pickInventory()
    end

    if not cfg.outputBarrel then
        print("")
        term.setTextColor(colors.yellow)
        print("Select output barrel (admin picks up):")
        term.setTextColor(colors.white)
        cfg.outputBarrel = vlib.pickInventory()
    end

    if not cfg.driveInput then
        print("")
        term.setTextColor(colors.yellow)
        print("Select drive input (hopper above drive):")
        term.setTextColor(colors.white)
        cfg.driveInput = vlib.pickInventory()
    end

    if not cfg.driveOutput then
        print("")
        term.setTextColor(colors.yellow)
        print("Select drive output (hopper below):")
        term.setTextColor(colors.white)
        cfg.driveOutput = vlib.pickInventory()
    end

    if not cfg.lockSide then
        write("Redstone lock side (back): ")
        local side = read()
        cfg.lockSide = (side and side ~= "") and side or "back"
    end

    redstone.setOutput(cfg.lockSide, true)

    vlib.saveConfig()

    local ok = vlib.register(BLOCK_TYPE, {})

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

local function loadFromBarrel(cfg)
    if not cfg.inputBarrel or not cfg.driveInput then return false end
    local ok, contents = pcall(peripheral.call, cfg.inputBarrel, "list")
    if ok and contents then
        for slot, _ in pairs(contents) do
            local ok2, moved = pcall(
                peripheral.call, cfg.inputBarrel, "pushItems",
                cfg.driveInput, slot, 1
            )
            if ok2 and moved and moved > 0 then
                sleep(1)
                return true
            end
        end
    end
    return false
end

local function loadFromReserve(cfg)
    if not cfg.reserveChest or not cfg.driveInput then return false end
    local ok, contents = pcall(peripheral.call, cfg.reserveChest, "list")
    if ok and contents then
        for slot, _ in pairs(contents) do
            local ok2, moved = pcall(
                peripheral.call, cfg.reserveChest, "pushItems",
                cfg.driveInput, slot, 1
            )
            if ok2 and moved and moved > 0 then
                sleep(1)
                return true
            end
        end
    end
    return false
end

local function ejectToBarrel(cfg)
    if not cfg.driveOutput or not cfg.outputBarrel then return false end
    redstone.setOutput(cfg.lockSide, false)
    sleep(0.5)
    disk.eject(cfg.driveName)
    sleep(0.5)
    redstone.setOutput(cfg.lockSide, true)
    sleep(0.3)
    local ok, contents = pcall(peripheral.call, cfg.driveOutput, "list")
    if ok and contents then
        for slot, _ in pairs(contents) do
            pcall(peripheral.call, cfg.driveOutput, "pushItems", cfg.outputBarrel, slot)
        end
    end
    return true
end

local function ejectToReserve(cfg)
    if not cfg.driveOutput or not cfg.reserveChest then return false end
    redstone.setOutput(cfg.lockSide, false)
    sleep(0.5)
    disk.eject(cfg.driveName)
    sleep(0.5)
    redstone.setOutput(cfg.lockSide, true)
    sleep(0.3)
    local ok, contents = pcall(peripheral.call, cfg.driveOutput, "list")
    if ok and contents then
        for slot, _ in pairs(contents) do
            pcall(peripheral.call, cfg.driveOutput, "pushItems", cfg.reserveChest, slot)
        end
    end
    return true
end

local function drawMenu()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Admin Terminal ===")
    print("")
    term.setTextColor(colors.white)
    print("  1. Create Card")
    print("  2. Recharge Card")
    print("  3. View Card")
    print("  4. Revoke Card")
    print("")
    term.setTextColor(colors.lightGray)
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.write("Server: " .. (vlib.isConnected() and "Connected" or "DISCONNECTED"))
end

local function waitForDisk(driveName)
    if disk.isPresent(driveName) then return true end
    term.setTextColor(colors.yellow)
    print("Insert a floppy disk...")
    while not disk.isPresent(driveName) do
        os.pullEvent("disk")
    end
    return true
end

local function createCard(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Create Card ===")
    print("")

    term.setTextColor(colors.white)
    print("Card type:")
    print("  1. Redemption (one-time)")
    print("  2. Balance (rechargeable)")
    print("  3. Access (door/zone)")
    print("")
    write("Choose (1-3): ")
    local typeChoice = tonumber(read())
    if not typeChoice or typeChoice < 1 or typeChoice > 3 then return end

    local cardTypes = { "redemption", "balance", "access" }
    local cardType = cardTypes[typeChoice]

    write("Card label: ")
    local label = read()
    if not label or label == "" then label = cardType .. " card" end

    local cardData = {
        type = cardType,
        label = label,
    }

    if cardType == "redemption" or cardType == "balance" then
        cardData.items = {}
        cardData.rechargeable = (cardType == "balance")
        print("")
        term.setTextColor(colors.yellow)
        print("Add items (blank to finish):")
        term.setTextColor(colors.white)
        while true do
            write("  Item: ")
            local item = read()
            if not item or item == "" then break end
            write("  Count: ")
            local count = tonumber(read())
            if not count then break end
            cardData.items[item] = (cardData.items[item] or 0) + count
        end
    elseif cardType == "access" then
        write("Access level (admin/member/guest): ")
        cardData.level = read() or "guest"
        cardData.zones = {}
        print("")
        term.setTextColor(colors.yellow)
        print("Add zones (blank to finish):")
        term.setTextColor(colors.white)
        while true do
            write("  Zone: ")
            local zone = read()
            if not zone or zone == "" then break end
            table.insert(cardData.zones, zone)
        end
    end

    print("")
    local driveName = cfg.driveName

    if not disk.isPresent(driveName) then
        print("Loading floppy from reserve...")
        if not loadFromReserve(cfg) then
            term.setTextColor(colors.red)
            print("No floppies in reserve!")
            sleep(2)
            return
        end
    end

    if not disk.isPresent(driveName) then
        waitForDisk(driveName)
    end

    local diskId = disk.getID(driveName)
    if not diskId then
        term.setTextColor(colors.red)
        print("Can't read disk ID!")
        sleep(2)
        return
    end

    vlib.send({
        type = "card_create",
        diskId = diskId,
        cardData = cardData,
    })

    vlib.receiveType("card_created", 5)

    disk.setLabel(driveName, cardData.label)

    term.setTextColor(colors.green)
    print("Card created! Disk #" .. diskId)
    print('Label: "' .. cardData.label .. '"')
    vlib.playSound("success")

    print("Ejecting to output...")
    ejectToBarrel(cfg)
end

local function rechargeCard(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Recharge Card ===")
    print("")

    local driveName = cfg.driveName
    if not disk.isPresent(driveName) then
        print("Insert card into input barrel...")
        if not loadFromBarrel(cfg) then
            waitForDisk(driveName)
        end
    end

    local diskId = disk.getID(driveName)
    if not diskId then
        term.setTextColor(colors.red)
        print("Can't read disk ID!")
        sleep(2)
        return
    end

    vlib.send({
        type = "card_scan",
        diskId = diskId,
        terminalId = os.getComputerID(),
    })

    local response = vlib.receive(5)
    if not response or response.type == "card_denied" then
        term.setTextColor(colors.red)
        print("Card not found on server.")
        sleep(2)
        return
    end

    if response.type ~= "card_data" or not response.rechargeable then
        term.setTextColor(colors.red)
        print("This card can't be recharged.")
        sleep(2)
        return
    end

    term.setTextColor(colors.white)
    print("Card: " .. (response.label or "?"))
    print("Current balance:")
    if response.items then
        for name, count in pairs(response.items) do
            local dn = (name:match(":(.+)") or name):gsub("_", " ")
            print("  " .. dn .. ": " .. count)
        end
    end

    print("")
    term.setTextColor(colors.yellow)
    print("Add items (blank to finish):")
    term.setTextColor(colors.white)
    while true do
        write("  Item: ")
        local item = read()
        if not item or item == "" then break end
        write("  Count: ")
        local count = tonumber(read())
        if not count then break end

        vlib.send({
            type = "card_recharge",
            diskId = diskId,
            item = item,
            count = count,
        })
        local reply = vlib.receiveType("card_recharged", 5)
        if reply then
            term.setTextColor(colors.green)
            print("  Added!")
            term.setTextColor(colors.white)
        end
    end

    print("Ejecting to output...")
    ejectToBarrel(cfg)
end

local function viewCard(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== View Card ===")
    print("")

    local driveName = cfg.driveName
    if not disk.isPresent(driveName) then
        print("Insert card into input barrel...")
        if not loadFromBarrel(cfg) then
            waitForDisk(driveName)
        end
    end

    local diskId = disk.getID(driveName)
    if not diskId then
        term.setTextColor(colors.red)
        print("Can't read disk ID!")
        sleep(2)
        return
    end

    vlib.send({
        type = "card_scan",
        diskId = diskId,
        terminalId = os.getComputerID(),
    })

    local response = vlib.receive(5)
    if not response or response.type == "card_denied" then
        term.setTextColor(colors.red)
        print("Card not registered.")
        sleep(2)
        return
    end

    term.setTextColor(colors.white)
    print("Disk #" .. diskId)
    print("Type: " .. (response.cardType or "?"))
    print("Label: " .. (response.label or "?"))

    if response.items then
        print("")
        term.setTextColor(colors.yellow)
        print("Items:")
        term.setTextColor(colors.white)
        for name, count in pairs(response.items) do
            local dn = (name:match(":(.+)") or name):gsub("_", " ")
            print("  " .. dn .. ": " .. count)
        end
    end

    print("")
    term.setTextColor(colors.lightGray)
    print("Press any key...")
    os.pullEvent("key")

    print("Ejecting to output...")
    ejectToBarrel(cfg)
end

local function revokeCard(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Revoke Card ===")
    print("")

    local driveName = cfg.driveName
    if not disk.isPresent(driveName) then
        print("Insert card into input barrel...")
        if not loadFromBarrel(cfg) then
            waitForDisk(driveName)
        end
    end

    local diskId = disk.getID(driveName)
    if not diskId then
        term.setTextColor(colors.red)
        print("Can't read disk ID!")
        sleep(2)
        return
    end

    term.setTextColor(colors.yellow)
    print("Disk #" .. diskId)
    write("Revoke this card? (y/n): ")
    local answer = read()
    if answer ~= "y" and answer ~= "Y" then
        print("Cancelled.")
        sleep(1)
        return
    end

    vlib.send({
        type = "card_revoke",
        diskId = diskId,
    })
    vlib.receiveType("card_revoked", 5)

    disk.setLabel(driveName, nil)

    term.setTextColor(colors.green)
    print("Card revoked.")
    vlib.playSound("success")

    if cfg.driveOutput and cfg.reserveChest then
        print("Returning floppy to reserve...")
        ejectToReserve(cfg)
    else
        print("")
        term.setTextColor(colors.lightGray)
        print("Remove the disk.")
        while disk.isPresent(driveName) do sleep(0.5) end
    end
end

local function mainLoop()
    local cfg = vlib.getConfig()

    local heartbeatTimer = os.startTimer(10)

    while true do
        drawMenu()

        local event, p1, p2 = os.pullEvent()
        vlib.checkEvent(event, p1, p2)

        if event == "timer" and p1 == heartbeatTimer then
            vlib.heartbeat()
            heartbeatTimer = os.startTimer(10)
        elseif event == "key" then
            if p1 == keys.one then
                createCard(cfg)
            elseif p1 == keys.two then
                rechargeCard(cfg)
            elseif p1 == keys.three then
                viewCard(cfg)
            elseif p1 == keys.four then
                revokeCard(cfg)
            end
        end
    end
end

if setup() then
    mainLoop()
end
