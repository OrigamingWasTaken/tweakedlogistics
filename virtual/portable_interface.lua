local vlib = dofile("/tweakedlogistics/virtual/lib.lua")

local CONFIG_PATH = "/virtual_portable.config"
local BLOCK_TYPE = "virtual_portable_interface"

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
local _showOutputList = false

local function setup()
    vlib.loadConfig(CONFIG_PATH)
    if not vlib.setupScreen("Portable Interface") then return false end

    vlib.saveConfig()

    local ok = vlib.register(BLOCK_TYPE, {})

    if ok then
        term.setTextColor(colors.green)
        print("Registered with server!")
    else
        term.setTextColor(colors.yellow)
        print("Server did not acknowledge...")
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
    return nil
end

local function getSelectedOutputName()
    if #_outputNames > 0 and _selectedOutput <= #_outputNames then
        return _outputNames[_selectedOutput]
    end
    return "None"
end

local function drawOutputList()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("Select Output:")
    term.setTextColor(colors.lightGray)
    print(string.rep("-", w))

    for i, name in ipairs(_outputNames) do
        if i + 2 > h then break end
        term.setCursorPos(1, i + 2)
        if i == _selectedOutput then
            term.setTextColor(colors.green)
            term.write(" > " .. name)
        else
            term.setTextColor(colors.white)
            term.write("   " .. name)
        end
    end
end

local function drawExtractOverlay(item)
    local w, h = term.getSize()
    local oy = math.floor(h / 2) - 2
    local ox = 2
    local ow = w - 2

    for row = oy, oy + 5 do
        term.setCursorPos(ox, row)
        term.setBackgroundColor(colors.gray)
        term.write(string.rep(" ", ow))
    end

    local name = (item.displayName or item.name or "?")
    if #name > ow - 2 then name = name:sub(1, ow - 4) .. ".." end
    term.setCursorPos(ox + 1, oy)
    term.setTextColor(colors.cyan)
    term.setBackgroundColor(colors.gray)
    term.write(name)

    term.setCursorPos(ox + 1, oy + 1)
    term.setTextColor(colors.lightGray)
    term.write("Available: " .. (item.count or 0))

    local countStr = tostring(_extractCount)
    term.setCursorPos(ox + 2, oy + 3)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(" - ")
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.yellow)
    if _typingCount then
        term.write(" " .. countStr .. "_ ")
    else
        term.write(" " .. countStr .. " ")
    end
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" + ")

    term.setCursorPos(ox + 2, oy + 5)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" Send ")
    term.setBackgroundColor(colors.gray)
    term.write(" ")
    term.setBackgroundColor(colors.red)
    term.write(" Cancel ")

    term.setBackgroundColor(colors.black)
end

