-- ============================================
-- ЗАХИСТ БЛОКІВ
-- ============================================
-- Гравці без привілею «server» не можуть ставити й ламати блоки.
-- Виняток - ресурси: руда, джерела ефіру/версиформу, дерева ефіру, рис.
-- (Будівництво фортеці йде через сервер, set_node - захист його не стосується.)

human_fortress = human_fortress or {}

local FREE_DIG = {
    ["human_fortress:versiforn_source"] = true,
    ["human_fortress:ether_source"]     = true,
    ["human_fortress:rice"]             = true,
}

local function free_dig(node_name)
    if FREE_DIG[node_name] then return true end
    local def = minetest.registered_nodes[node_name]
    if not def then return false end
    local g = def.groups or {}
    if (g.ether_tree or 0) > 0 or (g.hf_free_dig or 0) > 0 then return true end
    -- звичайна руда (default:stone_with_coal, ...)
    if node_name:find("stone_with_", 1, true) or node_name:find("_ore", 1, true) then
        return true
    end
    return false
end
human_fortress.is_free_dig_node = free_dig

local function can_build(name)
    return minetest.check_player_privs(name, { server = true })
        or minetest.check_player_privs(name, { protection_bypass = true })
end

minetest.register_on_mods_loaded(function()
    local old = minetest.is_protected
    function minetest.is_protected(pos, name)
        if old(pos, name) then return true end
        if not name or name == "" then return false end   -- сервер/мобі
        if can_build(name) then return false end
        -- ламати дозволено лише ресурси; ставити - нічого
        local node = minetest.get_node_or_nil(pos)
        if node and free_dig(node.name) then return false end
        return true
    end
end)
