local vlib = {}

local PROTOCOL = "tweakedlogistics"
local SERVER_HOST = "tweakedlogistics_server"

local _modemSide = nil
local _serverId = nil
local _configPath = nil
local _config = {}
local _speaker = nil
local _connected = false
local _lastServerResponse = 0
local _alarmActive = false
local _clientStatus = {}

local SOUNDS = {
    click = { name = "minecraft:ui.button.click", volume = 0.5, pitch = 1.0 },
    success = { name = "minecraft:entity.experience_orb.pickup", volume = 0.8, pitch = 1.2 },
    error = { name = "minecraft:block.note_block.bass", volume = 0.8, pitch = 0.5 },
    alert = { name = "minecraft:block.note_block.bell", volume = 1.0, pitch = 1.0 },
    item_added = { name = "minecraft:entity.item.pickup", volume = 0.6, pitch = 1.0 },
    item_removed = { name = "minecraft:entity.item.pickup", volume = 0.6, pitch = 0.7 },
    update = { name = "minecraft:block.note_block.chime", volume = 1.0, pitch = 1.5 },
}

function vlib.findModem()
    for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
        if peripheral.hasType(side, "modem") then
            _modemSide = side
            return side
        end
    end
    return nil
end

function vlib.openModem()
    if not _modemSide then
        vlib.findModem()
    end
    if not _modemSide then return false end
    rednet.open(_modemSide)
    return true
end

function vlib.discoverServer(timeout)
    local id = rednet.lookup(PROTOCOL, SERVER_HOST)
    if id then
        _serverId = id
        return id
    end
    return nil
end

function vlib.getServerId()
    return _serverId
end

function vlib.setServerId(id)
    _serverId = id
end

function vlib.send(msg)
    if not _serverId then return false end
    return rednet.send(_serverId, msg)
end

local function handleUpdate()
    if _speaker then
        pcall(_speaker.playSound, "minecraft:block.note_block.chime", 1.0, 1.5)
        sleep(0.3)
        pcall(_speaker.playSound, "minecraft:block.note_block.chime", 1.0, 2.0)
    end

    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Update received from server!")
    print("Installing...")

    local resp = http.get("https://raw.githubusercontent.com/OrigamingWasTaken/tweakedlogistics/main/install.lua?cb=" .. os.epoch("utc"))
    if resp then
        local code = resp.readAll()
        resp.close()
        local fn = loadstring(code, "install.lua")
        if fn then fn() end
    end

    print("Rebooting in 5s...")
    print("(waiting for server to finish)")
    sleep(5)
    os.reboot()
end

function vlib.checkEvent(event, senderId, message)
    if event == "rednet_message" and type(message) == "table" then
        if senderId == _serverId then
            if message.type == "do_update" then
                handleUpdate()
            elseif message.type == "config_ack" then
                _connected = true
                _lastServerResponse = os.epoch("utc")
                _alarmActive = false
            elseif message.type == "reconnect" then
                _connected = true
                _lastServerResponse = os.epoch("utc")
                _alarmActive = false
                vlib.register(_blockType, _blockConfig)
            end
        elseif message.type == "reconnect" then
            _serverId = senderId
            _connected = true
            _lastServerResponse = os.epoch("utc")
            _alarmActive = false
            vlib.saveConfig()
            vlib.register(_blockType, _blockConfig)
        end
    end
end

function vlib.receive(timeout)
    local senderId, message = rednet.receive(nil, timeout)
    if senderId and senderId == _serverId and type(message) == "table" then
        if message.type == "do_update" then
            handleUpdate()
        end
        if message.type == "reconnect" then
            _connected = true
            _lastServerResponse = os.epoch("utc")
            _alarmActive = false
            vlib.register(_blockType, _blockConfig)
            return nil
        end
        if message.type == "pending" then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("Waiting for server approval...")
            print("Ask admin to run: approve " .. os.getComputerID())
            while true do
                local msg2 = vlib.receive(10)
                if msg2 and msg2.type == "config_ack" then
                    return msg2
                end
            end
        end
        if message.type == "revoked" then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("This client has been revoked.")
            print("Contact an admin.")
            while true do sleep(30) end
        end
        _connected = true
        _lastServerResponse = os.epoch("utc")
        _alarmActive = false
        return message
    end
    return nil
end

function vlib.receiveType(msgType, timeout)
    local deadline = os.epoch("utc") + (timeout or 5) * 1000
    while os.epoch("utc") < deadline do
        local remaining = (deadline - os.epoch("utc")) / 1000
        if remaining <= 0 then break end
        local msg = vlib.receive(remaining)
        if msg and msg.type == msgType then
            return msg
        end
    end
    return nil
end

local _blockType = nil
local _blockConfig = nil

function vlib.register(blockType, config)
    _blockType = blockType
    _blockConfig = config
    vlib.send({
        type = "register",
        blockType = blockType,
        computerId = os.getComputerID(),
        config = config,
        version = vlib.getVersion(),
    })
    local reply = vlib.receive(5)
    if reply and reply.type == "config_ack" then
        _connected = true
        _lastServerResponse = os.epoch("utc")
        return true
    end
    return false
