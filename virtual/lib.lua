local vlib = {}

local PROTOCOL = "tweakedlogistics"
local SERVER_HOST = "tweakedlogistics_server"

local _modemSide = nil
local _serverId = nil
local _configPath = nil
local _config = {}

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
    return rednet.send(_serverId, msg, PROTOCOL)
end

function vlib.receive(timeout)
    local senderId, message, protocol = rednet.receive(PROTOCOL, timeout)
    if senderId and senderId == _serverId then
        return message
    end
    return nil
end

function vlib.register(blockType, config)
    vlib.send({
        type = "register",
        blockType = blockType,
        computerId = os.getComputerID(),
        config = config,
    })
    local reply = vlib.receive(5)
    if reply and reply.type == "config_ack" then
        return true
    end
    return false
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
    local id = vlib.discoverServer(3)
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
    vlib.saveConfig()
    return true
end

return vlib
