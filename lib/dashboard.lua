local dashboard = {}

local _core = nil
local _storage = nil
local _logistics = nil
local _crafting = nil
local _config = nil

-- Dark palette --

local function applyPalette(mon)
    mon.setPaletteColor(colors.black, 0x0f0f14)
    mon.setPaletteColor(colors.gray, 0x1a1b26)
    mon.setPaletteColor(colors.lightGray, 0x414868)
    mon.setPaletteColor(colors.blue, 0x7aa2f7)
    mon.setPaletteColor(colors.green, 0x73daca)
    mon.setPaletteColor(colors.red, 0xf7768e)
    mon.setPaletteColor(colors.purple, 0xbb9af7)
    mon.setPaletteColor(colors.orange, 0xff9e64)
    mon.setPaletteColor(colors.yellow, 0xe0af68)
    mon.setPaletteColor(colors.white, 0xa9b1d6)
    mon.setPaletteColor(colors.cyan, 0x7dcfff)
    mon.setPaletteColor(colors.lightBlue, 0x89ddff)
    mon.setPaletteColor(colors.lime, 0x9ece6a)
end

-- Draw primitives --

local function clear(mon)
    mon.setBackgroundColor(colors.black)
    mon.clear()
end

local function box(mon, x, y, w, h, bg)
    mon.setBackgroundColor(bg)
    for row = y, y + h - 1 do
        mon.setCursorPos(x, row)
        mon.write(string.rep(" ", w))
    end
end

local function text(mon, x, y, str, fg, bg)
    mon.setCursorPos(x, y)
    if bg then mon.setBackgroundColor(bg) end
    if fg then mon.setTextColor(fg) end
    mon.write(str)
end

local function textRight(mon, x, y, w, str, fg, bg)
    local px = x + w - #str
    text(mon, px, y, str, fg, bg)
end

local function header(mon, w, title, fg, bg)
    box(mon, 1, 1, w, 1, bg or colors.gray)
    text(mon, 2, 1, title, fg or colors.blue, bg or colors.gray)
end

local function progressBar(mon, x, y, w, value, max, fg, bg)
    if max <= 0 then max = 1 end
    local filled = math.floor((value / max) * w + 0.5)
    if filled > w then filled = w end
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(fg or colors.green)
    mon.write(string.rep(" ", filled))
    mon.setBackgroundColor(bg or colors.lightGray)
    mon.write(string.rep(" ", w - filled))
end

local function formatCount(n)
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end

-- Rarity --

local EPIC_ITEMS = {
    ["minecraft:mace"] = true,
    ["minecraft:dragon_egg"] = true,
    ["minecraft:end_crystal"] = true,
    ["minecraft:command_block"] = true,
    ["minecraft:chain_command_block"] = true,
    ["minecraft:repeating_command_block"] = true,
}

local UNCOMMON_ITEMS = {
    ["minecraft:golden_apple"] = true,
    ["minecraft:experience_bottle"] = true,
    ["minecraft:dragon_breath"] = true,
    ["minecraft:nautilus_shell"] = true,
    ["minecraft:heart_of_the_sea"] = true,
    ["minecraft:music_disc_13"] = true,
    ["minecraft:music_disc_cat"] = true,
    ["minecraft:music_disc_blocks"] = true,
    ["minecraft:music_disc_chirp"] = true,
    ["minecraft:music_disc_far"] = true,
    ["minecraft:music_disc_mall"] = true,
    ["minecraft:music_disc_mellohi"] = true,
    ["minecraft:music_disc_stal"] = true,
    ["minecraft:music_disc_strad"] = true,
    ["minecraft:music_disc_ward"] = true,
    ["minecraft:music_disc_11"] = true,
    ["minecraft:music_disc_wait"] = true,
    ["minecraft:music_disc_pigstep"] = true,
    ["minecraft:music_disc_otherside"] = true,
    ["minecraft:music_disc_5"] = true,
    ["minecraft:music_disc_relic"] = true,
}

local RARE_ITEMS = {
    ["minecraft:nether_star"] = true,
    ["minecraft:elytra"] = true,
    ["minecraft:trident"] = true,
    ["minecraft:totem_of_undying"] = true,
    ["minecraft:enchanted_golden_apple"] = true,
}

local function getItemRarity(item)
    if EPIC_ITEMS[item.name] then return "epic" end
    if RARE_ITEMS[item.name] then return "rare" end

    local baseRarity = "common"
    if UNCOMMON_ITEMS[item.name] then baseRarity = "uncommon" end

    if item.enchantments and #item.enchantments > 0 then
        if baseRarity == "common" or baseRarity == "uncommon" then
            return "rare"
        end
    end

    return baseRarity
