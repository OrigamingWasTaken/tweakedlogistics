local nicknames = {}

local _config = nil

function nicknames.init(config)
    _config = config
end

function nicknames.set(invName, label)
    local all = _config.get("nicknames") or {}
    all[invName] = label
    _config.set("nicknames", all)
end

function nicknames.get(invName)
    local all = _config.get("nicknames") or {}
    return all[invName]
end

function nicknames.remove(invName)
    local all = _config.get("nicknames") or {}
    all[invName] = nil
    _config.set("nicknames", all)
end

function nicknames.getDisplay(invName)
    local label = nicknames.get(invName)
    if label then
        return label
    end
    return invName
end

function nicknames.getAll()
    return _config.get("nicknames") or {}
end

return nicknames
