local storage = {}

local _core = nil
local _config = nil
local _items = {}
local _itemsByKey = {}
local _detailCache = {}
local _activity = {}
local _activityMax = 100
local _inventoryCount = 0
local _totalSlots = 0
local _usedSlots = 0
local _lastScanMs = 0
local _excludedInvs = {}
local _recentExtracts = {}

function storage.init(core, config)
    _core = core
    _config = config
end

function storage.excludeInventory(name)
    _excludedInvs[name] = true
end

local function isExcluded(name)
    if _excludedInvs[name] then return true end
    local excludes = _config.get("storage.excludes")
    if type(excludes) == "table" then
        for _, pattern in ipairs(excludes) do
            if name:find(pattern, 1, true) then return true end
        end
    end
    return false
end

local function shouldScan(name)
    local includes = _config.get("storage.includes")
    if type(includes) == "table" then
        for _, pattern in ipairs(includes) do
            if name:find(pattern, 1, true) then return true end
        end
        return false
    end
    return not isExcluded(name)
end

local function getInventories()
    local all = _core.findInventories("inventory")
    local result = {}
    for _, name in ipairs(all) do
        if shouldScan(name) then
            table.insert(result, name)
        end
    end
    return result
end

local function enrichItem(invName, slot, basicItem)
    local key = _core.itemKey(basicItem.name, basicItem.nbt)
    if _detailCache[key] then
        return _detailCache[key]
    end

    local ok, detail = pcall(peripheral.call, invName, "getItemDetail", slot)
    local enriched = {
        name = basicItem.name,
        displayName = basicItem.name,
        nbt = basicItem.nbt,
    }

    if ok and detail then
        enriched.displayName = detail.displayName or basicItem.name
        enriched.enchantments = detail.enchantments
        enriched.damage = detail.damage
        enriched.maxDamage = detail.maxDamage
        enriched.tags = detail.tags

        if basicItem.nbt and detail.displayName then
            local baseKey = _core.itemKey(basicItem.name, nil)
            local baseDetail = _detailCache[baseKey]
            if baseDetail and baseDetail.displayName ~= detail.displayName then
                enriched.customName = detail.displayName
                enriched.baseName = basicItem.name
            end
        end
    end

    _detailCache[key] = enriched
    return enriched
end

local function addActivity(action, itemName, count)
    table.insert(_activity, 1, {
        action = action,
        item = itemName,
        count = count,
        timestamp = os.epoch("utc"),
    })
    while #_activity > _activityMax do
        table.remove(_activity)
    end
end

local function computeDelta(oldByKey, newByKey)
    local added = {}
    local removed = {}
    local changed = {}

    for key, newItem in pairs(newByKey) do
        local oldItem = oldByKey[key]
        if not oldItem then
            table.insert(added, { key = key, displayName = newItem.displayName, count = newItem.count })
        elseif oldItem.count ~= newItem.count then
            local diff = newItem.count - oldItem.count
            table.insert(changed, { key = key, displayName = newItem.displayName, count = newItem.count, diff = diff })
        end
    end

    for key, oldItem in pairs(oldByKey) do
        if not newByKey[key] then
            table.insert(removed, { key = key, displayName = oldItem.displayName, count = oldItem.count })
        end
    end

    return { added = added, removed = removed, changed = changed }
end

function storage.scan()
    local startTime = os.epoch("utc")
    local inventories = getInventories()

    _inventoryCount = #inventories
    _totalSlots = 0
    _usedSlots = 0

    local newItemsByKey = {}

    for _, invName in ipairs(inventories) do
        local okSize, size = pcall(peripheral.call, invName, "size")
        if okSize and size then
            _totalSlots = _totalSlots + size
        end

        local okList, contents = pcall(peripheral.call, invName, "list")
        if okList and contents then
            for slot, basicItem in pairs(contents) do
                _usedSlots = _usedSlots + 1
                local key = _core.itemKey(basicItem.name, basicItem.nbt)
                local detail = enrichItem(invName, slot, basicItem)

                if not newItemsByKey[key] then
                    newItemsByKey[key] = {
                        key = key,
                        name = detail.name,
                        displayName = detail.displayName,
                        count = 0,
                        nbt = basicItem.nbt,
                        enchantments = detail.enchantments,
                        customName = detail.customName,
                        baseName = detail.baseName,
                        damage = detail.damage,
                        maxDamage = detail.maxDamage,
                        tags = detail.tags,
                        sources = {},
                    }
                end

                newItemsByKey[key].count = newItemsByKey[key].count + basicItem.count
                table.insert(newItemsByKey[key].sources, {
                    inv = invName,
                    slot = slot,
                    count = basicItem.count,
                })
            end
        end
    end

    local delta = computeDelta(_itemsByKey, newItemsByKey)
    _itemsByKey = newItemsByKey

    _items = {}
    for _, item in pairs(_itemsByKey) do
        table.insert(_items, item)
    end
    table.sort(_items, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.displayName < b.displayName
    end)

    for _, entry in ipairs(delta.added) do
        addActivity("add", entry.displayName, entry.count)
    end
    for _, entry in ipairs(delta.removed) do
        if not _recentExtracts[entry.key] then
            addActivity("remove", entry.displayName, entry.count)
        end
    end
    for _, entry in ipairs(delta.changed) do
        if _recentExtracts[entry.key] then
            _recentExtracts[entry.key] = nil
        end
    end
    _recentExtracts = {}

    _lastScanMs = os.epoch("utc") - startTime

    _core.event.emit("storage:scanned")
    if #delta.added > 0 or #delta.removed > 0 or #delta.changed > 0 then
        _core.event.emit("storage:changed", delta)
    end

    return _items
end

function storage.getItems()
    return _items
end

function storage.getItem(key)
    return _itemsByKey[key]
end

function storage.extract(key, count, toInv)
    local item = _itemsByKey[key]
    if not item then return 0 end

    local remaining = count
    local extracted = 0

    for _, source in ipairs(item.sources) do
        if remaining <= 0 then break end
        local moved = _core.move(source.inv, source.slot, toInv, math.min(remaining, source.count))
        remaining = remaining - moved
        extracted = extracted + moved
    end

    if extracted > 0 then
        addActivity("extract", item.displayName, extracted)
        _recentExtracts[key] = true
    end

    return extracted
end

function storage.insert(fromInv, fromSlot, count)
    local destinations = getInventories()
    local remaining = count

    for _, destInv in ipairs(destinations) do
        if remaining <= 0 then break end
        local ok, transferred = pcall(
            peripheral.call, destInv, "pullItems",
            fromInv, fromSlot, remaining
        )
        if ok and transferred and transferred > 0 then
            remaining = remaining - transferred
        end
    end

    return count - remaining
end

function storage.getActivity()
    return _activity
end

function storage.getStatus()
    return {
        inventories = _inventoryCount,
        totalSlots = _totalSlots,
        usedSlots = _usedSlots,
        uniqueTypes = #_items,
        lastScanMs = _lastScanMs,
    }
end

function storage.loop()
    while true do
        storage.scan()
        sleep(_config.get("storage.scanInterval") or 5)
    end
end

return storage