end

local function getRarityColor(rarity)
    if rarity == "epic" then return colors.purple end
    if rarity == "rare" then return colors.cyan end
    if rarity == "uncommon" then return colors.yellow end
    return colors.white
end

-- Panels --

local function drawItemName(mon, x, y, w, item, bg)
    local rarity = getItemRarity(item)
    local nameColor = getRarityColor(rarity)
    local isRenamed = item.customName ~= nil

    if isRenamed then
        nameColor = colors.lightGray
    end

    local name = item.displayName
    local suffix = ""
    if isRenamed and item.baseName then
        local realName = item.baseName:match(":(.+)") or item.baseName
        realName = realName:gsub("_", " ")
        suffix = " (" .. realName .. ")"
    end

    local maxNameLen = w - #suffix
    if #name > maxNameLen then
        name = name:sub(1, maxNameLen - 2) .. ".."
        suffix = ""
    end

    text(mon, x, y, name, nameColor, bg)
    if #suffix > 0 then
        text(mon, x + #name, y, suffix, colors.lightGray, bg)
    end
end

local _rowItems = {}

local function panelStockOverview(mon, w, h, monName)
    header(mon, w, " Stock Overview", colors.blue, colors.gray)

    local items = _storage.getItems()
    local maxRows = h - 2
    _rowItems[monName] = {}

    if #items == 0 then
        text(mon, 2, 3, "No items found", colors.lightGray, colors.black)
        return
    end

    for i = 1, math.min(#items, maxRows) do
        local item = items[i]
        local row = i + 1
        local bg = i % 2 == 0 and colors.gray or colors.black

        _rowItems[monName][row] = item

        local countStr = formatCount(item.count)
        local nameW = w - #countStr - 4

        box(mon, 1, row, w, 1, bg)
        drawItemName(mon, 2, row, nameW, item, bg)
        textRight(mon, 1, row, w - 1, countStr, colors.cyan, bg)
    end
end

local function panelRuleStatus(mon, w, h)
    header(mon, w, " Rule Status", colors.purple, colors.gray)

    if not _logistics then
        text(mon, 2, 3, "Logistics not loaded", colors.lightGray, colors.black)
        return
    end

    local rules = _logistics.getRules()
    local maxRows = h - 2

    if #rules == 0 then
        text(mon, 2, 3, "No rules defined", colors.lightGray, colors.black)
        return
    end

    for i = 1, math.min(#rules, maxRows) do
        local rule = rules[i]
        local row = i + 1
        local bg = i % 2 == 0 and colors.gray or colors.black

        local statusColor = colors.yellow
        if rule.status == "fulfilled" then statusColor = colors.green
        elseif rule.status == "short" then statusColor = colors.red end

        local countStr = formatCount(rule.current) .. "/" .. formatCount(rule.target)
        local nameW = w - #countStr - 4
        local name = rule.item:match(":(.+)") or rule.item
        if #name > nameW then
            name = name:sub(1, nameW - 2) .. ".."
        end

        box(mon, 1, row, w, 1, bg)
        text(mon, 2, row, name, statusColor, bg)
        textRight(mon, 1, row, w - 1, countStr, colors.lightGray, bg)
    end
end

local function panelCraftingJobs(mon, w, h)
    header(mon, w, " Crafting Jobs", colors.orange, colors.gray)

    if not _crafting then
        text(mon, 2, 3, "Crafting not loaded", colors.lightGray, colors.black)
        return
    end

    local jobs = _crafting.getJobs()
    local maxRows = h - 2

    if #jobs == 0 then
        text(mon, 2, 3, "No active jobs", colors.lightGray, colors.black)
        return
    end

    for i = 1, math.min(#jobs, maxRows) do
        local job = jobs[i]
        local row = i + 1
        local bg = i % 2 == 0 and colors.gray or colors.black

        local statusColor = colors.yellow
        if job.status == "complete" then statusColor = colors.green
        elseif job.status == "failed" then statusColor = colors.red
        elseif job.status == "processing" then statusColor = colors.orange end

        local name = job.item:match(":(.+)") or job.item
        local info = formatCount(job.count) .. " " .. job.status
        local nameW = w - #info - 4
        if #name > nameW then
            name = name:sub(1, nameW - 2) .. ".."
        end

        box(mon, 1, row, w, 1, bg)
        text(mon, 2, row, name, colors.white, bg)
        textRight(mon, 1, row, w - 1, info, statusColor, bg)
    end
end

local function panelProcessorStatus(mon, w, h)
    header(mon, w, " Processors", colors.lime, colors.gray)

    if not _crafting then
        text(mon, 2, 3, "Crafting not loaded", colors.lightGray, colors.black)
        return
    end

    local procs = _crafting.getProcessors()
    local maxRows = h - 2

    if #procs == 0 then
        text(mon, 2, 3, "No processors", colors.lightGray, colors.black)
        return
    end

    for i = 1, math.min(#procs, maxRows) do
        local proc = procs[i]
        local row = i + 1
        local bg = i % 2 == 0 and colors.gray or colors.black

        local statusStr = proc.busy and "BUSY" or "IDLE"
        local statusColor = proc.busy and colors.orange or colors.green

        local name = proc.type or proc.id
        local nameW = w - #statusStr - 4
        if #name > nameW then
            name = name:sub(1, nameW - 2) .. ".."
        end

        box(mon, 1, row, w, 1, bg)
        text(mon, 2, row, name, colors.white, bg)
        textRight(mon, 1, row, w - 1, statusStr, statusColor, bg)
    end
end

local function panelActivity(mon, w, h)
    header(mon, w, " Activity", colors.cyan, colors.gray)

    local activity = _storage.getActivity()
    local maxRows = h - 2

    if #activity == 0 then
        text(mon, 2, 3, "No activity yet", colors.lightGray, colors.black)
        return
    end

    for i = 1, math.min(#activity, maxRows) do
        local entry = activity[i]
        local row = i + 1
        local bg = i % 2 == 0 and colors.gray or colors.black

        local icon, iconColor
        if entry.action == "add" then
            icon = "+"
            iconColor = colors.green
        elseif entry.action == "remove" or entry.action == "extract" then
            icon = "-"
            iconColor = colors.red
        else
            icon = "?"
            iconColor = colors.yellow
        end

        local countStr = formatCount(entry.count)
        local nameW = w - #countStr - 5
        local name = entry.item or "?"
        if #name > nameW then
            name = name:sub(1, nameW - 2) .. ".."
        end

        box(mon, 1, row, w, 1, bg)
        text(mon, 2, row, icon, iconColor, bg)
        text(mon, 4, row, name, colors.white, bg)
        textRight(mon, 1, row, w - 1, countStr, colors.lightBlue, bg)
    end
end

local PANEL_REGISTRY = {
    stock_overview = panelStockOverview,
    rule_status = panelRuleStatus,
    crafting_jobs = panelCraftingJobs,
    processor_status = panelProcessorStatus,
    activity = panelActivity,
}

-- Item Detail Modal --

local _modalItem = {}
local _modalClose = {}

local function drawModal(mon, w, h, item, monName)
    local modalW = math.min(w - 4, 40)
    local modalH = math.min(h - 4, 16)
    local mx = math.floor((w - modalW) / 2) + 1
    local my = math.floor((h - modalH) / 2) + 1

    box(mon, mx, my, modalW, modalH, colors.gray)
    box(mon, mx, my, modalW, 1, colors.blue)

    local rarity = getItemRarity(item)
    local nameColor = getRarityColor(rarity)
    if item.customName then nameColor = colors.lightGray end

    local title = item.displayName
    if #title > modalW - 5 then
        title = title:sub(1, modalW - 7) .. ".."
    end
    text(mon, mx + 1, my, title, nameColor, colors.blue)

    local closeX = mx + modalW - 2
    text(mon, closeX, my, "X", colors.red, colors.blue)
    _modalClose[monName] = { x1 = closeX, y = my }

    local row = my + 2
    local contentW = modalW - 2

    text(mon, mx + 1, row, item.name, colors.lightGray, colors.gray)
    row = row + 1

    if item.customName and item.baseName then
        local realName = item.baseName:match(":(.+)") or item.baseName
        text(mon, mx + 1, row, "Base: " .. realName:gsub("_", " "), colors.lightGray, colors.gray)
        row = row + 1
    end

    row = row + 1
    text(mon, mx + 1, row, "Count: ", colors.lightGray, colors.gray)
    text(mon, mx + 8, row, tostring(item.count), colors.white, colors.gray)
    row = row + 1

    local rarityLabel = rarity:sub(1, 1):upper() .. rarity:sub(2)
    text(mon, mx + 1, row, "Rarity: ", colors.lightGray, colors.gray)
    text(mon, mx + 9, row, rarityLabel, getRarityColor(rarity), colors.gray)
    row = row + 1

    if item.enchantments and #item.enchantments > 0 then
        row = row + 1
        text(mon, mx + 1, row, "Enchantments:", colors.cyan, colors.gray)
        row = row + 1
        for _, ench in ipairs(item.enchantments) do
            if row >= my + modalH - 1 then break end
            local enchName = ench.displayName or ench.name or "?"
            if type(enchName) == "string" then
                if #enchName > contentW - 2 then
                    enchName = enchName:sub(1, contentW - 4) .. ".."
                end
                text(mon, mx + 2, row, enchName, colors.lightBlue, colors.gray)
                row = row + 1
            end
        end
    end

    if item.damage and item.maxDamage and item.maxDamage > 0 then
        if row < my + modalH - 1 then
            row = row + 1
            local durability = item.maxDamage - item.damage
            local pct = math.floor(durability / item.maxDamage * 100)
            text(mon, mx + 1, row, "Durability: ", colors.lightGray, colors.gray)
            local durColor = colors.green
            if pct < 25 then durColor = colors.red
            elseif pct < 50 then durColor = colors.yellow end
            text(mon, mx + 13, row, durability .. "/" .. item.maxDamage .. " (" .. pct .. "%)", durColor, colors.gray)
        end
    end

    if item.tags and row < my + modalH - 2 then
        row = row + 1
        local tagCount = 0
        for _ in pairs(item.tags) do tagCount = tagCount + 1 end
        if tagCount > 0 then
            text(mon, mx + 1, row, "Tags: " .. tagCount, colors.lightGray, colors.gray)
        end
    end
end

-- Speaker --

local _speaker = nil

local function findSpeaker()
    for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
        if peripheral.hasType(side, "speaker") then
            _speaker = peripheral.wrap(side)
            return
        end
    end
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "speaker") then
            _speaker = peripheral.wrap(name)
            return
        end
    end
end

local function playClick()
    if not _speaker then return end
    pcall(_speaker.playSound, "minecraft:ui.button.click", 0.5, 1.0)
end

-- Init and loop --

function dashboard.init(core, storage, logistics, crafting, config)
    _core = core
    _storage = storage
    _logistics = logistics
    _crafting = crafting
    _config = config
    findSpeaker()
end

local function findMonitors()
    local result = {}
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "monitor") then
            table.insert(result, name)
        end
    end
    return result
end

local function renderPanel(mon, panelId, monName)
    local w, h = mon.getSize()
    applyPalette(mon)
    clear(mon)

    local panelFn = PANEL_REGISTRY[panelId]
    if panelFn then
        panelFn(mon, w, h, monName)
    else
        text(mon, 2, 2, "Unknown panel:", colors.red, colors.black)
        text(mon, 2, 3, panelId or "nil", colors.white, colors.black)
    end

    if _modalItem[monName] then
        drawModal(mon, w, h, _modalItem[monName], monName)
    end
end

local function renderAll()
    local panelConfig = _config.get("dashboard.panels") or {}
    local monitors = findMonitors()

    if next(panelConfig) == nil then
        for _, monName in ipairs(monitors) do
            panelConfig[monName] = "stock_overview"
        end
    end

    for monName, panelId in pairs(panelConfig) do
        local mon = peripheral.wrap(monName)
        if mon then
            mon.setTextScale(0.5)
            local ok, err = pcall(renderPanel, mon, panelId, monName)
            if not ok then
                pcall(function()
                    mon.setBackgroundColor(colors.black)
                    mon.setTextColor(colors.red)
                    mon.clear()
                    mon.setCursorPos(1, 1)
                    mon.write("Panel error:")
                    mon.setCursorPos(1, 2)
                    mon.write(tostring(err):sub(1, 30))
                end)
            end
        end
    end
end

local function handleTouch(monName, tx, ty)
    if _modalItem[monName] then
        local close = _modalClose[monName]
        if close and tx >= close.x1 and ty == close.y then
            _modalItem[monName] = nil
            _modalClose[monName] = nil
            playClick()
            renderAll()
        end
        return
    end

    local rows = _rowItems[monName]
    if rows and rows[ty] then
        _modalItem[monName] = rows[ty]
        playClick()
        renderAll()
    end
end

function dashboard.loop()
    renderAll()

    local needsRedraw = false

    _core.event.on("storage:changed", function()
        needsRedraw = true
    end)

    while true do
        local timerId = os.startTimer(_config.get("dashboard.interval") or 1)

        while true do
            local event, p1, p2, p3 = os.pullEvent()

            if event == "timer" and p1 == timerId then
                break
            elseif event == "monitor_touch" then
                handleTouch(p1, p2, p3)
            end
        end

        for monName, item in pairs(_modalItem) do
            local fresh = _storage.getItem(item.key)
            if fresh then
                _modalItem[monName] = fresh
            end
        end

        renderAll()
        needsRedraw = false
    end
end

-- Panel configuration helpers --

function dashboard.getPanelTypes()
    local list = {}
    for name, _ in pairs(PANEL_REGISTRY) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

return dashboard
