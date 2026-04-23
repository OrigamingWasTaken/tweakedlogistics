local rarity = {}

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

function rarity.get(item)
    if EPIC_ITEMS[item.name] then return "epic" end
    if RARE_ITEMS[item.name] then return "rare" end
    local base = "common"
    if UNCOMMON_ITEMS[item.name] then base = "uncommon" end
    if item.enchantments and #item.enchantments > 0 then
        if base == "common" or base == "uncommon" then
            return "rare"
        end
    end
    return base
end

function rarity.getColor(r)
    if r == "epic" then return colors.purple end
    if r == "rare" then return colors.cyan end
    if r == "uncommon" then return colors.yellow end
    return colors.white
end

function rarity.getItemColor(item)
    local r = rarity.get(item)
    local c = rarity.getColor(r)
    if item.customName then c = colors.lightGray end
    return c
end

return rarity
