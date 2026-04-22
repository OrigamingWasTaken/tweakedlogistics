local repo = "https://raw.githubusercontent.com/OrigamingWasTaken/tweakedlogistics/main"

local files = {
    { remote = "lib/core.lua", path = "/tweakedlogistics/lib/core.lua" },
    { remote = "lib/storage.lua", path = "/tweakedlogistics/lib/storage.lua" },
    { remote = "lib/logistics.lua", path = "/tweakedlogistics/lib/logistics.lua" },
    { remote = "lib/crafting.lua", path = "/tweakedlogistics/lib/crafting.lua" },
    { remote = "lib/dashboard.lua", path = "/tweakedlogistics/lib/dashboard.lua" },
    { remote = "lib/nicknames.lua", path = "/tweakedlogistics/lib/nicknames.lua" },
    { remote = "lib/server.lua", path = "/tweakedlogistics/lib/server.lua" },
    { remote = "lib/cli.lua", path = "/tweakedlogistics/lib/cli.lua" },
    { remote = "virtual/lib.lua", path = "/tweakedlogistics/virtual/lib.lua" },
    { remote = "virtual/restocker.lua", path = "/tweakedlogistics/virtual/restocker.lua" },
    { remote = "virtual/redstone_requester.lua", path = "/tweakedlogistics/virtual/redstone_requester.lua" },
    { remote = "main.lua", path = "/tweakedlogistics/main.lua" },
    { remote = "startup.lua", path = "/startup.lua" },
    { remote = "turtle_helper.lua", path = "/tweakedlogistics/turtle_helper.lua" },
}

fs.makeDir("/tweakedlogistics")
fs.makeDir("/tweakedlogistics/lib")
fs.makeDir("/tweakedlogistics/virtual")

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
