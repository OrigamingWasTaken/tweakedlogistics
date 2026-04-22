local vlib = dofile("/tweakedlogistics/virtual/lib.lua")

local CONFIG_PATH = "/virtual_speaker.config"
local BLOCK_TYPE = "virtual_speaker"

local function setup()
    vlib.loadConfig(CONFIG_PATH)
    if not vlib.setupScreen("Speaker") then return false end

    if not vlib.hasSpeaker() then
        term.setTextColor(colors.red)
        print("")
        print("No speaker found!")
        print("Attach a speaker and reboot.")
        return false
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

local function drawStatus(lastEvent)
    term.clear()
    term.setCursorPos(1, 1)

    term.setTextColor(colors.cyan)
    print("=== Virtual Speaker ===")
    print("")

    term.setTextColor(colors.white)
    local version = vlib.getVersion()
    print("Server: #" .. (vlib.getServerId() or "?"))
    if version then
        print("Version: " .. version:sub(1, 7))
    end
    print("")

    term.setTextColor(colors.yellow)
    print("Listening for events...")
    print("")

    if lastEvent then
        term.setTextColor(colors.white)
        print("Last: " .. lastEvent)
    end

    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setTextColor(colors.lightGray)
    print("Ctrl+T to stop")
end

local function mainLoop()
    local lastEvent = nil
    drawStatus(lastEvent)

    while true do
        local msg = vlib.receive(5)

        if msg and type(msg) == "table" then
            if msg.type == "stock_update" then
                vlib.playSound("item_added")
                lastEvent = "Stock updated"
                drawStatus(lastEvent)

            elseif msg.type == "item_sources" then
                vlib.playSound("click")
                lastEvent = "Item request"
                drawStatus(lastEvent)

            elseif msg.type == "items_delivered" then
                if msg.delivered and msg.delivered > 0 then
                    vlib.playSound("success")
                    lastEvent = "Delivered " .. msg.delivered .. "x " .. (msg.item or "?")
                else
                    vlib.playSound("error")
                    lastEvent = "Delivery failed: " .. (msg.item or "?")
                end
                drawStatus(lastEvent)

            elseif msg.type == "craft_status" then
                vlib.playSound("alert")
                lastEvent = "Craft: " .. (msg.status or "?")
                drawStatus(lastEvent)
            end
        end
    end
end

if setup() then
    mainLoop()
end
