local vlib = dofile("/tweakedlogistics/virtual/lib.lua")
local rarity = dofile("/tweakedlogistics/lib/rarity.lua")

local CONFIG_PATH = "/virtual_storage_interface.config"
local BLOCK_TYPE = "virtual_storage_interface"

local _items = {}
local _filtered = {}
local _outputs = {}
local _outputNames = {}
local _selectedOutput = 1
local _searchText = ""
local _searchFocused = false
local _page = 1
local _extractingIdx = nil
local _extractCount = 1
local _typingCount = false

local function setup()
    vlib.loadConfig(CONFIG_PATH)
    if not vlib.setupScreen("Storage Interface") then return false end

    local cfg = vlib.getConfig()

    term.setTextColor(colors.white)
    print("")

    if not cfg.defaultOutput then
        print("Select default output chest:")
        cfg.defaultOutput = vlib.pickInventory()
    end

    vlib.saveConfig()

    local ok = vlib.register(BLOCK_TYPE, {
        outputChest = cfg.defaultOutput,
    })

    if ok then
        term.setTextColor(colors.green)
        print("Registered with server!")
    else
        term.setTextColor(colors.yellow)
        print("Server did not acknowledge, continuing anyway...")
    end

    sleep(1)
    return true
end

local function getItemsPerPage()
    local _, h = term.getSize()
    return h - 4
end