end

function vlib.setStatus(status)
    _clientStatus = status or {}
end

function vlib.heartbeat()
    if not _blockType then return end

    vlib.send({
        type = "register",
        blockType = _blockType,
        computerId = os.getComputerID(),
        config = _blockConfig,
        version = vlib.getVersion(),
        status = _clientStatus,
    })

    local elapsed = os.epoch("utc") - _lastServerResponse
    if elapsed > 120000 then
        _connected = false
        if not _alarmActive and _speaker then
            _alarmActive = true
        end
    end
end

function vlib.isConnected()
    return _connected
end

function vlib.playAlarm()
    if not _connected and _speaker then
        pcall(_speaker.playSound, "minecraft:block.note_block.bit", 1.5, 0.5)
        sleep(0.3)
        pcall(_speaker.playSound, "minecraft:block.note_block.bit", 1.5, 0.7)
        sleep(0.3)
        pcall(_speaker.playSound, "minecraft:block.note_block.bit", 1.5, 0.5)
    end
end

function vlib.loadConfig(path)
    _configPath = path
    if fs.exists(path) then
        local h = fs.open(path, "r")
        if h then
            local content = h.readAll()
            h.close()
            local loaded = textutils.unserialize(content)
            if type(loaded) == "table" then
                _config = loaded
                if _config.serverId then
                    _serverId = _config.serverId
                end
                return _config
            end
        end
    end
    return _config
end

function vlib.saveConfig()
    if not _configPath then return end
    _config.serverId = _serverId
    local h = fs.open(_configPath, "w")
    if h then
        h.write(textutils.serialize(_config))
        h.close()
    end
end

function vlib.getConfig()
    return _config
end

function vlib.setConfig(key, value)
    _config[key] = value
    vlib.saveConfig()
end

function vlib.resolveInventory(sideOrName)
    if peripheral.hasType(sideOrName, "inventory") then
        local wrapped = peripheral.wrap(sideOrName)
        if wrapped then
            local name = peripheral.getName(wrapped)
            if name then return name end
        end
    end
    return sideOrName
end

function vlib.listLocalInventories()
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

function vlib.pickInventory()
    local invs = vlib.listLocalInventories()
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
            return vlib.resolveInventory(input)
        end
    else
        write("Destination inventory name: ")
        local input = read()
        if input and input ~= "" then
            return vlib.resolveInventory(input)
        end
    end
    return nil
end

function vlib.matchesItem(slotName, itemName)
    if slotName == itemName then return true end
    if not itemName:find(":") then
        if slotName == "minecraft:" .. itemName then return true end
        if slotName:match(":(.+)") == itemName then return true end
    end
    return false
end

function vlib.countItemInInventory(invName, itemName)
    local total = 0
    local ok, contents = pcall(peripheral.call, invName, "list")
    if ok and contents then
        for _, slot in pairs(contents) do
            if vlib.matchesItem(slot.name, itemName) then
                total = total + slot.count
            end
        end
    end
    return total
end

function vlib.pullFromSources(destination, sources)
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

function vlib.setupScreen(blockName)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== TweakedLogistics ===")
    term.setTextColor(colors.yellow)
    print("Virtual " .. blockName)
    term.setTextColor(colors.white)
    print("")

    if not vlib.openModem() then
        term.setTextColor(colors.red)
        print("No modem found!")
        print("Attach a wired modem and reboot.")
        return false
    end

    print("Searching for server...")
    local id = nil
    if _serverId then
        id = _serverId
        print("Using saved server #" .. id)
    else
        for attempt = 1, 10 do
            id = vlib.discoverServer(3)
            if id then break end
            if attempt < 10 then
                print("Retry " .. attempt .. "/10...")
                sleep(2)
            end
        end
    end

    if not id then
        print("Server not found automatically.")
        term.setTextColor(colors.yellow)
        write("Enter server ID manually: ")
        term.setTextColor(colors.white)
        local input = read()
        local num = tonumber(input)
        if not num then
            term.setTextColor(colors.red)
            print("Invalid ID.")
            return false
        end
        _serverId = num
    end

    print("Connected to server #" .. _serverId)

    vlib.findSpeaker()
    if _speaker then
        print("Speaker detected")
    end

    vlib.saveConfig()
    return true
end

-- Speaker --

function vlib.findSpeaker()
    for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
        if peripheral.hasType(side, "speaker") then
            _speaker = peripheral.wrap(side)
            return _speaker
        end
    end
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "speaker") then
            _speaker = peripheral.wrap(name)
            return _speaker
        end
    end
    return nil
end

function vlib.playSound(soundKey)
    if not _speaker then return end
    local s = SOUNDS[soundKey]
    if not s then return end
    pcall(_speaker.playSound, s.name, s.volume, s.pitch)
end

function vlib.hasSpeaker()
    return _speaker ~= nil
end

-- Version --

function vlib.getVersion()
    if fs.exists("/tweakedlogistics/.version") then
        local h = fs.open("/tweakedlogistics/.version", "r")
        if h then
            local v = h.readAll()
            h.close()
            return v
        end
    end
    return nil
end

return vlib
