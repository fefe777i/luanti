-- ============================================
-- СИСТЕМА КЕРУВАННЯ - РЕЖИМ КОМАНДУВАННЯ
-- ============================================

local cmd_mode = {}
local storage = minetest.get_mod_storage()
local exit_command_mode
local box_corner = {} -- перший кут виділення рамкою для кожного гравця
local CMD_REACH    = 150.0 -- камера зверху: ціль може бути далеко від "очей"
local NORMAL_REACH = 4.0

local function set_reach(player, r)
    player:set_properties({ reach = r })
end

local function save_cmd_mode(name)
    if cmd_mode[name] then
        local data = { pos = cmd_mode[name].pos, inv = cmd_mode[name].inv }
        storage:set_string("cmd_mode_" .. name, minetest.serialize(data))
    else
        storage:set_string("cmd_mode_" .. name, "")
    end
end

local function load_cmd_mode(name)
    local raw = storage:get_string("cmd_mode_" .. name)
    if raw and raw ~= "" then return minetest.deserialize(raw) end
    return nil
end

-- ============================================
-- ЧЕРГА КОМАНД ДЛЯ СПЛЯЧИХ ЧАНКІВ
-- ============================================
if not human_fortress.pending_commands then
    human_fortress.pending_commands = {}
end

minetest.register_globalstep(function(dtime)
    local now = os.time()
    for uid, cmd in pairs(human_fortress.pending_commands) do
        if cmd.timestamp and (now - cmd.timestamp) > 300 then
            human_fortress.pending_commands[uid] = nil
        end
    end
end)

local function find_unit_by_id(unit_id)
    if not unit_id then return nil, nil end
    -- швидкий шлях: кеш з rts.lua (без сканування радіуса 300 для кожного юніта)
    if human_fortress.rts then
        local cobj, cent = human_fortress.rts.find_unit(unit_id)
        if cobj then return cobj, cent end
    end
    for _, player in ipairs(minetest.get_connected_players()) do
        local objs = minetest.get_objects_inside_radius(player:get_pos(), 300)
        for _, obj in ipairs(objs) do
            local ent = obj:get_luaentity()
            if ent and ent.unit_data and ent.unit_data.unit_id == unit_id then
                return obj, ent
            end
        end
    end
    return nil, nil
end

local function get_selected_unit_ids(player)
    local name = player:get_player_name()
    if not human_fortress.players or not human_fortress.players[name] then return {} end
    return human_fortress.players[name].selected_ids or {}
end

local function set_selected_unit_ids(player, ids)
    local name = player:get_player_name()
    if not human_fortress.players then human_fortress.players = {} end
    if not human_fortress.players[name] then human_fortress.players[name] = {selected_ids = {}} end
    human_fortress.players[name].selected_ids = ids
    if human_fortress.rts and human_fortress.rts.is_active(name) then
        human_fortress.rts.sync(name)
    end
end

local function send_command_to_selected(player, command, target)
    local name = player:get_player_name()
    local ids = get_selected_unit_ids(player)
    if #ids == 0 then
        minetest.chat_send_player(name, "⚠️ Немає виділених юнітів!")
        return 0, 0
    end

    local sent = 0
    local queued = 0

    for _, unit_id in ipairs(ids) do
        local obj, ent = find_unit_by_id(unit_id)
        if ent then
            ent.unit_data = ent.unit_data or {}
            ent.unit_data.command = command
            ent.unit_data.target = target
            sent = sent + 1
        else
            human_fortress.pending_commands[unit_id] = {
                command = command,
                target = target,
                timestamp = os.time(),
            }
            queued = queued + 1
        end
    end

    if sent > 0 then
        minetest.chat_send_player(name, "📡 Команду відправлено " .. sent .. " юнітам")
    end
    if queued > 0 then
        minetest.chat_send_player(name, "⏳ " .. queued .. " юнітів у сплячих чанках — команда виконається при завантаженні")
    end
    return sent, queued
end

-- ============================================
-- ДАНІ ПРО БУДІВЛІ
-- ============================================

local BUILDING_PREVIEWS = {
    townhall = { label = "🏛️ Ратуша",  preview_node = "default:brick" },
    rice_field     = { label = "🌾 Ферма",   preview_node = "default:dirt_with_grass" },
    barracks = { label = "⚔️ Казарми", preview_node = "default:stonebrick" },
    wall     = { label = "🧱 Стіна",   preview_node = "default:stonebrick" },
    tower    = { label = "🗼 Вежа",    preview_node = "default:stone" },
    house    = { label = "🏠 Дім",     preview_node = "default:wood" },
    carpenter_workshop = { label = "🪚 Плотницька", preview_node = "default:wood" },
    market   = { label = "🏪 Ринок",   preview_node = "default:junglewood" },
    warehouse = { label = "📦 Склад",  preview_node = "default:chest" },
}

-- ============================================
-- ФАНТОМНИЙ БЛОК
-- ============================================

minetest.register_entity("human_fortress:ghost_preview", {
    initial_properties = {
        visual = "wielditem",
        wield_item = "air",
        visual_size = { x = 0.67, y = 0.67 },
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
        glow = 6,
        color = "#FFFFFF9A",
    },
    on_activate = function(self)
        self.object:set_armor_groups({ immortal = 1 })
    end,
})

-- ============================================
-- ХУД-КНОПКИ
-- ============================================

local MAIN_BUTTONS = {
    {key = "sight",  tool = "human_fortress:cmd_sight",  icon = "my_button.png^human_fortress_cmd_sight.png"},
    {key = "select",  tool = "human_fortress:cmd_select",  icon = "my_button.png^human_fortress_cmd_select.png"},
    {key = "move",    tool = "human_fortress:cmd_move",    icon = "my_button.png^human_fortress_cmd_move.png"},
    {key = "gather",  tool = "human_fortress:cmd_gather",  icon = "my_button.png^human_fortress_cmd_gather.png"},
    {key = "build",   tool = "human_fortress:cmd_build",   icon = "my_button.png^human_fortress_cmd_build.png"},
    {key = "attack",  tool = "human_fortress:cmd_attack",  icon = "my_button.png^human_fortress_cmd_attack.png"},
    {key = "enter",   tool = "human_fortress:cmd_enter",   icon = "my_button.png^human_fortress_cmd_enter.png"},
    {key = "repair",  tool = "human_fortress:cmd_repair",  icon = "my_button.png^human_fortress_cmd_repair.png"},
    {key = "destroy", tool = "human_fortress:cmd_destroy", icon = "my_button.png^human_fortress_cmd_destroy.png"},
    {key = "box",     tool = "human_fortress:cmd_box",     icon = "my_button.png^human_fortress_cmd_box.png"},
    {key = "deselect", tool = "human_fortress:cmd_select", icon = "my_button.png^human_fortress_cmd_deselect.png"},
    {key = "exit",    tool = "human_fortress:cmd_exit",    icon = "my_button.png^human_fortress_cmd_exit.png"},
}

