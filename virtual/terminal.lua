local vlib = dofile("/tweakedlogistics/virtual/lib.lua")
local rarity = dofile("/tweakedlogistics/lib/rarity.lua")

local CONFIG_PATH = "/virtual_terminal.config"
local BLOCK_TYPE = "virtual_terminal"

-- Disk helpers --

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

local function drainToTarget(cfg, targetInv)
    if not cfg.driveOutput or not targetInv or not cfg.lockSide then return false end
    local driveName = cfg.driveName
    redstone.setOutput(cfg.lockSide, false)
    for _ = 1, 20 do
        if not disk.isPresent(driveName) then break end
        sleep(0.25)
    end
    sleep(0.5)
    redstone.setOutput(cfg.lockSide, true)
    local ok, contents = pcall(peripheral.call, cfg.driveOutput, "list")
    if ok and contents then
        for slot, _ in pairs(contents) do
            pcall(peripheral.call, cfg.driveOutput, "pushItems", targetInv, slot)
        end
    end
    return true
end

local function ejectToBarrel(cfg) return drainToTarget(cfg, cfg.outputBarrel) end
local function returnToInput(cfg) return drainToTarget(cfg, cfg.inputBarrel) end
local function ejectToReserve(cfg) return drainToTarget(cfg, cfg.reserveChest) end

-- Monitor drawing --

local _mon = nil
local _monName = nil
local _palette = {
    bg = 0x0f0f14,
    panel = 0x1a1b26,
    border = 0x414868,
    accent = 0x7aa2f7,
    text = 0xa9b1d6,
    green = 0x73daca,
    red = 0xf7768e,
    yellow = 0xe0af68,
    cyan = 0x7dcfff,
    purple = 0xbb9af7,
    orange = 0xff9e64,
}

local function applyPalette(mon)
    mon.setPaletteColor(colors.black, _palette.bg)
    mon.setPaletteColor(colors.gray, _palette.panel)
    mon.setPaletteColor(colors.lightGray, _palette.border)
    mon.setPaletteColor(colors.blue, _palette.accent)
    mon.setPaletteColor(colors.white, _palette.text)
    mon.setPaletteColor(colors.green, _palette.green)
    mon.setPaletteColor(colors.red, _palette.red)
    mon.setPaletteColor(colors.yellow, _palette.yellow)
    mon.setPaletteColor(colors.cyan, _palette.cyan)
    mon.setPaletteColor(colors.purple, _palette.purple)
    mon.setPaletteColor(colors.orange, _palette.orange)
end

local function mClear()
    _mon.setBackgroundColor(colors.black)
    _mon.clear()
end

local function mText(x, y, str, fg, bg)
    _mon.setCursorPos(x, y)
    if bg then _mon.setBackgroundColor(bg) end
    if fg then _mon.setTextColor(fg) end
    _mon.write(str)
end

local function mBox(x, y, w, h, bg)
    _mon.setBackgroundColor(bg)
    for row = y, y + h - 1 do
        _mon.setCursorPos(x, row)
        _mon.write(string.rep(" ", w))
    end
end

