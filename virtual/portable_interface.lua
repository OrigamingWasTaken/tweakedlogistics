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
local _selectedRow = 1
local _modal = nil
local _modalCount = 1
local _modalTyping = false
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

local function perPage()
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
            local name = (item.displayName or ""):lower()
            local id = (item.name or ""):lower()
            if name:find(query, 1, true) or id:find(query, 1, true) then
                table.insert(_filtered, item)
            end
        end
    end
    local maxP = math.max(1, math.ceil(#_filtered / perPage()))
    if _page > maxP then _page = maxP end
    if _selectedRow > #_filtered then _selectedRow = math.max(1, #_filtered) end
end

local function getOutputChest()
    if #_outputNames > 0 and _selectedOutput <= #_outputNames then
        return _outputs[_outputNames[_selectedOutput]]
    end
    return nil
end

local function getOutputName()
    if #_outputNames > 0 and _selectedOutput <= #_outputNames then
        return _outputNames[_selectedOutput]
    end
    return "None"
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
        if _selectedOutput > #_outputNames then _selectedOutput = 1 end
    end
end

local function drawModal()
    if not _modal then return end
    local w, h = term.getSize()
    local mw = w - 4
    local mh = 9
    local mx = 3
    local my = math.floor((h - mh) / 2) + 1

    for row = my, my + mh - 1 do
        term.setCursorPos(mx, row)
        term.setBackgroundColor(colors.gray)
        term.write(string.rep(" ", mw))
    end

    local name = _modal.displayName or _modal.name or "?"
    if #name > mw - 2 then name = name:sub(1, mw - 4) .. ".." end
    term.setCursorPos(mx + 1, my)
    term.setTextColor(colors.cyan)
    term.setBackgroundColor(colors.gray)
    term.write(name)

    term.setCursorPos(mx + 1, my + 1)
    term.setTextColor(colors.lightGray)
    term.write("Available: " .. (_modal.count or 0))

    term.setCursorPos(mx + 1, my + 3)
    term.setTextColor(colors.white)
    term.write("To: ")
    term.setTextColor(colors.cyan)
    local oName = getOutputName()
    if #oName > mw - 10 then oName = oName:sub(1, mw - 12) .. ".." end
    term.write(oName .. " [Tab]")

    local countStr = tostring(_modalCount)
    term.setCursorPos(mx + 2, my + 5)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(" - ")
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.yellow)
    if _modalTyping then
        term.write(" " .. countStr .. "_ ")
    else
        term.write(" " .. countStr .. " ")
    end
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" + ")
    term.setBackgroundColor(colors.blue)
    term.write(" All ")

    term.setCursorPos(mx + 2, my + 7)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" Send  ")
    term.setBackgroundColor(colors.gray)
    term.write(" ")
    term.setBackgroundColor(colors.red)
    term.write(" Cancel ")

    term.setBackgroundColor(colors.black)
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

