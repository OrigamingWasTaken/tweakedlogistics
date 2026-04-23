local cards = {}

local _config = nil

function cards.init(config)
    _config = config
end

function cards.create(diskId, cardData)
    local all = _config.get("cards") or {}
    all[tostring(diskId)] = cardData
    _config.set("cards", all)
end

function cards.get(diskId)
    local all = _config.get("cards") or {}
    return all[tostring(diskId)]
end

function cards.delete(diskId)
    local all = _config.get("cards") or {}
    all[tostring(diskId)] = nil
    _config.set("cards", all)
end

function cards.withdraw(diskId, itemName, count)
    local all = _config.get("cards") or {}
    local card = all[tostring(diskId)]
    if not card or not card.items then return 0 end

    local available = card.items[itemName] or 0
    local actual = math.min(available, count)
    if actual <= 0 then return 0 end

    card.items[itemName] = available - actual
    if card.items[itemName] <= 0 then
        card.items[itemName] = nil
    end

    _config.set("cards", all)
    return actual
end

function cards.recharge(diskId, itemName, count)
    local all = _config.get("cards") or {}
    local card = all[tostring(diskId)]
    if not card then return false end
    if not card.rechargeable then return false end

    if not card.items then card.items = {} end
    card.items[itemName] = (card.items[itemName] or 0) + count
    _config.set("cards", all)
    return true
end

function cards.getAll()
    return _config.get("cards") or {}
end

return cards