local BUILD_BUTTONS = {
    {key = "b_move",    tool = "human_fortress:build_move",    icon = "my_button.png^human_fortress_cmd_moveb.png"},
    {key = "b_rotate",  tool = "human_fortress:build_rotate",  icon = "my_button.png^human_fortress_cmd_rotate.png"},
    {key = "b_confirm", tool = "human_fortress:build_confirm", icon = "my_button.png^human_fortress_cmd_buildc.png"},
    {key = "b_cancel",  tool = "human_fortress:build_cancel",  icon = "my_button.png^human_fortress_cmd_exit.png"},
}

local BUTTON_LOOKUP = {}
for _, b in ipairs(MAIN_BUTTONS) do BUTTON_LOOKUP[b.key] = b end
for _, b in ipairs(BUILD_BUTTONS) do BUTTON_LOOKUP[b.key] = b end

-- Кнопки-дії одноразові: вони не лишаються підсвіченими як вибраний інструмент
local ACTION_KEYS = { deselect = true, exit = true, b_rotate = true, b_confirm = true, b_cancel = true }

-- інструмент -> ключ кнопки (для підсвітки вибраного інструмента)
local TOOL_KEY = {}
for _, list in ipairs({ MAIN_BUTTONS, BUILD_BUTTONS }) do
    for _, b in ipairs(list) do
        if not ACTION_KEYS[b.key] then TOOL_KEY[b.tool] = b.key end
    end
end

local function clear_hud_buttons(player)
    if human_fortress.rts and human_fortress.rts.is_active(player:get_player_name()) then
        human_fortress.rts.set_buttons(player, {})
        return
    end
    local name = player:get_player_name()
    local data = cmd_mode[name]
    if not data or not data.hud_buttons then return end
    for _, id in pairs(data.hud_buttons) do
        player:hud_remove(id)
    end
    data.hud_buttons = {}
end

local function show_hud_buttons(player, button_list)
    local name = player:get_player_name()
    if not cmd_mode[name] then return end

    -- Кнопки рушія (великі, як кнопки керування) замість малих HUD-картинок
    if human_fortress.rts and human_fortress.rts.is_active(name) then
        local list = {}
        for _, b in ipairs(button_list) do
            list[#list + 1] = { key = b.key, icon = b.icon, action = ACTION_KEYS[b.key] or false }
        end
        human_fortress.rts.set_buttons(player, list)
        return
    end

    -- запасний варіант: HUD-кнопки (клієнт без RTS-режиму)
    clear_hud_buttons(player)
    cmd_mode[name].hud_buttons = {}

    local count = #button_list
    local spacing = 0.09
    local start_x = 0.5 - (count - 1) * spacing / 2

    for i, b in ipairs(button_list) do
        local id = player:hud_add({
            hud_elem_type = "image",
            type = "image",
            text = b.icon,
            position = {x = start_x + (i - 1) * spacing, y = 0.93},
            scale = {x = 4.5, y = 4.5},
            alignment = {x = 0, y = 0},
            name = "hf_btn_" .. b.key,
            touchable = true,
            z_index = 100,
        })
        cmd_mode[name].hud_buttons[b.key] = id
    end
end

local function select_tool(player, tool_name)
    local inv = player:get_inventory()
    local idx = player:get_wield_index()
    local stack = ItemStack(tool_name .. " 1")
    stack:get_meta():set_float("range", CMD_REACH)
    inv:set_stack("main", idx, stack)
    if human_fortress.rts then
        human_fortress.rts.set_active(player, TOOL_KEY[tool_name])
    end
end

local function handle_button(player, key)
    local b = BUTTON_LOOKUP[key]
    if not b then return end

    local name = player:get_player_name()
    if not cmd_mode[name] then return end

    if key == "deselect" then
        set_selected_unit_ids(player, {})
        select_tool(player, "human_fortress:cmd_select")
        minetest.chat_send_player(name, "❎ Виділення знято")
        return
    end

    if b.tool == "human_fortress:cmd_exit" then
        exit_command_mode(player)
        return
    end

    if b.tool == "human_fortress:build_confirm" then
        select_tool(player, b.tool)
        local def = minetest.registered_tools[b.tool]
        if def and def.on_use then def.on_use(player:get_wielded_item(), player) end
        return
    end
    if b.tool == "human_fortress:build_cancel" then
        select_tool(player, b.tool)
        local def = minetest.registered_tools[b.tool]
        if def and def.on_use then def.on_use(player:get_wielded_item(), player) end
        return
    end
    if b.tool == "human_fortress:build_rotate" then
        select_tool(player, b.tool)
        local def = minetest.registered_tools[b.tool]
        if def and def.on_place then def.on_place(player:get_wielded_item(), player, nil) end
        return
    end

    select_tool(player, b.tool)
    minetest.chat_send_player(name, "🎯 Вибрано: " .. key .. " — тапни по цілі на екрані")
end

-- старі HUD-кнопки (запасний варіант)
core.register_on_hud_touch(function(player, hud_element_name)
    local key = hud_element_name:match("^hf_btn_(.+)$")
    if key then handle_button(player, key) end
end)

-- кнопки рушія: клієнт шле поле rts_button
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "" and type(fields.rts_button) == "string" then
        handle_button(player, fields.rts_button)
    end
end)

-- ============================================
-- ПРЕВ'Ю БУДІВЕЛЬ
-- ============================================

local GHOST_VISUAL_SIZE = 1.0
local GHOST_POS_OFFSET  = 0
local SCHEMATIC_CACHE = {}

local function get_schematic_data(building_type)
    if SCHEMATIC_CACHE[building_type] ~= nil then
        return SCHEMATIC_CACHE[building_type]
    end
    local schematic = BUILDING_SCHEMATICS and BUILDING_SCHEMATICS[building_type]
    if not schematic then
        SCHEMATIC_CACHE[building_type] = false
        return false
    end
    local filepath = minetest.get_modpath("human_fortress") .. "/schematics/" .. schematic.schematic
    local data = minetest.read_schematic(filepath, {})
    SCHEMATIC_CACHE[building_type] = data or false
    return SCHEMATIC_CACHE[building_type]
end

local function rotate_xz(x, z, sx, sz, rotation)
    if rotation == 90 then
        return z, sx - 1 - x
    elseif rotation == 180 then
        return sx - 1 - x, sz - 1 - z
    elseif rotation == 270 then
        return sz - 1 - z, x
    end
    return x, z
end