local function draw()
    if _showOutputList then
        drawOutputList()
        return
    end

    local w, h = term.getSize()
    local pp = perPage()
    local maxP = math.max(1, math.ceil(#_filtered / pp))

    term.setBackgroundColor(colors.black)
    term.clear()

    -- Top bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, 1)

    local outName = getOutputName()
    if #outName > 8 then outName = outName:sub(1, 7) .. "." end
    term.setTextColor(colors.cyan)
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
    local startIdx = ((_page - 1) * pp) + 1
    for i = 0, pp - 1 do
        local idx = startIdx + i
        local row = 3 + i
        local item = _filtered[idx]

        term.setCursorPos(1, row)

        if item then
            local isSelected = (idx == _selectedRow)
            term.setBackgroundColor(isSelected and colors.gray or colors.black)
            term.write(string.rep(" ", w))
            term.setCursorPos(1, row)

            local name = item.displayName or item.name or "?"
            local countStr = tostring(item.count or 0)
            local nameW = w - #countStr - 2

            if #name > nameW then name = name:sub(1, nameW - 2) .. ".." end

            term.setTextColor(colors.white)
            term.write(" " .. name)
            term.setCursorPos(w - #countStr, row)
            term.setTextColor(colors.cyan)
            term.write(countStr)
            term.setBackgroundColor(colors.black)
        else
            term.setBackgroundColor(colors.black)
            term.write(string.rep(" ", w))
        end
    end

    -- Pagination
    local pageRow = h - 1
    term.setCursorPos(1, pageRow)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(string.rep("-", w))

    if maxP > 1 then
        if _page > 1 then
            term.setCursorPos(2, pageRow)
            term.setTextColor(colors.yellow)
            term.write("[<]")
        end
        local pageStr = _page .. "/" .. maxP
        term.setCursorPos(math.floor((w - #pageStr) / 2), pageRow)
        term.setTextColor(colors.white)
        term.write(pageStr)
        if _page < maxP then
            term.setCursorPos(w - 3, pageRow)
            term.setTextColor(colors.yellow)
            term.write("[>]")
        end
    end

    -- Status
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    term.setTextColor(vlib.isConnected() and colors.green or colors.red)
    term.write(vlib.isConnected() and " OK" or " DISC")
    term.setCursorPos(w - #tostring(#_filtered) - 1, h)
    term.setTextColor(colors.lightGray)
    term.write(#_filtered .. " ")

    term.setBackgroundColor(colors.black)

    if _modal then drawModal() end
end

local function openModal(item)
    _modal = item
    _modalCount = 1
    _modalTyping = false
    vlib.playSound("click")
end

local function closeModal()
    _modal = nil
    _modalTyping = false
end

local function sendExtract()
    if not _modal then return end
    local dest = getOutputChest()
    if dest and _modalCount > 0 then
        vlib.send({
            type = "request_items",
            item = _modal.name,
            count = _modalCount,
            destination = dest,
        })
        vlib.receiveType("items_delivered", 5)
        vlib.playSound("success")
    end
    closeModal()
    queryStock()
end

local function handleModalClick(x, y)
    local w, h = term.getSize()
    local mw = w - 4
    local mh = 9
    local mx = 3
    local my = math.floor((h - mh) / 2) + 1

    if y == my + 3 then
        _selectedOutput = _selectedOutput + 1
        if _selectedOutput > #_outputNames then _selectedOutput = 1 end
        return
    end

    if y == my + 5 then
        if x >= mx + 2 and x <= mx + 4 then
            _modalCount = math.max(1, _modalCount - 1)
            _modalTyping = false
        elseif x >= mx + 9 and x <= mx + 11 then
            _modalCount = math.min(_modal.count or 64, _modalCount + 1)
            _modalTyping = false
        elseif x >= mx + 5 and x <= mx + 8 then
            _modalTyping = true
            _modalCount = 0
        elseif x >= mx + 12 then
            _modalCount = _modal.count or 64
            _modalTyping = false
        end
        return
    end

    if y == my + 7 then
        if x >= mx + 2 and x <= mx + 8 then
            sendExtract()
        elseif x >= mx + 10 then
            closeModal()
        end
    end
end

local function handleClick(x, y)
    local w, h = term.getSize()
    local pp = perPage()
    local maxP = math.max(1, math.ceil(#_filtered / pp))

    if _showOutputList then
        local idx = y - 2
        if idx >= 1 and idx <= #_outputNames then
            _selectedOutput = idx
            _showOutputList = false
            vlib.playSound("click")
        end
        return
    end

    if _modal then
        handleModalClick(x, y)
        return
    end

    if y == 1 then
        local outName = getOutputName()
        if #outName > 8 then outName = outName:sub(1, 7) .. "." end
        if x <= #outName + 2 then
            _showOutputList = true
            vlib.playSound("click")
        else
            _searchFocused = true
        end
        return
    end

    if y == h - 1 then
        if x >= 2 and x <= 4 and _page > 1 then _page = _page - 1
        elseif x >= w - 3 and _page < maxP then _page = _page + 1 end
        return
    end

    if y >= 3 and y <= h - 2 then
        local idx = ((_page - 1) * pp) + (y - 2)
        if _filtered[idx] then
            _selectedRow = idx
            openModal(_filtered[idx])
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
            if not _modal and not _showOutputList then queryStock() end
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
            if not _modal and not _showOutputList then
                local maxP = math.max(1, math.ceil(#_filtered / perPage()))
                if p1 == 1 and _page < maxP then _page = _page + 1
                elseif p1 == -1 and _page > 1 then _page = _page - 1 end
                draw()
            end
        elseif event == "char" then
            if _modal then
                local d = tonumber(p1)
                if d then
                    if not _modalTyping then
                        _modalTyping = true
                        _modalCount = 0
                    end
                    _modalCount = _modalCount * 10 + d
                end
                draw()
            elseif _searchFocused then
                _searchText = _searchText .. p1
                _page = 1
                filterItems()
                draw()
            elseif not _showOutputList then
                _searchFocused = true
                _searchText = p1
                _page = 1
                filterItems()
                draw()
            end
        elseif event == "key" then
            if p1 == keys.escape then
                if _modal then closeModal()
                elseif _showOutputList then _showOutputList = false
                elseif _searchFocused then _searchFocused = false end
                draw()
            elseif p1 == keys.enter then
                if _modal then
                    if _modalTyping then
                        _modalTyping = false
                        if _modalCount < 1 then _modalCount = 1 end
                    else
                        sendExtract()
                    end
                elseif _showOutputList then
                    _showOutputList = false
                elseif _searchFocused then
                    _searchFocused = false
                elseif _filtered[_selectedRow] then
                    openModal(_filtered[_selectedRow])
                end
                draw()
            elseif p1 == keys.backspace then
                if _modal and _modalTyping then
                    _modalCount = math.floor(_modalCount / 10)
                elseif _modal then
                    -- ignore
                elseif _searchFocused and #_searchText > 0 then
                    _searchText = _searchText:sub(1, #_searchText - 1)
                    _page = 1
                    filterItems()
                end
                draw()
            elseif _modal and (p1 == keys.left or p1 == keys.a) then
                _modalCount = math.max(1, _modalCount - 1)
                _modalTyping = false
                draw()
            elseif _modal and (p1 == keys.right or p1 == keys.d) then
                _modalCount = math.min(_modal.count or 64, _modalCount + 1)
                _modalTyping = false
                draw()
            elseif p1 == keys.up then
                if _showOutputList then
                    _selectedOutput = math.max(1, _selectedOutput - 1)
                elseif not _modal and _selectedRow > 1 then
                    _selectedRow = _selectedRow - 1
                    local startIdx = ((_page - 1) * perPage()) + 1
                    if _selectedRow < startIdx then _page = _page - 1 end
                end
                draw()
            elseif p1 == keys.down then
                if _showOutputList then
                    _selectedOutput = math.min(#_outputNames, _selectedOutput + 1)
                elseif not _modal and _selectedRow < #_filtered then
                    _selectedRow = _selectedRow + 1
                    local endIdx = _page * perPage()
                    if _selectedRow > endIdx then _page = _page + 1 end
                end
                draw()
            elseif p1 == keys.tab then
                if _modal or not _showOutputList then
                    _selectedOutput = _selectedOutput + 1
                    if _selectedOutput > #_outputNames then _selectedOutput = 1 end
                end
                draw()
            end
        end
    end
end

if setup() then
    mainLoop()
end
