local logistics = {}

local _core = nil
local _storage = nil
local _config = nil
local _crafting = nil

function logistics.init(core, storage, config)
    _core = core
    _storage = storage
    _config = config
end

function logistics.setCrafting(crafting)
    _crafting = crafting
end

local function findItemKey(itemName)
    local items = _storage.getItems()
    for _, item in ipairs(items) do
        if item.name == itemName then
            return item.key
        end
    end
    if not itemName:find(":") then
        for _, item in ipairs(items) do
            if item.name == "minecraft:" .. itemName then
                return item.key
            end
        end
        for _, item in ipairs(items) do
            if item.name:match(":(.+)") == itemName then
                return item.key
            end
        end
    end
    return nil
end

function logistics.request(itemName, count, toInv)
    local key = findItemKey(itemName)
    if not key then
        _core.event.emit("logistics:request_complete", itemName, 0, count)
        return 0
    end

    local extracted = _storage.extract(key, count, toInv)
    _core.event.emit("logistics:request_complete", itemName, extracted, count)
    return extracted
end

function logistics.loop()
    while true do
        sleep(_config.get("logistics.interval") or 10)
    end
end

return logistics