local function get_ghost_blocks(building_type, anchor_pos, rotation)
    local data = get_schematic_data(building_type)
    if not data then return {} end

    local sx, sy, sz = data.size.x, data.size.y, data.size.z
    local blocks = {}

    local i = 1
    for z = 0, sz - 1 do
        for y = 0, sy - 1 do
            for x = 0, sx - 1 do
                local cell = data.data[i]
                i = i + 1
                if cell and cell.name ~= "air" and cell.name ~= "ignore" then
                    local prob = cell.prob or cell.param1 or 255
                    if prob > 1 then
                        local ox, oz = rotate_xz(x, z, sx, sz, rotation)
                        table.insert(blocks, {
                            pos = {
                                x = anchor_pos.x + ox,
                                y = anchor_pos.y + y,
                                z = anchor_pos.z + oz,
                            },
                            node = cell.name,
                        })
                    end
                end
            end
        end
    end

    return blocks
end

local function clear_preview(player_name)
    local pdata = cmd_mode[player_name]
    if not pdata then return end
    if pdata.preview_objs then
        for _, obj in ipairs(pdata.preview_objs) do
            if obj and obj:is_valid() then
                obj:remove()
            end
        end
    end
    pdata.preview_objs = nil
    pdata.preview_pos = nil
end

local function place_preview(player_name, pos)
    local pdata = cmd_mode[player_name]
    if not pdata or not pdata.build then return end
    local btype = pdata.build.selected_type
    if not btype then return end

    local binfo = BUILDING_PREVIEWS[btype]
    if not binfo then
        minetest.chat_send_player(player_name, "❌ Немає даних для типу: " .. btype)
        return
    end

    clear_preview(player_name)

    local rotation = (pdata.build.rotation or 0) % 360
    local blocks = get_ghost_blocks(btype, pos, rotation)

    if #blocks == 0 then
        local center = {
            x = pos.x + GHOST_POS_OFFSET,
            y = pos.y + GHOST_POS_OFFSET,
            z = pos.z + GHOST_POS_OFFSET,
        }
        local obj = minetest.add_entity(center, "human_fortress:ghost_preview")
        if obj then
            obj:set_properties({ wield_item = binfo.preview_node or "default:glass" })
            pdata.preview_objs = { obj }
        end
    else
        local objs = {}
        for _, block in ipairs(blocks) do
            local center = {
                x = block.pos.x + GHOST_POS_OFFSET,
                y = block.pos.y + GHOST_POS_OFFSET,
                z = block.pos.z + GHOST_POS_OFFSET,
            }
            local obj = minetest.add_entity(center, "human_fortress:ghost_preview")
            if obj then
                obj:set_properties({ wield_item = block.node })
                table.insert(objs, obj)
            end
        end
        pdata.preview_objs = objs
    end

    pdata.preview_pos = pos

    local cur = minetest.get_node(pos)
    local is_free = (cur.name == "air" or
                     cur.name == "default:grass_1" or
                     cur.name:find("^default:grass"))
    if is_free then
        minetest.chat_send_player(player_name, "✨ Місце вільне — можна будувати! (підтверди або перемісти)")
    else
        minetest.chat_send_player(player_name, "⚠️ Увага: на цьому місці щось є! Фантом показано, але будівництво може не вдатись.")
    end
end

-- ============================================
-- БУДІВНИЦТВО
-- ============================================

local function build_structure(player_name, building_type, pos, rotation)
    if not BUILDING_SCHEMATICS or not BUILDING_SCHEMATICS[building_type] then
        minetest.chat_send_player(player_name, "❌ Немає схеми для: " .. tostring(building_type))
        return false
    end
    local schematic = BUILDING_SCHEMATICS[building_type]
    rotation = rotation or 0

    local cur = minetest.get_node(pos)
    if cur.name ~= "air" and
       cur.name ~= "default:grass_1" and
       not cur.name:find("^default:grass") then
        minetest.chat_send_player(player_name, "❌ Будівництво скасовано! На місці знаходиться: " .. cur.name)
        return false
    end

    if human_fortress.edos_data and human_fortress.edos_data[player_name] and schematic.cost then
        local resources = human_fortress.edos_data[player_name]
        for res, amount in pairs(schematic.cost) do
            if (resources[res] or 0) < amount then
                minetest.chat_send_player(player_name, "❌ Недостатньо ресурсів: " .. res)
                return false
            end
        end
        for res, amount in pairs(schematic.cost) do
            resources[res] = resources[res] - amount
        end
    end

    local filepath = minetest.get_modpath("human_fortress") .. "/schematics/" .. schematic.schematic

    local file = io.open(filepath, "rb")
    if not file then
        minetest.chat_send_player(player_name, "❌ Файл схеми не знайдено: " .. tostring(schematic.schematic))
        return false
    end
    file:close()

    local rotation_str = tostring(rotation)
    local result = minetest.place_schematic(pos, filepath, rotation_str, nil, false)

    if not result then
        minetest.chat_send_player(player_name, "❌ Не вдалося звести будівлю!")
        return false
    end

    if schematic.on_built then
        schematic.on_built(player_name, pos)
    end

    minetest.chat_send_player(player_name, "🏗️ Будівлю зведено!")
    return true
end

local function give_build_inventory(player, building_type)
    local name = player:get_player_name()
    if not cmd_mode[name] then cmd_mode[name] = {} end
    if not cmd_mode[name].build then cmd_mode[name].build = {} end
    cmd_mode[name].build.selected_type = building_type
    cmd_mode[name].build.rotation = cmd_mode[name].build.rotation or 0
    local start_pos = cmd_mode[name].build.pos or player:get_pos()
    cmd_mode[name].placed_previews = cmd_mode[name].placed_previews or {}

    player:hud_set_flags({hotbar = false})
    show_hud_buttons(player, BUILD_BUTTONS)

    local binfo = BUILDING_PREVIEWS[building_type]
    local label = binfo and binfo.label or building_type
    minetest.chat_send_player(name, "🏗️ Вибрано: " .. label)
    minetest.chat_send_player(name, "📌 'перемістити' → тапни по блоку")
    minetest.chat_send_player(name, "🔄 'повернути' | ✅ 'підтвердити' | ❌ 'скасувати'")

    if start_pos then
        place_preview(name, start_pos)
    end
end

local function give_command_inventory(player)
    player:get_inventory():set_list("main", {})
    player:hud_set_flags({hotbar = false})
    show_hud_buttons(player, MAIN_BUTTONS)
end

