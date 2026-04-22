local repo = "https://raw.githubusercontent.com/OrigamingWasTaken/tweakedlogistics/main"

local components = {
    {
        name = "Server (central hub)",
        files = {
            { remote = "lib/core.lua", path = "/tweakedlogistics/lib/core.lua" },
            { remote = "lib/storage.lua", path = "/tweakedlogistics/lib/storage.lua" },
            { remote = "lib/logistics.lua", path = "/tweakedlogistics/lib/logistics.lua" },
            { remote = "lib/crafting.lua", path = "/tweakedlogistics/lib/crafting.lua" },
            { remote = "lib/dashboard.lua", path = "/tweakedlogistics/lib/dashboard.lua" },
            { remote = "lib/nicknames.lua", path = "/tweakedlogistics/lib/nicknames.lua" },
            { remote = "lib/server.lua", path = "/tweakedlogistics/lib/server.lua" },
            { remote = "lib/cli.lua", path = "/tweakedlogistics/lib/cli.lua" },
            { remote = "main.lua", path = "/tweakedlogistics/main.lua" },
            { remote = "startup.lua", path = "/startup.lua" },
        },
        dirs = { "/tweakedlogistics", "/tweakedlogistics/lib" },
        postInstall = "Reboot to start, or run: /tweakedlogistics/main.lua",
    },
    {
        name = "Crafting Turtle",
        files = {
            { remote = "turtle_helper.lua", path = "/startup.lua" },
        },
        dirs = {},
        postInstall = "Reboot to start listening for craft commands.",
    },
    {
        name = "Virtual Restocker",
        files = {
            { remote = "virtual/lib.lua", path = "/tweakedlogistics/virtual/lib.lua" },
            { remote = "virtual/restocker.lua", path = "/startup.lua" },
        },
        dirs = { "/tweakedlogistics", "/tweakedlogistics/virtual" },
        postInstall = "Reboot to begin setup.",
    },
    {
        name = "Virtual Redstone Requester",
        files = {
            { remote = "virtual/lib.lua", path = "/tweakedlogistics/virtual/lib.lua" },
            { remote = "virtual/redstone_requester.lua", path = "/startup.lua" },
        },
        dirs = { "/tweakedlogistics", "/tweakedlogistics/virtual" },
        postInstall = "Reboot to begin setup.",
    },
}

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.cyan)
print("=== TweakedLogistics Installer ===")
term.setTextColor(colors.white)
print("")

for i, comp in ipairs(components) do
    print("  " .. i .. ". " .. comp.name)
end

print("")
term.setTextColor(colors.yellow)
write("Choose component (1-" .. #components .. "): ")
term.setTextColor(colors.white)
local choice = tonumber(read())

if not choice or choice < 1 or choice > #components then
    term.setTextColor(colors.red)
    print("Invalid choice.")
    return
end

local comp = components[choice]
print("")
term.setTextColor(colors.cyan)
print("Installing: " .. comp.name)
term.setTextColor(colors.white)
print("")

for _, dir in ipairs(comp.dirs) do
    fs.makeDir(dir)
end

for _, f in ipairs(comp.files) do
    if fs.exists(f.path) then
        fs.delete(f.path)
    end
    print("  " .. f.path)
    shell.run("wget", repo .. "/" .. f.remote, f.path)
end

print("")
term.setTextColor(colors.green)
print("Done!")
term.setTextColor(colors.white)
print(comp.postInstall)
