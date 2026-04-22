local repo = "https://raw.githubusercontent.com/OrigamingWasTaken/tweakedlogistics/main"

local files = {
    { remote = "lib/core.lua", path = "/tweakedlogistics/lib/core.lua" },
    { remote = "lib/storage.lua", path = "/tweakedlogistics/lib/storage.lua" },
    { remote = "lib/logistics.lua", path = "/tweakedlogistics/lib/logistics.lua" },
    { remote = "lib/crafting.lua", path = "/tweakedlogistics/lib/crafting.lua" },
    { remote = "lib/dashboard.lua", path = "/tweakedlogistics/lib/dashboard.lua" },
    { remote = "main.lua", path = "/tweakedlogistics/main.lua" },
    { remote = "startup.lua", path = "/startup.lua" },
    { remote = "turtle_helper.lua", path = "/tweakedlogistics/turtle_helper.lua" },
}

fs.makeDir("/tweakedlogistics")
fs.makeDir("/tweakedlogistics/lib")

for _, f in ipairs(files) do
    if fs.exists(f.path) then
        fs.delete(f.path)
    end
    print("Downloading " .. f.path)
    shell.run("wget", repo .. "/" .. f.remote, f.path)
end

print("")
print("TweakedLogistics installed!")
print("Reboot to start, or run: /tweakedlogistics/main.lua")