-- ============================================
-- ВХІД / ВИХІД
-- ============================================
local function set_cmd_physics(player, on)
    if on then
        player:set_physics_override({gravity = 0})
        local groups = player:get_armor_groups()
        groups.fall_damage_add_percent = -100
        player:set_armor_groups(groups)
        player:set_velocity(vector.new(0, 0, 0))
    else
        player:set_physics_override({gravity = 1})
        local groups = player:get_armor_groups()
        groups.fall_damage_add_percent = nil
        player:set_armor_groups(groups)
    end
end

local function set_hud_hidden(player, hidden)
    player:hud_set_flags({
        hotbar = not hidden,
    })
    -- прибрати/повернути підсвітку вибраного слота
    player:hud_set_hotbar_itemcount(hidden and 1 or 8)
end

local function enter_command_mode(player)
    local name = player:get_player_name()
    if cmd_mode[name] then return end
    local inv = player:get_inventory()
    local pos = player:get_pos()
    cmd_mode[name] = { inv = {}, pos = pos, build = {}, placed_previews = {}, base_y = pos.y }

    for i = 1, inv:get_size("main") do
        local stack = inv:get_stack("main", i)
        if not stack:is_empty() then cmd_mode[name].inv[i] = stack:to_string() end
    end

    -- Камера зверху (рушій): палець рухає камеру, кнопки руху сховані.
    -- Гравець не літає і не телепортується - клієнт сам веде камеру.
    human_fortress.rts.enter(player, pos)
    give_command_inventory(player)
    set_reach(player, CMD_REACH)
    save_cmd_mode(name)

    set_hud_hidden(player, true)  -- ховаємо хотбар

    -- одразу вибираємо розумний інструмент: тап по юніту - виділити,
    -- тап по землі - йти, тап по ворогу - атакувати
    select_tool(player, "human_fortress:cmd_select")

    minetest.chat_send_player(name, "🎮 Режим командування активовано!")
end

exit_command_mode = function(player)
    local name = player:get_player_name()
    clear_preview(name)
    clear_hud_buttons(player)
    local data = cmd_mode[name]
    if not data then return end

    human_fortress.rts.exit(player)
    box_corner[name] = nil
    if data.pos then player:set_pos(data.pos) end
    player:set_velocity(vector.new(0, 0, 0))
    set_cmd_physics(player, false)
    set_reach(player, NORMAL_REACH)

    local inv = player:get_inventory()
    inv:set_list("main", {})
    if data.inv then
        for i, stack in pairs(data.inv) do
            inv:set_stack("main", i, ItemStack(stack))
        end
    end

    cmd_mode[name] = nil
    storage:set_string("cmd_mode_" .. name, "")

    set_hud_hidden(player, false)
    player:hud_set_hotbar_itemcount(9)

    minetest.chat_send_player(name, "🚪 Вийшли з режиму командування")
end

function toggle_command_mode(player)
    local name = player:get_player_name()
    if cmd_mode[name] then
        exit_command_mode(player)
    else
        enter_command_mode(player)
    end
end

-- ============================================
-- ДОПОМІЖНА ФУНКЦІЯ ПОЛЬОТУ
-- ============================================

local function apply_fly_mode(player)
    local name = player:get_player_name()
    local privs = minetest.get_player_privs(name)
    privs.fly = true
    minetest.set_player_privs(name, privs)
end

-- (стара прив'язка висоти польоту видалена: тепер камеру веде клієнт)

-- Вихід гравця з гри → вимикаємо режим
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if cmd_mode[name] then
        exit_command_mode(player)
    end
end)

-- Зупинка сервера → вимикаємо режим у всіх
minetest.register_on_shutdown(function()
    for _, player in ipairs(minetest.get_connected_players()) do
        if cmd_mode[player:get_player_name()] then
            exit_command_mode(player)
        end
    end
end)

-- Вхід: якщо лишився збережений режим (краш сервера), коректно виходимо з нього
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local saved = load_cmd_mode(name)
    if saved then
        cmd_mode[name] = saved
        cmd_mode[name].build = cmd_mode[name].build or {}
        cmd_mode[name].placed_previews = {}
        exit_command_mode(player)
    else
        player:hud_set_flags({hotbar = true})
    end
    set_reach(player, NORMAL_REACH)
end)
-- ============================================
-- 0. ПРИЦІЛ (інфо про юніта)
-- ============================================

local sight_target = {}

-- розблоковано апгрейд у гравця? (те саме, що get_player_upgrades, але не залежить від порядку в файлі)
local function player_has_upgrade(name, id)
    local file = io.open(minetest.get_worldpath() .. "/upgrades.json", "r")
    if not file then return false end
    local content = file:read("*all")
    file:close()
    local data = minetest.parse_json(content) or {}
    return (data[name] and data[name][id]) and true or false
end

-- ціна покращення = різниця цін елітного і звичайного рибака
local function fisher_upgrade_cost()
    local ul = human_fortress.units_list or {}
    local from = ul.fisherman and ul.fisherman.cost or {}
    local to   = ul.elite_fisherman and ul.elite_fisherman.cost or {}
    local c = {}
    for res, amount in pairs(to) do
        local diff = amount - (from[res] or 0)
        if diff > 0 then c[res] = diff end
    end
    return c
end

local RES_ICONS = {wood = "🌳", stone = "💎", food = "🌾", score = "⭐"}
local function cost_to_text(cost)
    local t = {}
    for res, amount in pairs(cost) do
        table.insert(t, (RES_ICONS[res] or res) .. amount)
    end
    return table.concat(t, " ")
end