local function filterItems()
    _filtered = {}
    local query = _searchText:lower()
    for _, item in ipairs(_items) do
        if query == "" then
            table.insert(_filtered, item)
        else
            local name = (item.displayName or item.name or ""):lower()
            local id = (item.name or ""):lower()
            if name:find(query, 1, true) or id:find(query, 1, true) then
                table.insert(_filtered, item)
            end
        end
    end
    local maxPage = math.max(1, math.ceil(#_filtered / getItemsPerPage()))
    if _page > maxPage then _page = maxPage end
end

local function getSelectedOutputChest()
    if #_outputNames > 0 and _selectedOutput <= #_outputNames then
        return _outputs[_outputNames[_selectedOutput]]
    end
    local cfg = vlib.getConfig()
    return cfg.defaultOutput
end

local function getSelectedOutputName()
    if #_outputNames > 0 and _selectedOutput <= #_outputNames then
        return _outputNames[_selectedOutput]
    end
    return "Local"
end

local function draw()
    local w, h = term.getSize()
    local perPage = getItemsPerPage()
    local maxPage = math.max(1, math.ceil(#_filtered / perPage))

    term.setBackgroundColor(colors.black)
    term.clear()

    -- Search bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, 1)
    if _searchFocused then
        term.setTextColor(colors.yellow)
        term.write(" > " .. _searchText .. "_")
    elseif _searchText ~= "" then
        term.setTextColor(colors.white)
        term.write(" > " .. _searchText)
        term.setCursorPos(w - 2, 1)
        term.setTextColor(colors.red)
        term.write("[X]")
    else
        term.setTextColor(colors.lightGray)
        term.write(" Click to search...")
    end

    -- Output selector
    local outLabel = "[" .. getSelectedOutputName() .. "]"
    if not _searchFocused and _searchText == "" then
        term.setCursorPos(w - #outLabel, 1)
        term.setTextColor(colors.cyan)
        term.setBackgroundColor(colors.gray)
        term.write(outLabel)
    end

    -- Header line
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(string.rep("-", w))

    -- Item list
    local startIdx = ((_page - 1) * perPage) + 1
    for i = 0, perPage - 1 do
        local idx = startIdx + i
        local row = 3 + i
        local item = _filtered[idx]

        term.setCursorPos(1, row)
        term.setBackgroundColor(colors.black)

        if not item then
            term.write(string.rep(" ", w))
        elseif _extractingIdx == idx then
            -- Extract mode
            term.setTextColor(colors.white)
            local name = (item.displayName or item.name or "?")
            if #name > w - 30 then name = name:sub(1, w - 32) .. ".." end
            term.write(" " .. name .. " ")

            local countStr = tostring(_extractCount)
            local cx = w - 22
            term.setCursorPos(cx, row)
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
            term.write(" - ")
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.yellow)
            if _typingCount then
                term.write(" " .. countStr .. "_ ")
            else
                term.write(" " .. countStr .. " ")
            end
            term.setBackgroundColor(colors.green)
            term.setTextColor(colors.white)
            term.write(" + ")
            term.write(" OK ")
            term.setBackgroundColor(colors.red)
            term.write(" X ")
            term.setBackgroundColor(colors.black)
        else
            -- Normal row
            local nameColor = rarity.getItemColor(item)
            local name = item.displayName or item.name or "?"
            local countStr = "x" .. tostring(item.count or 0)
            local btnStr = "[>]"
            local nameW = w - #countStr - #btnStr - 4

            if #name > nameW then name = name:sub(1, nameW - 2) .. ".." end

            term.setTextColor(nameColor)
            term.write(" " .. name)
            term.setCursorPos(w - #countStr - #btnStr - 2, row)
            term.setTextColor(colors.cyan)
            term.write(countStr)
            term.setCursorPos(w - #btnStr, row)
            term.setTextColor(colors.green)
            term.write(btnStr)
        end
    end

    -- Pagination
    local pageRow = h - 1
    term.setCursorPos(1, pageRow)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(string.rep("-", w))

    if maxPage > 1 then
        local pageStr = _page .. "/" .. maxPage
        local px = math.floor((w - #pageStr) / 2)
        term.setCursorPos(px, pageRow)
        term.setTextColor(colors.white)
        term.write(pageStr)

        if _page > 1 then
            term.setCursorPos(2, pageRow)
            term.setTextColor(colors.yellow)
            term.write("[<]")
        end
        if _page < maxPage then
            term.setCursorPos(w - 3, pageRow)
            term.setTextColor(colors.yellow)
            term.write("[>]")
        end
    end

    -- Status bar
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    if vlib.isConnected() then
        term.setTextColor(colors.green)
        term.write(" Connected")
    else
        term.setTextColor(colors.red)
        term.write(" DISCONNECTED")
    end
    local countInfo = #_filtered .. " items "
    term.setCursorPos(w - #countInfo, h)
    term.setTextColor(colors.lightGray)
    term.write(countInfo)

    term.setBackgroundColor(colors.black)
end

local function handleClick(x, y)
    local w, h = term.getSize()
    local perPage = getItemsPerPage()
    local maxPage = math.max(1, math.ceil(#_filtered / perPage))

    -- Search bar click (row 1)
    if y == 1 then
        if _searchText ~= "" and x >= w - 2 then
            _searchText = ""
            _searchFocused = false
            _page = 1
            filterItems()
        else
            local outLabel = "[" .. getSelectedOutputName() .. "]"
            if x >= w - #outLabel then
                _selectedOutput = _selectedOutput + 1
                if _selectedOutput > #_outputNames then
                    _selectedOutput = 1
                end
            else
                _searchFocused = true
            end
        end
        return
    end

    -- Pagination (row h-1)
    if y == h - 1 then
        if x >= 2 and x <= 4 and _page > 1 then
            _page = _page - 1
        elseif x >= w - 3 and _page < maxPage then
            _page = _page + 1
        end
        return
    end

    -- Item rows (rows 3 to h-2)
    if y >= 3 and y <= h - 2 then
        local idx = ((_page - 1) * perPage) + (y - 2)
        local item = _filtered[idx]
        if not item then return end

        if _extractingIdx == idx then
            local cx = w - 22
            if x >= cx and x <= cx + 2 then
                -- Minus
                _extractCount = math.max(1, _extractCount - 1)
                _typingCount = false
            elseif x >= cx + 7 and x <= cx + 9 then
                -- Plus
                _extractCount = math.min(item.count or 64, _extractCount + 1)
                _typingCount = false
            elseif x >= cx + 3 and x <= cx + 6 then
                -- Click number to type
                _typingCount = true
                _extractCount = 0
            elseif x >= cx + 10 and x <= cx + 13 then
                -- OK
                local dest = getSelectedOutputChest()
                if dest then
                    vlib.send({
                        type = "request_items",
                        item = item.name,
                        count = _extractCount,
                        destination = dest,
                    })
                    vlib.receiveType("items_delivered", 5)
                    vlib.playSound("success")
                end
                _extractingIdx = nil
                _typingCount = false
            elseif x >= cx + 14 then
                -- Cancel
                _extractingIdx = nil
                _typingCount = false
            end
        else
            if x >= w - 2 then
                _extractingIdx = idx
                _extractCount = 1
                _typingCount = false
                vlib.playSound("click")
            end
        end
    end
end

local function queryStock()
    vlib.send({ type = "query_stock" })
    local reply = vlib.receiveType("stock_update", 5)
    if reply and reply.items then
        _items = reply.items
        filterItems()
    end
end

local function queryOutputs()
    vlib.send({ type = "query_outputs" })
    local reply = vlib.receiveType("output_list", 5)
    if reply and reply.outputs then
        _outputs = reply.outputs
        _outputNames = {}
        for name, _ in pairs(_outputs) do
            table.insert(_outputNames, name)
        end
        table.sort(_outputNames)
    end
end

local function mainLoop()
    queryOutputs()
    queryStock()
    draw()

    local refreshTimer = os.startTimer(5)
    local heartbeatTimer = os.startTimer(10)

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        vlib.checkEvent(event, p1, p2)

        if event == "timer" and p1 == refreshTimer then
            queryStock()
            draw()
            refreshTimer = os.startTimer(5)
        elseif event == "timer" and p1 == heartbeatTimer then
            vlib.heartbeat()
            heartbeatTimer = os.startTimer(10)
        elseif event == "mouse_click" then
            _searchFocused = false
            handleClick(p2, p3)
            draw()
        elseif event == "mouse_scroll" then
            local maxPage = math.max(1, math.ceil(#_filtered / getItemsPerPage()))
            if p1 == 1 and _page < maxPage then
                _page = _page + 1
            elseif p1 == -1 and _page > 1 then
                _page = _page - 1
            end
            draw()
        elseif event == "char" then
            if _typingCount then
                local digit = tonumber(p1)
                if digit then
                    _extractCount = _extractCount * 10 + digit
                end
                draw()
            elseif _searchFocused then
                _searchText = _searchText .. p1
                _page = 1
                filterItems()
                draw()
            else
                _searchFocused = true
                _searchText = p1
                _page = 1
                filterItems()
                draw()
            end
        elseif event == "key" then
            if p1 == keys.backspace then
                if _typingCount then
                    _extractCount = math.floor(_extractCount / 10)
                    if _extractCount < 1 then _extractCount = 0 end
                    draw()
                elseif _searchFocused and #_searchText > 0 then
                    _searchText = _searchText:sub(1, #_searchText - 1)
                    _page = 1
                    filterItems()
                    draw()
                end
            elseif p1 == keys.escape then
                if _extractingIdx then
                    _extractingIdx = nil
                    _typingCount = false
                    draw()
                elseif _searchFocused then
                    _searchFocused = false
                    draw()
                end
            elseif p1 == keys.enter then
                if _typingCount then
                    _typingCount = false
                    if _extractCount < 1 then _extractCount = 1 end
                    draw()
                elseif _searchFocused then
                    _searchFocused = false
                    draw()
                end
            end
        end
    end
end

if setup() then
    mainLoop()
end
