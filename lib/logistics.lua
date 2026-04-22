local logistics = {}

local _core = nil
local _storage = nil
local _config = nil
local _crafting = nil
local _rules = {}
local _ruleCounter = 0
local _requests = {}
local _requestCounter = 0

function logistics.init(core, storage, config)
    _core = core
    _storage = storage
    _config = config

    local saved = _config.get("logistics.rules")
    if type(saved) == "table" then
        for _, rule in ipairs(saved) do
            _ruleCounter = _ruleCounter + 1
            rule.id = rule.id or tostring(_ruleCounter)
            _rules[rule.id] = rule
        end
    end
end

function logistics.setCrafting(crafting)
    _crafting = crafting
end

local function saveRules()
    local list = {}
    for _, rule in pairs(_rules) do
        table.insert(list, rule)
    end
    _config.set("logistics.rules", list)
end

function logistics.addRule(rule)
    _ruleCounter = _ruleCounter + 1
    local id = tostring(_ruleCounter)
    rule.id = id
    rule.priority = rule.priority or 0
    _rules[id] = rule
    saveRules()
    return id
end

function logistics.removeRule(id)
    _rules[id] = nil
    saveRules()
end

function logistics.editRule(id, changes)
    local rule = _rules[id]
    if not rule then return false end
    for k, v in pairs(changes) do
        rule[k] = v
    end
    saveRules()
    return true
end

function logistics.getRules()
    local list = {}
    for _, rule in pairs(_rules) do
        table.insert(list, {
            id = rule.id,
            item = rule.item,
            target = rule.target,
            destination = rule.destination,
            priority = rule.priority,
            status = rule._status or "pending",
            current = rule._current or 0,
        })
    end
    table.sort(list, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
    return list
end

function logistics.request(itemName, count, toInv)
    _requestCounter = _requestCounter + 1
    local id = tostring(_requestCounter)

    local items = _storage.getItems()
    local targetKey = nil
    for _, item in ipairs(items) do
        if item.name == itemName then
            targetKey = item.key
            break
        end
    end

    if not targetKey then
        _core.event.emit("logistics:request_complete", id, itemName, 0, count)
        return id, 0
    end

    local extracted = _storage.extract(targetKey, count, toInv)
    _core.event.emit("logistics:request_complete", id, itemName, extracted, count)
    return id, extracted
end

local function countItemInInventory(invName, itemName)
    local total = 0
    local ok, contents = pcall(peripheral.call, invName, "list")
    if ok and contents then
        for _, slot in pairs(contents) do
            if slot.name == itemName then
                total = total + slot.count
            end
        end
    end
    return total
end

local function findItemKey(itemName)
    local items = _storage.getItems()
    for _, item in ipairs(items) do
        if item.name == itemName then
            return item.key
        end
    end
    return nil
end

local function fulfillRules()
    local sorted = {}
    for _, rule in pairs(_rules) do
        table.insert(sorted, rule)
    end
    table.sort(sorted, function(a, b) return (a.priority or 0) > (b.priority or 0) end)

    for _, rule in ipairs(sorted) do
        local current = countItemInInventory(rule.destination, rule.item)
        rule._current = current

        if current >= rule.target then
            rule._status = "fulfilled"
            _core.event.emit("logistics:fulfilled", rule.id, rule.item)
        else
            local deficit = rule.target - current
            local key = findItemKey(rule.item)

            if key then
                local extracted = _storage.extract(key, deficit, rule.destination)
                if extracted >= deficit then
                    rule._status = "fulfilled"
                    _core.event.emit("logistics:fulfilled", rule.id, rule.item)
                else
                    rule._status = "short"
                    _core.event.emit("logistics:short", rule.id, rule.item, deficit - extracted)
                    if _crafting then
                        _crafting.requestCraft(rule.item, deficit - extracted)
                    end
                end
            else
                rule._status = "short"
                _core.event.emit("logistics:short", rule.id, rule.item, deficit)
                if _crafting then
                    _crafting.requestCraft(rule.item, deficit)
                end
            end
        end
    end
end

function logistics.loop()
    while true do
        fulfillRules()
        sleep(_config.get("logistics.interval") or 10)
    end
end

return logistics
