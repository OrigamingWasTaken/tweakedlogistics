local server = {}

local PROTOCOL = "tweakedlogistics"
local HOST = "tweakedlogistics_server"

local _core = nil
local _storage = nil
local _logistics = nil
local _crafting = nil
local _nicknames = nil
local _config = nil
local _clients = {}
local _modemSide = nil

function server.init(core, storage, logistics, crafting, nicknames, config)
    _core = core
    _storage = storage
    _logistics = logistics
    _crafting = crafting
    _nicknames = nicknames
    _config = config

    _core.event.on("storage:changed", function(delta)
        server.broadcastStockUpdate()
    end)
end

local function findModem()
    for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
        if peripheral.hasType(side, "modem") then
            return side
        end
    end
    return nil
end

function server.broadcastStockUpdate()
    local items = _storage.getItems()
    local compact = {}
    for _, item in ipairs(items) do
        table.insert(compact, {
            name = item.name,
            displayName = item.displayName,
            count = item.count,
            nbt = item.nbt,
        })
    end
    for clientId, _ in pairs(_clients) do
        rednet.send(clientId, {
            type = "stock_update",
            items = compact,
        })
    end
end

local function findItem(itemName)
    local items = _storage.getItems()
    for _, item in ipairs(items) do
        if item.name == itemName then return item end
    end
    if not itemName:find(":") then
        for _, item in ipairs(items) do
            if item.name == "minecraft:" .. itemName then return item end
        end
        for _, item in ipairs(items) do
            if item.name:match(":(.+)") == itemName then return item end
        end
    end
    return nil
end

local function handleRegister(senderId, msg)
    _clients[senderId] = {
        blockType = msg.blockType,
        computerId = msg.computerId,
        config = msg.config,
        version = msg.version,
        lastSeen = os.epoch("utc"),
    }

    if msg.config and msg.config.destination then
        _storage.excludeInventory(msg.config.destination)
    end

    rednet.send(senderId, {
        type = "config_ack",
        serverId = os.getComputerID(),
    })
end

local function handleHeartbeat(senderId, msg)
    if _clients[senderId] then
        _clients[senderId].lastSeen = os.epoch("utc")
    end
end

local function handleQueryStock(senderId, msg)
    local items = _storage.getItems()
    local result = {}
    for _, item in ipairs(items) do
        local include = true
        if msg.filter then
            if not item.name:find(msg.filter, 1, true) and
               not item.displayName:lower():find(msg.filter:lower(), 1, true) then
                include = false
            end
        end
        if include then
            table.insert(result, {
                name = item.name,
                displayName = item.displayName,
                count = item.count,
                nbt = item.nbt,
            })
        end
    end
    rednet.send(senderId, {
        type = "stock_update",
        items = result,
    })
end

local function handleRequestItems(senderId, msg)
    local itemName = msg.item
    local count = msg.count or 1
    local destination = msg.destination

    local item = findItem(itemName)
    local delivered = 0
    if item then
        delivered = _storage.extract(item.key, count, destination)
    end

    rednet.send(senderId, {
        type = "items_delivered",
        item = itemName,
        requested = count,
        delivered = delivered,
    })
end

local function handleCraftRequest(senderId, msg)
    local itemName = msg.item
    local count = msg.count or 1

    local jobId = _crafting.requestCraft(itemName, count)

    rednet.send(senderId, {
        type = "craft_status",
        jobId = jobId,
        status = "queued",
    })
end

local function handleLocateItems(senderId, msg)
    local itemName = msg.item
    local count = msg.count or 1

    local item = findItem(itemName)

    if not item then
        rednet.send(senderId, {
            type = "item_sources",
            item = itemName,
            sources = {},
            available = 0,
        })
        return
    end

    local sources = {}
    local remaining = count
    for _, source in ipairs(item.sources) do
        if remaining <= 0 then break end
        local take = math.min(remaining, source.count)
        table.insert(sources, {
            inv = source.inv,
            slot = source.slot,
            count = take,
        })
        remaining = remaining - take
    end

    rednet.send(senderId, {
        type = "item_sources",
        item = itemName,
        sources = sources,
        available = item.count,
    })
end

local function handleMessage(senderId, msg)
    if type(msg) ~= "table" or not msg.type then return end

    if msg.type == "register" then
        handleRegister(senderId, msg)
    elseif msg.type == "heartbeat" then
        handleHeartbeat(senderId, msg)
    elseif msg.type == "query_stock" then
        handleQueryStock(senderId, msg)
    elseif msg.type == "request_items" then
        handleRequestItems(senderId, msg)
    elseif msg.type == "locate_items" then
        handleLocateItems(senderId, msg)
    elseif msg.type == "craft_request" then
        handleCraftRequest(senderId, msg)
    end
end

function server.broadcastUpdate()
    local count = 0
    for clientId, _ in pairs(_clients) do
        rednet.send(clientId, {
            type = "do_update",
        })
        count = count + 1
    end
    return count
end

function server.getClients()
    local list = {}
    for id, client in pairs(_clients) do
        table.insert(list, {
            id = id,
            blockType = client.blockType,
            version = client.version,
            lastSeen = client.lastSeen,
        })
    end
    return list
end

function server.loop()
    _modemSide = findModem()
    if not _modemSide then
        return
    end

    rednet.open(_modemSide)
    rednet.host(PROTOCOL, HOST)

    while true do
        local senderId, message = rednet.receive()
        if senderId and type(message) == "table" and message.type then
            handleMessage(senderId, message)
        end
    end
end

return server
