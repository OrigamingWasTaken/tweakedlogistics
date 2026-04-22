local core = {}

-- Config --

function core.config(path)
    local cfg = {}
    local _data = {}
    local _path = path

    function cfg.load()
        if fs.exists(_path) then
            local h = fs.open(_path, "r")
            if h then
                local content = h.readAll()
                h.close()
                local loaded = textutils.unserialize(content)
                if type(loaded) == "table" then
                    _data = loaded
                end
            end
        end
    end

    function cfg.save()
        local h = fs.open(_path, "w")
        if h then
            h.write(textutils.serialize(_data))
            h.close()
        end
    end

    function cfg.get(key)
        return _data[key]
    end

    function cfg.set(key, value)
        _data[key] = value
        cfg.save()
    end

    function cfg.getAll()
        local copy = {}
        for k, v in pairs(_data) do
            copy[k] = v
        end
        return copy
    end

    function cfg.setMany(tbl)
        for k, v in pairs(tbl) do
            _data[k] = v
        end
        cfg.save()
    end

    cfg.load()
    return cfg
end

-- Event Bus --

local _listeners = {}

core.event = {}

function core.event.on(name, callback)
    if not _listeners[name] then
        _listeners[name] = {}
    end
    table.insert(_listeners[name], callback)
end

function core.event.off(name, callback)
    local list = _listeners[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
            return
        end
    end
end

function core.event.emit(name, ...)
    local list = _listeners[name]
    if not list then return end
    for _, cb in ipairs(list) do
        cb(...)
    end
end

-- Inventory Helpers --

function core.itemKey(name, nbt)
    return name .. "|" .. (nbt or "")
end

function core.move(fromInv, fromSlot, toInv, count)
    local ok, transferred = pcall(
        peripheral.call, toInv, "pullItems",
        fromInv, fromSlot, count
    )
    if ok then
        return transferred or 0
    end
    return 0
end

function core.findInventories(typeFilter)
    local result = {}
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.hasType(name, typeFilter or "inventory") then
            table.insert(result, name)
        end
    end
    return result
end

return core
