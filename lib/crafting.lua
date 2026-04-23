local crafting = {}

local _core = nil
local _storage = nil
local _config = nil
local _recipes = {}
local _processors = {}
local _processorCounter = 0
local _jobs = {}
local _jobCounter = 0

function crafting.init(core, storage, config)
    _core = core
    _storage = storage
    _config = config

    local savedProcessors = _config.get("crafting.processors")
    if type(savedProcessors) == "table" then
        for _, proc in ipairs(savedProcessors) do
            _processorCounter = _processorCounter + 1
            proc.id = proc.id or tostring(_processorCounter)
            proc.busy = false
            proc.currentJob = nil
            _processors[proc.id] = proc
        end
    end
end

-- Recipe management --

function crafting.loadRecipes(url)
    local resp = http.get(url)
    if not resp then return false end

    local body = resp.readAll()
    resp.close()

    if not body then return false end

    local data = textutils.unserializeJSON(body)
    if type(data) ~= "table" then return false end

    _recipes = data

    local h = fs.open("/tweakedlogistics_recipes.cache", "w")
    if h then
        h.write(body)
        h.close()
    end

    return true
end

function crafting.loadCachedRecipes()
    if not fs.exists("/tweakedlogistics_recipes.cache") then return false end
    local h = fs.open("/tweakedlogistics_recipes.cache", "r")
    if not h then return false end
    local body = h.readAll()
    h.close()
    local data = textutils.unserializeJSON(body)
    if type(data) ~= "table" then return false end
    _recipes = data
    return true
end

function crafting.getRecipe(itemName)
    return _recipes[itemName]
end

-- Processor management --

local function saveProcessors()
    local list = {}
    for _, proc in pairs(_processors) do
        table.insert(list, {
            id = proc.id,
            type = proc.type,
            input = proc.input,
            output = proc.output,
        })
    end
    _config.set("crafting.processors", list)
end

function crafting.addProcessor(proc)
    _processorCounter = _processorCounter + 1
    local id = tostring(_processorCounter)
    proc.id = id
    proc.busy = false
    proc.currentJob = nil
    _processors[id] = proc

    _storage.excludeInventory(proc.input)
    _storage.excludeInventory(proc.output)

    saveProcessors()
    return id
end

function crafting.removeProcessor(id)
    _processors[id] = nil
    saveProcessors()
end

function crafting.getProcessors()
    local list = {}
    for _, proc in pairs(_processors) do
        table.insert(list, {
            id = proc.id,
            type = proc.type,
            input = proc.input,
            output = proc.output,
            busy = proc.busy,
            currentJob = proc.currentJob,
        })
    end
    return list
end

-- Job management --

function crafting.requestCraft(itemName, count)
    _jobCounter = _jobCounter + 1
    local id = tostring(_jobCounter)

    local recipe = crafting.getRecipe(itemName)
    local job = {
        id = id,
        item = itemName,
        count = count,
        recipe = recipe,
        status = "queued",
        created = os.epoch("utc"),
        inputsSent = 0,
        outputsCollected = 0,
    }

    table.insert(_jobs, job)
    _core.event.emit("crafting:job_started", id, itemName, count)
    return id
end

function crafting.cancelJob(id)
    for i, job in ipairs(_jobs) do
        if job.id == id then
            table.remove(_jobs, i)
            return true
        end
    end
    return false
end

function crafting.getJobs()
    local list = {}
    for _, job in ipairs(_jobs) do
        table.insert(list, {
            id = job.id,
            item = job.item,
            count = job.count,
            status = job.status,
            inputsSent = job.inputsSent,
            outputsCollected = job.outputsCollected,
        })
    end
    return list
end

local function findProcessorForRecipe(recipe)
    if not recipe or not recipe.processorType then return nil end
    for _, proc in pairs(_processors) do
        if proc.type == recipe.processorType and not proc.busy then
            return proc
        end
    end
    return nil
end

local function collectOutputs(proc, job)
    local ok, contents = pcall(peripheral.call, proc.output, "list")
    if not ok or not contents then return end

    for slot, slotData in pairs(contents) do
        local moved = _storage.insert(proc.output, slot, slotData.count)
        if moved > 0 then
            job.outputsCollected = job.outputsCollected + moved
        end
    end
end

local function processJobs()
    for i = #_jobs, 1, -1 do
        local job = _jobs[i]

        if job.status == "queued" and job.recipe then
            local proc = findProcessorForRecipe(job.recipe)
            if proc then
                local inputItem = job.recipe.input
                local inputCount = job.count
                if job.recipe.ratio then
                    inputCount = math.ceil(job.count * job.recipe.ratio)
                end

                local key = nil
                local items = _storage.getItems()
                for _, item in ipairs(items) do
                    if _core.matchesItem(item.name, inputItem) then
                        key = item.key
                        break
                    end
                end

                if key then
                    local sent = _storage.extract(key, inputCount, proc.input)
                    if sent > 0 then
                        job.status = "processing"
                        job.inputsSent = sent
                        job.processorId = proc.id
                        proc.busy = true
                        proc.currentJob = job.id
                        _core.event.emit("crafting:processor_busy", proc.id, job.id)
                    else
                        job.status = "failed"
                        _core.event.emit("crafting:job_failed", job.id, job.item, "no items in storage")
                    end
                else
                    job.status = "failed"
                    _core.event.emit("crafting:job_failed", job.id, job.item, "item not found in storage")
                end
            end

        elseif job.status == "processing" then
            local proc = _processors[job.processorId]
            if proc then
                collectOutputs(proc, job)

                local expectedOutput = job.count
                if job.outputsCollected >= expectedOutput then
                    job.status = "complete"
                    proc.busy = false
                    proc.currentJob = nil
                    _core.event.emit("crafting:processor_idle", proc.id)
                    _core.event.emit("crafting:job_complete", job.id, job.item, job.outputsCollected)
                    table.remove(_jobs, i)
                end
            end

        elseif job.status == "failed" then
            table.remove(_jobs, i)
        end
    end
end

function crafting.loop()
    crafting.loadCachedRecipes()
    while true do
        processJobs()
        sleep(_config.get("crafting.interval") or 2)
    end
end

return crafting
