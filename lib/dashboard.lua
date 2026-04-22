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

-- Panels --

local function panelStockOverview(mon, w, h)
    header(mon, w, " Stock Overview", colors.blue, colors.gray)

    local items = _storage.getItems()
    local maxRows = h - 2

    if #items == 0 then
        text(mon, 2, 3, "No items found", colors.lightGray, colors.black)
        return
    end

    for i = 1, math.min(#items, maxRows) do
        local item = items[i]
        local row = i + 1
        local bg = i % 2 == 0 and colors.gray or colors.black

        local countStr = formatCount(item.count)
        local nameW = w - #countStr - 4
        local name = item.displayName
        if #name > nameW then
            name = name:sub(1, nameW - 2) .. ".."
        end

        box(mon, 1, row, w, 1, bg)
        text(mon, 2, row, name, colors.white, bg)
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

-- Init and loop --

function dashboard.init(core, storage, logistics, crafting, config)
    _core = core
    _storage = storage
    _logistics = logistics
    _crafting = crafting
    _config = config
end

local function renderPanel(mon, panelId)
    local w, h = mon.getSize()
    applyPalette(mon)
    clear(mon)

    local panelFn = PANEL_REGISTRY[panelId]
    if panelFn then
        panelFn(mon, w, h)
    else
        text(mon, 2, 2, "Unknown panel:", colors.red, colors.black)
        text(mon, 2, 3, panelId or "nil", colors.white, colors.black)
    end
end

function dashboard.loop()
    while true do
        local panelConfig = _config.get("dashboard.panels") or {}
        local monitors = _core.findInventories("monitor")

        if next(panelConfig) == nil then
            for _, monName in ipairs(monitors) do
                panelConfig[monName] = "stock_overview"
            end
        end

        for monName, panelId in pairs(panelConfig) do
            local mon = peripheral.wrap(monName)
            if mon then
                mon.setTextScale(0.5)
                local ok, err = pcall(renderPanel, mon, panelId)
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

        sleep(_config.get("dashboard.interval") or 1)
    end
end

return dashboard