local function show_unit_info(player, unit_id)
    local name = player:get_player_name()
    local obj, ent = find_unit_by_id(unit_id)
    if not ent then
        minetest.chat_send_player(name, "❌ Юніт недоступний")
        return
    end

    local inv = ent.inventory or {}
    local wood  = inv.wood  or 0
    local stone = inv.stone or 0
    local food  = inv.food  or 0
    local total = wood + stone + food
    local carry_max = ent.carry_max or 300

    local loot_n = 0
    for _, c in pairs(inv.loot or {}) do loot_n = loot_n + c end

    local uname = "Юніт"
    for _, u in pairs(human_fortress.units_list or {}) do
        if u.entity == ent.name then uname = u.name break end
    end

    local order_names = {
        move = "Рух", gather = "Збір", unload = "Розвантаження",
        attack_target = "Атака", stand = "Очікує",
    }
    local order = order_names[ent.order or "stand"] or tostring(ent.order)

    local hp = math.floor(ent.health or 0)
    local hp_max = ent.hp_max or (ent.initial_properties and ent.initial_properties.hp_max) or 20

    -- кнопка "Покращити": тільки для звичайного рибака, якщо спеціалізація розблокована
    local can_upgrade = ent.name == "human_fortress:fisherman"
        and player_has_upgrade(name, "elite_fisherman")

    local height = can_upgrade and 7.5 or 6.5
    local fs = "size[6," .. height .. "]" ..
        "bgcolor[#0A0A1A;true]" ..
        "box[0,0;6,0.8;#2D2D44]" ..
        "label[0.3,0.2;👷 " .. minetest.formspec_escape(uname) .. "]" ..
        "label[0.3,1.1;❤️ HP: " .. hp .. " / " .. hp_max .. "]" ..
        "label[0.3,1.6;📋 Наказ: " .. minetest.formspec_escape(order) .. "]" ..
        "label[0.3,2.3;🎒 Інвентар (" .. total .. "/" .. carry_max .. "):]" ..
        "label[0.6,2.8;🌳 Ефір: " .. wood .. "]" ..
        "label[0.6,3.3;💎 Версиформ: " .. stone .. "]" ..
        "label[0.6,3.8;🌾 Рис/риба: " .. food .. "]"

    if loot_n > 0 then
        fs = fs .. "label[0.6,4.3;🎁 Здобич: " .. loot_n .. "]"
    end

    local y = 4.8
    if total > 0 or loot_n > 0 then
        fs = fs .. "button[0.5," .. y .. ";5,0.9;unload;📥 Здати ресурси в Ратушу]"
    else
        fs = fs .. "label[0.6," .. (y + 0.1) .. ";(інвентар порожній)]"
    end
    y = y + 0.9

    if can_upgrade then
        fs = fs .. "button[0.5," .. y .. ";5,0.9;upgrade;⬆ Покращити до Елітного (" ..
            minetest.formspec_escape(cost_to_text(fisher_upgrade_cost())) .. ")]"
        y = y + 0.9
    end
    fs = fs .. "button_exit[0.5," .. y .. ";5,0.8;close;Закрити]"

    sight_target[name] = unit_id
    minetest.show_formspec(name, "human_fortress:sight", fs)
end

-- заміна звичайного рибака на елітного (unit_id, інвентар і наказ зберігаються)
local function upgrade_fisherman(player, unit_id)
    local name = player:get_player_name()
    local obj, ent = find_unit_by_id(unit_id)

    if not ent or not ent.unit_data or ent.unit_data.owner ~= name then
        minetest.chat_send_player(name, "❌ Юніт недоступний")
        return
    end
    if ent.name ~= "human_fortress:fisherman" then
        minetest.chat_send_player(name, "❌ Цього юніта не можна покращити")
        return
    end
    if not player_has_upgrade(name, "elite_fisherman") then
        minetest.chat_send_player(name, "❌ Спеціалізацію «Елітний рибак» ще не розблоковано!")
        return
    end

    -- перевірка і списання ресурсів
    local cost = fisher_upgrade_cost()
    local res = human_fortress.edos_data and human_fortress.edos_data[name]
    if res then
        for r, amount in pairs(cost) do
            if (res[r] or 0) < amount then
                minetest.chat_send_player(name, "❌ Недостатньо ресурсів: " .. r .. " (потрібно " .. amount .. ")")
                return
            end
        end
        for r, amount in pairs(cost) do res[r] = res[r] - amount end
    end

    -- зберігаємо стан старого юніта
    local pos = obj:get_pos()
    local saved = {
        unit_id = ent.unit_data.unit_id,
        inventory = ent.inventory,
        order = ent.order,
        goto_destination = ent.goto_destination,
        last_gather_pos = ent.last_gather_pos,
    }
    obj:remove()

    local new_obj = minetest.add_entity(pos, "human_fortress:elite_fisherman")
    local new_ent = new_obj and new_obj:get_luaentity()
    if not new_ent then
        minetest.chat_send_player(name, "❌ Не вдалося створити елітного рибака")
        return
    end

    new_ent.unit_data = new_ent.unit_data or {}
    new_ent.unit_data.unit_id = saved.unit_id   -- той самий id: виділення зберігається
    new_ent.unit_data.owner = name
    new_ent.inventory = saved.inventory or {wood = 0, stone = 0, food = 0}
    new_ent.order = saved.order
    new_ent.goto_destination = saved.goto_destination
    new_ent.last_gather_pos = saved.last_gather_pos
    new_ent.fish_spot = nil
    new_ent.health = new_ent.hp_max or new_ent.health   -- повне HP

    minetest.add_particlespawner({
        amount = 30, time = 0.5,
        minpos = {x = pos.x - 0.5, y = pos.y, z = pos.z - 0.5},
        maxpos = {x = pos.x + 0.5, y = pos.y + 1.5, z = pos.z + 0.5},
        minvel = {x = -1, y = 1, z = -1}, maxvel = {x = 1, y = 3, z = 1},
        minexptime = 0.6, maxexptime = 1.2,
        minsize = 1, maxsize = 3,
        texture = "bubble.png", glow = 12,
    })
    minetest.chat_send_player(name, "⬆ Рибак покращений до Елітного!")
end

