-- ============================================
-- МІНІМАПА РЕЖИМУ КОМАНДУВАННЯ
-- ============================================
-- * формики (усі юніти з unit_data) показуються на мінімапі маркерами;
-- * у режимі командування вмикається звичайна мінімапа (поверхня, 512 вузлів);
-- * вигляд рамки й маркерів - textures/minimap_overlay_*.png, object_marker_red.png.

human_fortress = human_fortress or {}
local MM = {}
human_fortress.minimap = MM

-- Звичайна карта (поверхня), великий огляд. Маркери формиксів видно в усіх режимах.
local MODES = {
    { type = "surface", label = "Карта",            size = 512, scale = 1 },
    { type = "surface", label = "Карта (ближче)",   size = 256, scale = 1 },
    { type = "off",     label = "Мінімапу сховано", size = 0,   scale = 1 },
}

-- 1. Усі юніти-формики видно на мінімапі (за замовчуванням об'єкти там не показуються)
minetest.register_on_mods_loaded(function()
    for name, def in pairs(minetest.registered_entities) do
        if name:sub(1, 15) == "human_fortress:" and (def.hp_max or def.hp_min)
                and name ~= "human_fortress:jackal" then
            def.show_on_minimap = true
            if def.initial_properties then
                def.initial_properties.show_on_minimap = true
            end
        end
    end
end)

-- запасний варіант: юніти, що вже існують/створені іншим шляхом
local function flag_units_near(player)
    local pos = player:get_pos()
    if not pos then return end
    for _, o in ipairs(minetest.get_objects_inside_radius(pos, 300)) do
        local ent = o:get_luaentity()
        if ent and ent.unit_data and not ent._hf_mm then
            ent._hf_mm = true
            o:set_properties({ show_on_minimap = true })
        end
    end
end

local saved_flags = {}
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 2 then return end
    timer = 0
    for name in pairs(saved_flags) do
        local player = minetest.get_player_by_name(name)
        if player then flag_units_near(player) end
    end
end)

function MM.enter(player)
    local name = player:get_player_name()
    if not saved_flags[name] then
        saved_flags[name] = player:hud_get_flags() or { minimap = false, minimap_radar = false }
    end
    player:hud_set_flags({ minimap = true })
    player:set_minimap_modes(MODES, 1)
    flag_units_near(player)
end

function MM.exit(player)
    local name = player:get_player_name()
    local f = saved_flags[name]
    saved_flags[name] = nil
    if f then
        player:hud_set_flags({ minimap = f.minimap and true or false,
                               minimap_radar = f.minimap_radar and true or false })
    end
end

minetest.register_on_leaveplayer(function(player)
    saved_flags[player:get_player_name()] = nil
end)