local function draw()
    if _showOutputList then
        drawOutputList()
        return
    end

    local w, h = term.getSize()
    local perPage = getItemsPerPage()
    local maxPage = math.max(1, math.ceil(#_filtered / perPage))

    term.setBackgroundColor(colors.black)
    term.clear()

    -- Top bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))

    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    local outName = getSelectedOutputName()
    if #outName > 8 then outName = outName:sub(1, 7) .. "." end
    term.write("[" .. outName .. "]")

    local searchX = #outName + 4
    term.setCursorPos(searchX, 1)
    if _searchFocused then
        term.setTextColor(colors.yellow)
        term.write(_searchText .. "_")
    elseif _searchText ~= "" then
        term.setTextColor(colors.white)
        term.write(_searchText)
    else
        term.setTextColor(colors.lightGray)
        term.write("Search...")
    end

    -- Divider
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(string.rep("-", w))

    -- Items
    local startIdx = ((_page - 1) * perPage) + 1
    for i = 0, perPage - 1 do
        local idx = startIdx + i
        local row = 3 + i
        local item = _filtered[idx]

        term.setCursorPos(1, row)
        term.setBackgroundColor(colors.black)

        if item then
            local name = item.displayName or item.name or "?"
            local countStr = tostring(item.count or 0)
            local nameW = w - #countStr - 5

            if #name > nameW then name = name:sub(1, nameW - 2) .. ".." end

            term.setTextColor(colors.white)
            term.write(" " .. name)
            term.setCursorPos(w - #countStr - 4, row)
            term.setTextColor(colors.cyan)
            term.write(countStr)
            term.setCursorPos(w - 2, row)
            term.setTextColor(colors.green)
            term.write("[>]")
        end
    end

    -- Pagination
    local pageRow = h - 1
    term.setCursorPos(1, pageRow)
    term.setTextColor(colors.lightGray)
    term.write(string.rep("-", w))

    if maxPage > 1 then
        local pageStr = _page .. "/" .. maxPage
        term.setCursorPos(math.floor((w - #pageStr) / 2), pageRow)
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

    -- Status
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(vlib.isConnected() and colors.green or colors.red)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    term.write(vlib.isConnected() and " OK" or " DISC")
    term.setCursorPos(w - #tostring(#_filtered) - 1, h)
    term.setTextColor(colors.lightGray)
    term.write(#_filtered .. " ")

    term.setBackgroundColor(colors.black)

    -- Extract overlay
    if _extractingIdx then
        local item = _filtered[_extractingIdx]
        if item then
            drawExtractOverlay(item)
        end
    end
end

local function handleClick(x, y)
    local w, h = term.getSize()
    local perPage = getItemsPerPage()
    local maxPage = math.max(1, math.ceil(#_filtered / perPage))

    if _showOutputList then
        local idx = y - 2
        if idx >= 1 and idx <= #_outputNames then
            _selectedOutput = idx
            _showOutputList = false
            vlib.playSound("click")
        end
        return
    end

    if _extractingIdx then
        local item = _filtered[_extractingIdx]
        if not item then _extractingIdx = nil return end

        local oy = math.floor(h / 2) - 2
        local ox = 2

        if y == oy + 3 then
            if x >= ox + 2 and x <= ox + 4 then
                _extractCount = math.max(1, _extractCount - 1)
                _typingCount = false
            elseif x >= ox + 9 and x <= ox + 11 then
                _extractCount = math.min(item.count or 64, _extractCount + 1)
                _typingCount = false
            elseif x >= ox + 5 and x <= ox + 8 then
                _typingCount = true
                _extractCount = 0
            end
        elseif y == oy + 5 then
            if x >= ox + 2 and x <= ox + 7 then
                -- Send
                local dest = getSelectedOutputChest()
                if dest and _extractCount > 0 then
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
            elseif x >= ox + 9 then
                -- Cancel
                _extractingIdx = nil
                _typingCount = false
            end
        end
        return
    end

    -- Top bar
    if y == 1 then
        local outName = getSelectedOutputName()
        if #outName > 8 then outName = outName:sub(1, 7) .. "." end
        if x <= #outName + 2 then
            _showOutputList = true
            vlib.playSound("click")
        else
            _searchFocused = true
        end
        return
    end

    -- Pagination
    if y == h - 1 then
        if x >= 2 and x <= 4 and _page > 1 then
            _page = _page - 1
        elseif x >= w - 3 and _page < maxPage then
            _page = _page + 1
        end
        return
    end

    -- Items
    if y >= 3 and y <= h - 2 then
        local idx = ((_page - 1) * perPage) + (y - 2)
        if _filtered[idx] then
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
        if #_outputNames > 0 and _selectedOutput > #_outputNames then
            _selectedOutput = 1
        end
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
            if not _extractingIdx and not _showOutputList then
                local maxP = math.max(1, math.ceil(#_filtered / getItemsPerPage()))
                if p1 == 1 and _page < maxP then _page = _page + 1
                elseif p1 == -1 and _page > 1 then _page = _page - 1 end
                draw()
            end
        elseif event == "char" then
            if _typingCount then
                local digit = tonumber(p1)
                if digit then
                    _extractCount = _extractCount * 10 + digit
                end
                draw()
            elseif _searchFocused or not _showOutputList then
                if not _searchFocused then
                    _searchFocused = true
                    _searchText = ""
                end
                _searchText = _searchText .. p1
                _page = 1
                filterItems()
                draw()
            end
        elseif event == "key" then
            if p1 == keys.backspace then
                if _typingCount then
                    _extractCount = math.floor(_extractCount / 10)
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
                elseif _showOutputList then
                    _showOutputList = false
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