minetest.register_tool("human_fortress:cmd_sight", {
    description = "🎮 Приціл (тап по юніту — інфо, наказ здати ресурси, покращення)",
    inventory_image = "human_fortress_cmd_sight.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return itemstack end

        if pointed_thing and pointed_thing.type == "object" then
            local ent = pointed_thing.ref and pointed_thing.ref:get_luaentity()
            if ent and ent.unit_data and ent.unit_data.unit_id then
                if ent.unit_data.owner ~= name then
                    minetest.chat_send_player(name, "⚠️ Це не твій юніт!")
                else
                    show_unit_info(user, ent.unit_data.unit_id)
                end
            else
                minetest.chat_send_player(name, "❌ Це не юніт")
            end
        else
            minetest.chat_send_player(name, "🎯 Тапни по юніту")
        end
        return itemstack
    end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "human_fortress:sight" then return end
    local name = player:get_player_name()
    if not cmd_mode[name] then return end

    if fields.unload then
        local uid = sight_target[name]
        local obj, ent = find_unit_by_id(uid)
        if ent and ent.unit_data and ent.unit_data.owner == name then
            ent.unit_data.command = "unload"
            ent.unit_data.target = nil
            minetest.chat_send_player(name, "📥 Наказ здати ресурси відправлено")
        else
            minetest.chat_send_player(name, "❌ Юніт недоступний")
        end
        minetest.close_formspec(name, "human_fortress:sight")
        sight_target[name] = nil

    elseif fields.upgrade then
        local uid = sight_target[name]
        upgrade_fisherman(player, uid)
        minetest.close_formspec(name, "human_fortress:sight")
        sight_target[name] = nil
    end
end)
-- ============================================
-- 1. ВИДІЛЕННЯ ЮНІТІВ
-- ============================================

-- Розумний інструмент для керування тапом (як у RTS):
--   тап по своєму юніту   - виділити його (ще раз - зняти виділення)
--   подвійний тап по юніту - виділити всіх однотипних поруч
--   тап по землі          - якщо є виділені, вони йдуть туди;
--                           якщо ні - виділяються юніти в радіусі 10
--   тап по ворогу         - виділені юніти атакують
--   довгий тап            - виділити всіх своїх юнітів
local last_unit_tap = {}
local DOUBLE_TAP_TIME = 0.5

local function select_all_own(user, radius, center, same_kind)
    local name = user:get_player_name()
    local ids = {}
    local objs = minetest.get_objects_inside_radius(center, radius)
    for _, obj in ipairs(objs) do
        local ent = obj:get_luaentity()
        if ent and ent.unit_data and ent.unit_data.owner == name and ent.unit_data.unit_id
                and (not same_kind or ent.name == same_kind) then
            table.insert(ids, ent.unit_data.unit_id)
        end
    end
    return ids
end

minetest.register_tool("human_fortress:cmd_select", {
    description = "🎮 Керування (тап по юніту — виділити, по землі — йти, по ворогу — атакувати, довгий тап — всі юніти)",
    inventory_image = "human_fortress_cmd_select.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end
        local selected = get_selected_unit_ids(user)
        local rts = human_fortress.rts

        if pointed_thing and pointed_thing.type == "object" then
            local obj = pointed_thing.ref
            local ent = obj and obj:get_luaentity()
            local ud = ent and ent.unit_data

            if ud and ud.unit_id and ud.owner == name then
                -- свій юніт: виділення
                local uid = ud.unit_id
                local now = minetest.get_us_time() / 1000000
                local last = last_unit_tap[name]
                if last and last.uid == uid and now - last.t < DOUBLE_TAP_TIME then
                    local ids = select_all_own(user, 60, obj:get_pos(), ent.name)
                    set_selected_unit_ids(user, ids)
                    minetest.chat_send_player(name, "✅ Виділено однотипних юнітів: " .. #ids)
                    last_unit_tap[name] = nil
                else
                    if #selected == 1 and selected[1] == uid then
                        set_selected_unit_ids(user, {})
                    else
                        set_selected_unit_ids(user, {uid})
                    end
                    last_unit_tap[name] = { uid = uid, t = now }
                end
            elseif #selected > 0 and obj then
                -- ворог (чужий юніт або моб): атакуємо
                local p = obj:get_pos()
                if p then
                    local sent, queued = send_command_to_selected(user, "attack", p)
                    if sent + queued > 0 and rts then
                        rts.flash(name, p, rts.color_for("attack"))
                    end
                end
            end

        elseif pointed_thing and pointed_thing.type == "node" then
            local pos = pointed_thing.under
            if #selected > 0 then
                local target = { x = pos.x, y = pos.y + 1, z = pos.z }
                local sent, queued = send_command_to_selected(user, "move", target)
                if sent + queued > 0 and rts then
                    rts.flash(name, { x = pos.x, y = pos.y + 1, z = pos.z }, rts.color_for("move"))
                end
            else
                local ids = select_all_own(user, 10, pos)
                set_selected_unit_ids(user, ids)
                minetest.chat_send_player(name, "✅ Виділено юнітів: " .. #ids)
            end
        end
        return itemstack
    end,

    -- довгий тап: виділити всіх своїх юнітів
    on_place = function(itemstack, placer)
        local name = placer:get_player_name()
        if not cmd_mode[name] then return end
        local ids = select_all_own(placer, 100, placer:get_pos())
        set_selected_unit_ids(placer, ids)
        minetest.chat_send_player(name, "✅ Виділено ВСІХ юнітів: " .. #ids)
        return itemstack
    end,
    on_secondary_use = function(itemstack, placer)
        local name = placer:get_player_name()
        if not cmd_mode[name] then return end
        local ids = select_all_own(placer, 100, placer:get_pos())
        set_selected_unit_ids(placer, ids)
        minetest.chat_send_player(name, "✅ Виділено ВСІХ юнітів: " .. #ids)
        return itemstack
    end,
})

-- Виділення рамкою: тап у перший кут, тап у протилежний кут.
-- (камера дивиться завжди з одного боку, тому рамка співпадає з екраном)

minetest.register_tool("human_fortress:cmd_box", {
    description = "🎮 Виділення рамкою (тап у перший кут, потім у протилежний)",
    inventory_image = "human_fortress_cmd_box.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end
        if not (pointed_thing and pointed_thing.type == "node") then return itemstack end
        local rts = human_fortress.rts
        local p = pointed_thing.under
        local a = box_corner[name]

        if not a then
            box_corner[name] = { x = p.x, y = p.y, z = p.z }
            if rts then rts.flash(name, p, "#ffffff") end
            minetest.chat_send_player(name, "📐 Перший кут є. Тапни протилежний кут.")
            return itemstack
        end

        box_corner[name] = nil
        local x1, x2 = math.min(a.x, p.x), math.max(a.x, p.x)
        local z1, z2 = math.min(a.z, p.z), math.max(a.z, p.z)
        local ids = {}
        local center = { x = (x1 + x2) / 2, y = (a.y + p.y) / 2, z = (z1 + z2) / 2 }
        local radius = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) / 2 + 40
        for _, obj in ipairs(minetest.get_objects_inside_radius(center, radius)) do
            local ent = obj:get_luaentity()
            local ud = ent and ent.unit_data
            if ud and ud.owner == name and ud.unit_id then
                local o = obj:get_pos()
                if o and o.x >= x1 - 0.5 and o.x <= x2 + 0.5 and o.z >= z1 - 0.5 and o.z <= z2 + 0.5 then
                    table.insert(ids, ud.unit_id)
                end
            end
        end
        set_selected_unit_ids(user, ids)
        if rts then rts.draw_rect(name, a, p, "#4cff4c", 1.5) end
        minetest.chat_send_player(name, "✅ Виділено рамкою: " .. #ids)
        -- повертаємось до звичайного керування тапом
        select_tool(user, "human_fortress:cmd_select")
        return itemstack
    end,
})

-- Виділення рамкою пальцем (довго потримати і тягнути): рушій надсилає поле
-- rts_box з кутами рамки, а ми вибираємо юнітів, що потрапили в неї.
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "" or not fields.rts_box then return end
    local name = player:get_player_name()
    if not cmd_mode[name] or not human_fortress.rts then return end
    local ids = human_fortress.rts.select_in_box(name, fields.rts_box)
    if not ids then return end
    set_selected_unit_ids(player, ids)
    minetest.chat_send_player(name, "✅ Виділено рамкою: " .. #ids)
end)

-- ============================================
-- 2. РУХ ЮНІТІВ
-- ============================================

minetest.register_tool("human_fortress:cmd_move", {
    description = "🎮 Рух юнітів (ПКМ - точка призначення)",
    inventory_image = "human_fortress_cmd_move.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end

        if pointed_thing and pointed_thing.type == "node" then
            local pos = pointed_thing.under
            local target = { x = pos.x + 0.5, y = pos.y + 1, z = pos.z + 0.5 }
            local sent, queued = send_command_to_selected(user, "move", target)
            if sent + queued > 0 then
                minetest.chat_send_player(name, "🚶 Рух: " .. (sent + queued) .. " юнітів")
            end
        end
        return itemstack
    end
})

-- ============================================
-- 3. ЗБІР РЕСУРСІВ
-- ============================================

minetest.register_tool("human_fortress:cmd_gather", {
    description = "🎮 Збір ресурсів (ПКМ - по ресурсу)",
    inventory_image = "human_fortress_cmd_gather.png",
    liquids_pointable = true,

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end

        if pointed_thing and pointed_thing.type == "node" then
            local pos = pointed_thing.under
            local node = minetest.get_node(pos)
            local node_def = minetest.registered_nodes[node.name]
            local is_resource = false

            if (node_def and node_def.groups and node_def.groups.ether_tree) or
               node.name:find("tree") or node.name:find("wood") or node.name:find("ether") then
                is_resource = true
            elseif node.name:find("stone") or node.name:find("cobble") or node.name:find("versiforn") then
                is_resource = true
            elseif node.name:find("rice") or node.name:find("food") then
    is_resource = true
elseif minetest.get_item_group(node.name, "water") > 0 then
    is_resource = true
            end

            if is_resource then
                local sent, queued = send_command_to_selected(user, "gather", pos)
                if sent + queued > 0 then
                    minetest.chat_send_player(name, "📦 Збір: " .. (sent + queued) .. " юнітів")
                end
            else
                minetest.chat_send_player(name, "❌ Це не ресурс!")
            end
        end
        return itemstack
    end
})

-- ============================================
-- 4. БУДІВНИЦТВО
-- ============================================

local function get_player_upgrades(name)
    local path = minetest.get_worldpath() .. "/upgrades.json"
    local file = io.open(path, "r")
    if not file then return {} end
    local content = file:read("*all")
    file:close()
    local data = minetest.parse_json(content) or {}
    return data[name] or {}
end

minetest.register_tool("human_fortress:cmd_build", {
    description = "🎮 Будівництво (ПКМ по землі — відкрити меню)",
    inventory_image = "human_fortress_cmd_build.png",

    on_place = function(itemstack, placer, pointed_thing)
        local name = placer:get_player_name()
        if not cmd_mode[name] then
            minetest.chat_send_player(name, "❌ Ти не в режимі командування!")
            return itemstack
        end

        if pointed_thing and pointed_thing.type == "node" then
            local pos = pointed_thing.under
            if not cmd_mode[name].build then cmd_mode[name].build = {} end
            cmd_mode[name].build.pos = pos

            local my_upgrades = get_player_upgrades(name)

            local fs = "size[6,9]" ..
                "bgcolor[#0A0A1A;true]" ..
                "box[0,0;6,0.8;#2D2D44]" ..
                "label[0.5,0.2;🏗️ ВИБІР БУДІВЛІ]"
            local x = 0.4
local y = 1.1
local column = 0

for btype, bdata in pairs(BUILDING_PREVIEWS) do
    if my_upgrades[btype] then
        local schematic = BUILDING_SCHEMATICS and BUILDING_SCHEMATICS[btype] or {}
        local icon = schematic.icon or ("human_fortress_" .. btype .. ".png")
        local cost = schematic.cost or {}

        local cost_text = "💰 Ціна:"
        if cost.score then
            cost_text = cost_text .. " " .. cost.score .. " очок"
        end
        if cost.wood then
            cost_text = cost_text .. "\nЕфіру " .. cost.wood
        end
        if cost.stone then
            cost_text = cost_text .. "\nВерсиформу " .. cost.stone
        end
        if cost.food then
            cost_text = cost_text .. "\nРису " .. cost.food
        end

        local tooltip = (schematic.name or bdata.label) .. "\n" .. cost_text

        fs = fs ..
            "image_button[" .. x .. "," .. y .. ";1.5,1.5;" ..
            minetest.formspec_escape(icon) .. ";build_" .. btype .. ";]" ..
            "tooltip[" .. x .. "," .. y .. ";1.5,1.5;" ..
            minetest.formspec_escape(tooltip) .. "]"

        column = column + 1

        if column >= 3 then
            column = 0
            x = 0.4
            y = y + 2.0
        else
            x = x + 1.85
        end
    end
end
            minetest.show_formspec(name, "human_fortress:build", fs)
        else
            minetest.chat_send_player(name, "❌ Натисни ПКМ на блок землі!")
        end
        return itemstack
    end
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "human_fortress:build" then return end
    local name = player:get_player_name()

    if not cmd_mode[name] or not cmd_mode[name].build then
        minetest.chat_send_player(name, "❌ Помилка: не в режимі командування")
        return
    end
    if not cmd_mode[name].build.pos then
        minetest.chat_send_player(name, "❌ Не вибрано позицію")
        return
    end

    for field, _ in pairs(fields) do
        if field:sub(1, 6) == "build_" then
            local building_type = field:sub(7)

            local my_upgrades = get_player_upgrades(name)
            if my_upgrades[building_type] then
                minetest.close_formspec(name, "human_fortress:build")
                give_build_inventory(player, building_type)
            else
                minetest.chat_send_player(name, "❌ Ця будівля ще не куплена!")
            end
            break
        end
    end
end)

-- ============================================
-- 5. АТАКА
-- ============================================

minetest.register_tool("human_fortress:cmd_attack", {
    description = "🎮 Атака (ПКМ - по ворогу або точці)",
    inventory_image = "human_fortress_cmd_attack.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end

        local target_pos = nil
        if pointed_thing and pointed_thing.type == "object" then
            local obj = pointed_thing.ref
            if obj then target_pos = obj:get_pos() end
        elseif pointed_thing and pointed_thing.type == "node" then
            target_pos = pointed_thing.under
        end

        if target_pos then
            local sent, queued = send_command_to_selected(user, "attack", target_pos)
            if sent + queued > 0 then
                minetest.chat_send_player(name, "⚔️ Атака: " .. (sent + queued) .. " юнітів")
            end
        end
        return itemstack
    end
})

-- ============================================
-- 6. УВІЙТИ В БУДІВЛЮ
-- ============================================

minetest.register_tool("human_fortress:cmd_enter", {
    description = "🎮 Увійти в будівлю",
    inventory_image = "human_fortress_cmd_enter.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end

        if pointed_thing and pointed_thing.type == "node" then
            local pos = pointed_thing.under
            local sent, queued = send_command_to_selected(user, "enter", pos)
            if sent + queued > 0 then
                minetest.chat_send_player(name, "🚪 Вхід: " .. (sent + queued) .. " юнітів")
            end
        end
        return itemstack
    end
})

-- ============================================
-- 7. РЕМОНТ
-- ============================================

minetest.register_tool("human_fortress:cmd_repair", {
    description = "🎮 Ремонт будівлі",
    inventory_image = "human_fortress_cmd_repair.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end

        if pointed_thing and pointed_thing.type == "node" then
            local pos = pointed_thing.under
            local sent, queued = send_command_to_selected(user, "repair", pos)
            if sent + queued > 0 then
                minetest.chat_send_player(name, "🔧 Ремонт: " .. (sent + queued) .. " юнітів")
            end
        end
        return itemstack
    end
})

-- ============================================
-- 8. ЗНИЩЕННЯ
-- ============================================

minetest.register_tool("human_fortress:cmd_destroy", {
    description = "🎮 Знищення будівлі (Shift+ПКМ)",
    inventory_image = "human_fortress_cmd_destroy.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] then return end
        local ctrl = user:get_player_control()

        if pointed_thing and pointed_thing.type == "node" and ctrl.aux1 then
            minetest.remove_node(pointed_thing.under)
            minetest.chat_send_player(name, "💥 Будівлю знищено!")
        elseif pointed_thing and pointed_thing.type == "node" then
            minetest.chat_send_player(name, "⚠️ Утримуй Shift для знищення")
        end
        return itemstack
    end
})

-- ============================================
-- 9. ВИХІД
-- ============================================

minetest.register_tool("human_fortress:cmd_exit", {
    description = "🚪 Вийти з режиму командування",
    inventory_image = "human_fortress_cmd_exit.png",

    on_use = function(itemstack, user)
        exit_command_mode(user)
        return itemstack
    end
})

-- ============================================
-- БУДІВЕЛЬНІ ІНСТРУМЕНТИ
-- ============================================

minetest.register_tool("human_fortress:build_move", {
    description = "📌 Перемістити фантом (ПКМ по блоку)",
    inventory_image = "human_fortress_cmd_moveb.png",

    on_place = function(itemstack, placer, pointed_thing)
        local name = placer:get_player_name()
        if not cmd_mode[name] or not cmd_mode[name].build then return itemstack end

        if pointed_thing and pointed_thing.type == "node" then
            local pos = pointed_thing.above
            cmd_mode[name].build.pos = pos
            place_preview(name, pos)
            minetest.chat_send_player(name, "📌 Фантом переміщено: " .. minetest.pos_to_string(pos))
        end
        return itemstack
    end
})

minetest.register_tool("human_fortress:build_rotate", {
    description = "🔄 Повернути (ЛКМ = -90°, ПКМ = +90°)",
    inventory_image = "human_fortress_cmd_select.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] or not cmd_mode[name].build then return itemstack end
        local rot = (cmd_mode[name].build.rotation or 0)
        rot = (rot - 90) % 360
        cmd_mode[name].build.rotation = rot
        if cmd_mode[name].preview_pos then
            place_preview(name, cmd_mode[name].preview_pos)
        end
        minetest.chat_send_player(name, "🔄 Поворот: " .. rot .. "° (ЛКМ = -90°)")
        return itemstack
    end,

    on_place = function(itemstack, placer, pointed_thing)
        local name = placer:get_player_name()
        if not cmd_mode[name] or not cmd_mode[name].build then return itemstack end
        local rot = (cmd_mode[name].build.rotation or 0)
        rot = (rot + 90) % 360
        cmd_mode[name].build.rotation = rot
        if cmd_mode[name].preview_pos then
            place_preview(name, cmd_mode[name].preview_pos)
        end
        minetest.chat_send_player(name, "🔄 Поворот: " .. rot .. "° (ПКМ = +90°)")
        return itemstack
    end
})

minetest.register_tool("human_fortress:build_confirm", {
    description = "✅ Підтвердити будівництво",
    inventory_image = "human_fortress_cmd_buildc.png",

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not cmd_mode[name] or not cmd_mode[name].build then return itemstack end

        local bdata = cmd_mode[name].build
        local pos = cmd_mode[name].preview_pos or bdata.pos
        local building_type = bdata.selected_type
        local rotation = bdata.rotation or 0

        if not pos then
            minetest.chat_send_player(name, "❌ Постав фантом спочатку (перемістити)!")
            return itemstack
        end
        if not building_type then
            minetest.chat_send_player(name, "❌ Не вибрано тип будівлі!")
            return itemstack
        end

        minetest.chat_send_player(name, "🏗️ Будую " .. building_type .. " (поворот " .. rotation .. "°)...")

        clear_preview(name)
        if build_structure(name, building_type, pos, rotation) then
            cmd_mode[name].build = {}
            give_command_inventory(user)
        else
            place_preview(name, pos)
        end
        return itemstack
    end
})

minetest.register_tool("human_fortress:build_cancel", {
    description = "❌ Скасувати вибір будівлі",
    inventory_image = "human_fortress_cmd_exit.png",

    on_use = function(itemstack, user)
        local name = user:get_player_name()
        if not cmd_mode[name] then return itemstack end
        clear_preview(name)
        cmd_mode[name].build = {}
        give_command_inventory(user)
        minetest.chat_send_player(name, "↩️ Повернуто в режим командування")
        return itemstack
    end
})

-- ============================================
-- ДЕБАГ
-- ============================================

minetest.after(5, function()
    local path = minetest.get_modpath("human_fortress") .. "/schematics"
    minetest.chat_send_all("📁 Папка schematics: " .. path)
    local files = minetest.get_dir_list(path, false)
    if files and #files > 0 then
        for _, file in ipairs(files) do
            minetest.chat_send_all("   📄 " .. file)
        end
    else
        minetest.chat_send_all("⚠️ Папка порожня або не знайдена")
    end
end)

for _, tool in ipairs({
    "cmd_sight", "cmd_select", "cmd_box", "cmd_move", "cmd_gather", "cmd_build", "cmd_attack",
    "cmd_enter", "cmd_repair", "cmd_destroy", "cmd_exit",
    "build_move", "build_rotate", "build_confirm", "build_cancel",
}) do
    minetest.override_item("human_fortress:" .. tool, {
        range = CMD_REACH,
        -- на телефоні: короткий тап = використати інструмент (on_use),
        -- довгий тап = on_place
        touch_interaction = "short_dig_long_place",
    })
end

print("[Human Fortress] Система керування завантажена (стійка до вивантаження чанків)!")