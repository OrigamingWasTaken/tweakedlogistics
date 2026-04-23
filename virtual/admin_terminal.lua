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
        local chest = vlib.pickInventory()
        if chest then
            cfg.reserveChest = chest
        end
    end

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

    if not disk.isPresent(driveName) and cfg.reserveChest then
        print("Loading floppy from reserve...")
        local ok, moved = pcall(
            peripheral.call, driveName, "pullItems",
            cfg.reserveChest, 1, 1
        )
        if not ok or not moved or moved == 0 then
            local contents = peripheral.call(cfg.reserveChest, "list")
            if contents then
                for slot, _ in pairs(contents) do
                    local ok2, moved2 = pcall(
                        peripheral.call, driveName, "pullItems",
                        cfg.reserveChest, slot, 1
                    )
                    if ok2 and moved2 and moved2 > 0 then break end
                end
            end
        end
        sleep(0.5)
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

    print("")
    term.setTextColor(colors.lightGray)
    print("Remove the card.")
    while disk.isPresent(driveName) do sleep(0.5) end
end

local function rechargeCard(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Recharge Card ===")
    print("")

    local driveName = cfg.driveName
    waitForDisk(driveName)

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

    print("")
    term.setTextColor(colors.lightGray)
    print("Remove the card.")
    while disk.isPresent(driveName) do sleep(0.5) end
end

local function viewCard(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== View Card ===")
    print("")

    local driveName = cfg.driveName
    waitForDisk(driveName)

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

    print("Remove the card.")
    while disk.isPresent(driveName) do sleep(0.5) end
end

local function revokeCard(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Revoke Card ===")
    print("")

    local driveName = cfg.driveName
    waitForDisk(driveName)

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

    print("")
    term.setTextColor(colors.lightGray)
    print("Remove the disk.")
    while disk.isPresent(driveName) do sleep(0.5) end
end

local function mainLoop()
    local cfg = vlib.getConfig()

    while true do
        drawMenu()

        local event, p1 = os.pullEvent("key")
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

if setup() then
    mainLoop()
end
