local PROTOCOL = "tweakedlogistics"

local modemSide = nil
for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
    if peripheral.hasType(side, "modem") then
        modemSide = side
        break
    end
end

if not modemSide then
    printError("No modem found")
    return
end

rednet.open(modemSide)
rednet.host(PROTOCOL, "crafting_turtle")

print("TweakedLogistics Turtle Helper")
print("Listening for craft commands...")

while true do
    local senderId, message, protocol = rednet.receive(PROTOCOL)

    if senderId and type(message) == "table" and message.type == "craft" then
        local limit = message.limit
        local ok, err = turtle.craft(limit)
        rednet.send(senderId, {
            type = "craft_result",
            success = ok,
            error = err,
        }, PROTOCOL)
    end
end