local function mCenter(y, str, fg, bg)
    local w, _ = _mon.getSize()
    local x = math.floor((w - #str) / 2) + 1
    mText(x, y, str, fg, bg)
end

local function drawBranding(y)
    local w, _ = _mon.getSize()
    local brand = "TweakedLogistics"
    local x = math.floor((w - #brand) / 2) + 1
    mText(x, y, "T", colors.cyan, colors.black)
    mText(x + 1, y, "weaked", colors.white, colors.black)
    mText(x + 7, y, "L", colors.cyan, colors.black)
    mText(x + 8, y, "ogistics", colors.white, colors.black)
end

local _buttons = {}

local function drawButton(x, y, w, label, fg, bg, id)
    mBox(x, y, w, 1, bg)
    local lx = x + math.floor((w - #label) / 2)
    mText(lx, y, label, fg, bg)
    _buttons[id] = { x1 = x, x2 = x + w - 1, y = y }
end

local function checkButton(tx, ty)
    for id, btn in pairs(_buttons) do
        if tx >= btn.x1 and tx <= btn.x2 and ty == btn.y then
            return id
        end
    end
    return nil
end

-- Screens --

local function drawIdle()
    _buttons = {}
    mClear()
    local w, h = _mon.getSize()
    drawBranding(2)
    mCenter(4, string.rep("-", w - 4), colors.lightGray, colors.black)
    mCenter(math.floor(h / 2), "Insert card...", colors.yellow, colors.black)
    mCenter(h, "Server: " .. (vlib.isConnected() and "Connected" or "DISCONNECTED"),
        vlib.isConnected() and colors.green or colors.red, colors.black)
end

local function drawCardPreview(response)
    _buttons = {}
    mClear()
    local w, h = _mon.getSize()

    drawBranding(1)
    mCenter(3, response.label or "Card", colors.cyan, colors.black)
    mCenter(4, string.rep("-", w - 4), colors.lightGray, colors.black)

    local row = 6
    if response.items then
        for name, count in pairs(response.items) do
            if count > 0 and row < h - 3 then
                local displayName = (name:match(":(.+)") or name):gsub("_", " ")
                mText(3, row, displayName, colors.white, colors.black)
                local countStr = "x" .. tostring(count)
                mText(w - #countStr, row, countStr, colors.cyan, colors.black)
                row = row + 1
            end
        end
    end

    local btnW = math.floor((w - 6) / 2)
    local btnY = h - 1
    if response.cardType == "redemption" then
        drawButton(2, btnY, btnW, "[Redeem]", colors.white, colors.green, "redeem")
        drawButton(w - btnW, btnY, btnW, "[Eject]", colors.white, colors.red, "eject")
    elseif response.cardType == "balance" then
        drawButton(2, btnY, btnW, "[Withdraw]", colors.white, colors.green, "withdraw")
        drawButton(w - btnW, btnY, btnW, "[Eject]", colors.white, colors.red, "eject")
    end
end

local function drawProcessing(msg)
    mClear()
    local _, h = _mon.getSize()
    drawBranding(1)
    mCenter(math.floor(h / 2), msg, colors.yellow, colors.black)
end

local function drawResult(msg, ok)
    mClear()
    local _, h = _mon.getSize()
    drawBranding(1)
    mCenter(math.floor(h / 2), msg, ok and colors.green or colors.red, colors.black)
end

-- Setup --

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
        cfg.driveName = vlib.pickDrive()
    end

    if not cfg.monitorName then
        local monitors = {}
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            if peripheral.hasType(name, "monitor") then
                table.insert(monitors, name)
            end
        end
        for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
            if peripheral.hasType(side, "monitor") then
                local already = false
                for _, m in ipairs(monitors) do
                    if m == side then already = true break end
                end
                if not already then table.insert(monitors, side) end
            end
        end
        if #monitors == 1 then
            cfg.monitorName = monitors[1]
        elseif #monitors > 1 then
            print("")
            term.setTextColor(colors.yellow)
            print("Available monitors:")
            term.setTextColor(colors.white)
            for i, m in ipairs(monitors) do
                print("  " .. i .. ". " .. m)
            end
            write("Pick monitor: ")
            local num = tonumber(read())
            if num and monitors[num] then
                cfg.monitorName = monitors[num]
            else
                cfg.monitorName = monitors[1]
            end
        end
    end

    if (cfg.mode == "items" or cfg.mode == "both") and not cfg.outputChest then
        print("")
        term.setTextColor(colors.yellow)
        print("Select output chest for items:")
        term.setTextColor(colors.white)
        cfg.outputChest = vlib.pickInventory()
    end

    if (cfg.mode == "items" or cfg.mode == "both") then
        if not cfg.inputBarrel then
            print("")
            term.setTextColor(colors.yellow)
            print("Select input barrel (player drops card):")
            term.setTextColor(colors.white)
            cfg.inputBarrel = vlib.pickInventory()
        end
        if not cfg.outputBarrel then
            print("")
            term.setTextColor(colors.yellow)
            print("Select output barrel (player picks up):")
            term.setTextColor(colors.white)
            cfg.outputBarrel = vlib.pickInventory()
        end
        if not cfg.reserveChest then
            print("")
            term.setTextColor(colors.yellow)
            print("Select reserve chest (used cards):")
            term.setTextColor(colors.white)
            cfg.reserveChest = vlib.pickInventory()
        end
        if not cfg.driveInput then
            print("")
            term.setTextColor(colors.yellow)
            print("Select drive input (hopper above):")
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
            if side and side ~= "" then cfg.redstoneSide = side end
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

-- Card handling --

local function handleRedemption(cfg, response, diskId)
    drawProcessing("Redeeming items...")
    local anyDelivered = false

    for name, count in pairs(response.items or {}) do
        if count > 0 then
            vlib.send({
                type = "card_withdraw",
                diskId = diskId,
                item = name,
                count = count,
            })
            local reply = vlib.receiveType("card_delivered", 10)
            if reply and reply.count and reply.count > 0 then
                anyDelivered = true
            end
        end
    end

    if anyDelivered then
        drawResult("Items delivered!", true)
        vlib.playSound("success")
        ejectToReserve(cfg)
    else
        drawResult("Nothing in stock!", false)
        vlib.playSound("error")
        returnToInput(cfg)
    end
    sleep(3)
end

local function handleBalance(cfg, response, diskId)
    drawCardPreview(response)

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        vlib.checkEvent(event, p1, p2)

        if event == "monitor_touch" and p1 == _monName then
            local btn = checkButton(p2, p3)
            if btn == "eject" then
                vlib.playSound("click")
                drawProcessing("Ejecting card...")
                ejectToBarrel(cfg)
                sleep(1)
                return
            elseif btn == "withdraw" then
                vlib.playSound("click")
                drawProcessing("Withdrawing all items...")
                local anyDelivered = false

                for name, count in pairs(response.items or {}) do
                    if count > 0 then
                        vlib.send({
                            type = "card_withdraw",
                            diskId = diskId,
                            item = name,
                            count = count,
                        })
                        local reply = vlib.receiveType("card_delivered", 10)
                        if reply and reply.count and reply.count > 0 then
                            anyDelivered = true
                        end
                    end
                end

                if anyDelivered then
                    drawResult("Items delivered!", true)
                    vlib.playSound("success")
                else
                    drawResult("Nothing in stock!", false)
                    vlib.playSound("error")
                end
                ejectToBarrel(cfg)
                sleep(3)
                return
            end
        end
    end
end

-- Main loop --

local function mainLoop()
    local cfg = vlib.getConfig()
    local driveName = cfg.driveName

    if cfg.lockSide then
        redstone.setOutput(cfg.lockSide, true)
    end

    if cfg.monitorName then
        _monName = cfg.monitorName
        _mon = peripheral.wrap(_monName)
        if _mon then
            _mon.setTextScale(1)
            applyPalette(_mon)
        end
    end

    if not _mon then
        print("No monitor configured!")
        return
    end

    while true do
        drawIdle()
        local heartbeatTimer = os.startTimer(10)
        local pollTimer = os.startTimer(2)

        while true do
            local event, p1, p2, p3 = os.pullEvent()
            vlib.checkEvent(event, p1, p2)

            if event == "disk" then
                sleep(0.5)
                break
            elseif event == "timer" and p1 == heartbeatTimer then
                vlib.heartbeat()
                drawIdle()
                heartbeatTimer = os.startTimer(10)
            elseif event == "timer" and p1 == pollTimer then
                loadFromBarrel(cfg)
                if disk.isPresent(driveName) then
                    sleep(0.5)
                    break
                end
                pollTimer = os.startTimer(2)
            end
        end

        if not disk.isPresent(driveName) then
            sleep(0.5)
        else
            local diskId = disk.getID(driveName)
            if not diskId then
                drawResult("Invalid disk", false)
                vlib.playSound("error")
                returnToInput(cfg)
                sleep(2)
            else
                vlib.send({
                    type = "card_scan",
                    diskId = diskId,
                    terminalId = os.getComputerID(),
                })

                drawProcessing("Reading card...")
                local response = vlib.receive(5)

                if not response then
                    drawResult("Server not responding", false)
                    returnToInput(cfg)
                    sleep(2)
                elseif response.type == "card_denied" then
                    drawResult("Card denied", false)
                    vlib.playSound("error")
                    returnToInput(cfg)
                    sleep(2)
                elseif response.type == "card_access" then
                    if response.granted then
                        drawResult("ACCESS GRANTED", true)
                        vlib.playSound("success")
                        if cfg.redstoneSide then
                            redstone.setOutput(cfg.redstoneSide, true)
                            sleep(response.duration or cfg.redstoneDuration or 3)
                            redstone.setOutput(cfg.redstoneSide, false)
                        end
                    else
                        drawResult("ACCESS DENIED", false)
                        vlib.playSound("error")
                    end
                    returnToInput(cfg)
                    sleep(2)
                elseif response.type == "card_data" then
                    if response.cardType == "redemption" then
                        drawCardPreview(response)

                        while true do
                            local ev, ep1, ep2, ep3 = os.pullEvent()
                            vlib.checkEvent(ev, ep1, ep2)
                            if ev == "monitor_touch" and ep1 == _monName then
                                local btn = checkButton(ep2, ep3)
                                if btn == "redeem" then
                                    vlib.playSound("click")
                                    handleRedemption(cfg, response, diskId)
                                    break
                                elseif btn == "eject" then
                                    vlib.playSound("click")
                                    drawProcessing("Returning card...")
                                    returnToInput(cfg)
                                    sleep(1)
                                    break
                                end
                            end
                        end
                    elseif response.cardType == "balance" then
                        handleBalance(cfg, response, diskId)
                    end
                end
            end
        end

        while driveName and disk.isPresent(driveName) do
            sleep(0.5)
        end
    end
end

if setup() then
    mainLoop()
end
