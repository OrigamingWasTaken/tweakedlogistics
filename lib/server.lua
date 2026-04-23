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
local _pending = {}
local _cards = nil

function server.init(core, storage, logistics, crafting, nicknames, cards, config)
    _core = core
    _storage = storage
    _logistics = logistics
    _crafting = crafting
    _nicknames = nicknames
    _cards = cards
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
        if _core.matchesItem(item.name, itemName) then return item end
    end
    return nil
end

local function handleRegister(senderId, msg)
    local whitelist = _config.get("whitelist") or {}
    local isApproved = whitelist[tostring(senderId)]

    if isApproved == nil and next(whitelist) == nil then
        isApproved = true
        whitelist[tostring(senderId)] = true
        _config.set("whitelist", whitelist)
    end

    if not isApproved then
        _pending[senderId] = {
            blockType = msg.blockType,
            computerId = msg.computerId,
            config = msg.config,
            version = msg.version,
            requestedAt = os.epoch("utc"),
        }
        rednet.send(senderId, { type = "pending" })
        return
    end

    local existing = _clients[senderId]
    _clients[senderId] = {
        blockType = msg.blockType,
        computerId = msg.computerId,
        config = msg.config,
        version = msg.version,
        status = msg.status,
        lastSeen = os.epoch("utc"),
        firstSeen = existing and existing.firstSeen or os.epoch("utc"),
        requestCount = existing and existing.requestCount or 0,
        itemsMoved = existing and existing.itemsMoved or 0,
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

    if _clients[senderId] then
        _clients[senderId].requestCount = (_clients[senderId].requestCount or 0) + 1
    end

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

local function handleCardScan(senderId, msg)
    if not _cards then return end
    local card = _cards.get(msg.diskId)
    if not card then
        rednet.send(senderId, { type = "card_denied", reason = "Unknown card" })
        return
    end

    if card.type == "access" then
        local client = _clients[senderId]
        local zone = client and client.config and client.config.zone
        local granted = false
        if zone and card.zones then
            for _, z in ipairs(card.zones) do
                if z == zone then granted = true break end
            end
        end
        rednet.send(senderId, {
            type = "card_access",
            granted = granted,
            duration = 3,
            label = card.label,
        })

    elseif card.type == "redemption" or card.type == "balance" then
        rednet.send(senderId, {
            type = "card_data",
            cardType = card.type,
            label = card.label,
            items = card.items,
            rechargeable = card.rechargeable,
        })
    end
end

local function handleCardWithdraw(senderId, msg)
    if not _cards then return end
    local card = _cards.get(msg.diskId)
    if not card then
        rednet.send(senderId, { type = "card_denied", reason = "Unknown card" })
        return
    end

    local client = _clients[senderId]
    local outputChest = client and client.config and client.config.outputChest

    local actual = _cards.withdraw(msg.diskId, msg.item, msg.count)
    if actual > 0 and outputChest then
        local items = _storage.getItems()
        for _, it in ipairs(items) do
            if _core.matchesItem(it.name, msg.item) then
                _storage.extract(it.key, actual, outputChest)
                break
            end
        end
    end

    local updatedCard = _cards.get(msg.diskId)
    local isEmpty = true
    if updatedCard and updatedCard.items then
        for _, v in pairs(updatedCard.items) do
            if v > 0 then isEmpty = false break end
        end
    end

    if card.type == "redemption" and isEmpty then
        _cards.delete(msg.diskId)
    end

    rednet.send(senderId, {
        type = "card_delivered",
        item = msg.item,
        count = actual,
        remaining = updatedCard and updatedCard.items or {},
        reclaim = card.type == "redemption" and isEmpty,
    })
end

local function handleCardCreate(senderId, msg)
    if not _cards then return end
    _cards.create(msg.diskId, msg.cardData)
    rednet.send(senderId, { type = "card_created", diskId = msg.diskId })
end

local function handleCardRecharge(senderId, msg)
    if not _cards then return end
    local ok = _cards.recharge(msg.diskId, msg.item, msg.count)
    rednet.send(senderId, { type = "card_recharged", success = ok })
end

local function handleCardRevoke(senderId, msg)
    if not _cards then return end
    _cards.delete(msg.diskId)
    rednet.send(senderId, { type = "card_revoked", diskId = msg.diskId })
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
    elseif msg.type == "card_scan" then
        handleCardScan(senderId, msg)
    elseif msg.type == "card_withdraw" then
        handleCardWithdraw(senderId, msg)
    elseif msg.type == "card_create" then
        handleCardCreate(senderId, msg)
    elseif msg.type == "card_recharge" then
        handleCardRecharge(senderId, msg)
    elseif msg.type == "card_revoke" then
        handleCardRevoke(senderId, msg)
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

function server.broadcastReconnect()
    if not _modemSide then return 0 end
    rednet.broadcast({ type = "reconnect" })
    return true
end

function server.updateClient(clientId)
    rednet.send(clientId, { type = "do_update" })
end

function server.getPending()
    local list = {}
    for id, info in pairs(_pending) do
        table.insert(list, {
            id = id,
            blockType = info.blockType,
            requestedAt = info.requestedAt,
        })
    end
    return list
end

function server.approve(clientId)
    local whitelist = _config.get("whitelist") or {}
    whitelist[tostring(clientId)] = true
    _config.set("whitelist", whitelist)

    if _pending[clientId] then
        _pending[clientId] = nil
    end

    rednet.send(clientId, {
        type = "config_ack",
        serverId = os.getComputerID(),
    })
end

function server.revoke(clientId)
    local whitelist = _config.get("whitelist") or {}
    whitelist[tostring(clientId)] = nil
    _config.set("whitelist", whitelist)
    _clients[clientId] = nil

    rednet.send(clientId, { type = "revoked" })
end

function server.getClients()
    local list = {}
    local now = os.epoch("utc")
    for id, client in pairs(_clients) do
        local elapsed = now - (client.lastSeen or 0)
        table.insert(list, {
            id = id,
            blockType = client.blockType,
            version = client.version,
            config = client.config,
            status = client.status,
            lastSeen = client.lastSeen,
            firstSeen = client.firstSeen,
            requestCount = client.requestCount or 0,
            itemsMoved = client.itemsMoved or 0,
            online = elapsed < 60000,
        })
    end
    return list
end

function server.loop()
    _modemSide = findModem()
    if not _modemSide then
        while true do sleep(30) end
    end

    rednet.open(_modemSide)
    rednet.host(PROTOCOL, HOST)

    while true do
        local senderId, message = rednet.receive(nil, 2)
        if senderId and type(message) == "table" and message.type then
            handleMessage(senderId, message)
        end
    end
end

return server
