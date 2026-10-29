-------------------------------------------------
-- Human Fortress RTS - Init файл
-------------------------------------------------

human_fortress = {
    players = {},
    edos_data = {},
    units = {},
    buildings = {},
    resources = {},
    selected_units = {},
    control_block = "human_fortress:control_block",
    control_stick = "human_fortress:control_stick"
}

local storage = minetest.get_mod_storage()
local path = minetest.get_modpath("human_fortress")
local world_path = minetest.get_worldpath()

BUILDING_MENUS = {}
minetest.log("action", "[HF] BUILDING_MENUS створено")

-- ============================================
-- ЗБЕРЕЖЕННЯ / ЗАВАНТАЖЕННЯ
-- ============================================

function human_fortress.save_data(name)
    local data = human_fortress.edos_data[name]
    if data then
        storage:set_string(name .. "_data", minetest.serialize(data))
    end
end

local function load_data(name)
    local raw_data = storage:get_string(name .. "_data")
    if raw_data and raw_data ~= "" then
        local data = minetest.deserialize(raw_data)
        data.skin     = data.skin     or "default"
        data.upgrades = data.upgrades or {}
        data.wood     = data.wood     or 0
        data.stone    = data.stone    or 0
        data.food     = data.food     or 0
        data.ether    = data.ether    or 0
        data.rice     = data.rice     or 0
        data.versi    = data.versi    or 0
        return data
    end
    return nil
end

-- ПОВЕРНЕНА функція set_player_level
function human_fortress.set_player_level(name, new_level)
    local data = human_fortress.edos_data[name]
    if not data then return end
    data.level = new_level
    local player = minetest.get_player_by_name(name)
    if player and edit_skin and edit_skin.update_player_skin then
        edit_skin.update_player_skin(player)
    end
    human_fortress.save_data(name)
    return true
end

-- ============================================
-- ЗАВАНТАЖЕННЯ ФАЙЛІВ
-- ============================================

dofile(path .. "/resources.lua")
dofile(path .. "/units.lua")

BUILDING_SCHEMATICS = {}
local building_files = {
    "townhall.lua",
    "rice_field.lua",
    "barracks.lua",
    "wall.lua",
    "tower.lua",
    "warehouse.lua",
    "market.lua",
    "carpenter_workshop.lua"
}

for _, file in ipairs(building_files) do
    local filepath = path .. "/buildings/" .. file
    local f = io.open(filepath, "r")
    if f then
        f:close()
        local building = dofile(filepath)
        if building and building.id and building.data then
            BUILDING_SCHEMATICS[building.id] = building.data
            minetest.log("action", "[HF] ✅ Додано: " .. building.id)
        else
            minetest.log("warning", "[HF] ⚠️ Файл " .. file .. " не повернув будівлю")
        end
    else
        minetest.log("warning", "[HF] ❌ Не знайдено: " .. filepath)
    end
end
dofile(path .. "/core_heart.lua")
dofile(path .. "/building_health.lua")
dofile(path .. "/commands.lua")
dofile(path .. "/ether_tree.lua")
dofile(path .. "/ai.lua")
dofile(path .. "/rts.lua")
dofile(path .. "/control_stick.lua")
dofile(path .. "/gui.lua")
dofile(path .. "/time.lua")
dofile(minetest.get_modpath("human_fortress") .. "/clock_menu.lua")
dofile(path .. "/node.lua")
dofile(path .. "/shop.lua")
dofile(path .. "/edos.lua")
dofile(path .. "/vilka_core.lua")
dofile(path .. "/vilka_menu.lua")
  dofile(minetest.get_modpath("human_fortress") .. "/golden_fish_ritual.lua")
dofile(path .. "/world.lua")
dofile(path .. "/upgrades.lua")
dofile(path .. "/words.lua")
dofile(path .. "/jackals.lua")
dofile(path .. "/minigame.lua")
-- ============================================
-- ПРИЄДНАННЯ ГРАВЦЯ
-- ============================================

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()

    human_fortress.players[name] = {
        units = {},
        buildings = {},
        selected = {},
        control_mode = 0,
        selection_area = {}
    }

    local saved_data = load_data(name)
    if saved_data then
        human_fortress.edos_data[name] = saved_data
        minetest.chat_send_player(name, "§E[Human Fortress]§F Ваші дані завантажено!")
    else
        human_fortress.edos_data[name] = {
            level = 1,
            score = 0,
            needed = 10,
            can_level_up = false,
            tax_paid = false,
            wood = 100,
            stone = 100,
            food = 100,
            ether = 0,
            rice = 0,
            versi = 0,
            skin = "default",
            upgrades = {}
        }
        minetest.chat_send_player(name, "§G[Human Fortress]§F Створено новий профіль!")
    end

    if edit_skin and edit_skin.update_player_skin then
        minetest.after(1, function()
            edit_skin.update_player_skin(player)
        end)
    end
end)
--=======================
--ЧАТТТТТ
--=====================
-- Таблиця для збереження історії чату
local chat_huds = {}

-- Функція для отримання іконки голови з edit_skin на основі рівня гравця
local function get_custom_head_icon(player)
    if not player then return "character.png" end
    local name = player:get_player_name()
    local level = 0
    local selected_id = "default"

    -- 1. Тягнемо рівень та ID скіна з бази твого RTS мода human_fortress
    if human_fortress and human_fortress.edos_data[name] then
        local data = human_fortress.edos_data[name]
        level = data.level or 0
        selected_id = data.skin or (edit_skin.skins[1] and edit_skin.skins[1].id)
    end
    
    -- 2. Шукаємо скін у таблиці edit_skin.skins
    if edit_skin and edit_skin.skins then
        for _, s in ipairs(edit_skin.skins) do
            if s.id == selected_id then
                -- Якщо ти пропишеш у json "icon", наприклад: s.icon = "head_cossack.png"
                -- Якщо іконки немає, використовуємо її дефолтну lvl0 текстуру як запасний варіант
                return s.icon or s.lvl0 or "character.png"
            end
        end
    end

    return "character.png" -- Повний бекап, якщо щось пішло не так
end

-- Функція для очищення HUD елементів гравця
local function clear_player_chat_hud(player)
    local p_name = player:get_player_name()
    if chat_huds[p_name] and chat_huds[p_name].ids then
        for _, hud_id in ipairs(chat_huds[p_name].ids) do
            player:hud_remove(hud_id)
        end
        chat_huds[p_name].ids = {}
    end
end

-- Функція малювання кастомного чату
local function redraw_chat(player)
    local p_name = player:get_player_name()
    local p_chat = chat_huds[p_name]
    if not p_chat then return end

    clear_player_chat_hud(player)

    -- Розташування: msg1 знизу (y=0.82) чітко над хотбаром, msg2 над ним (y=0.77)
    local positions = {
        {msg = p_chat.msg1, head = p_chat.head1, y_pos = 0.82},
        {msg = p_chat.msg2, head = p_chat.head2, y_pos = 0.77}
    }

    for _, line in ipairs(positions) do
        if line.msg and line.msg ~= "" then
            
            -- 1. СІРИЙ ФОН ПОВІДОМЛЕННЯ
            local id_bg = player:hud_add({
                hud_elem_type = "image",
                position = {x = 0.5, y = line.y_pos},
                offset = {x = 0, y = 0},
                -- Використовуємо вбудоване серце як основу для швидкої плашки без багів текстур
                text = "chatt.png^[colorize:#111111:210^[resize:450x32", 
                scale = {x = 1, y = 1},
                alignment = {x = 0, y = 0},
            })
            table.insert(p_chat.ids, id_bg)

            -- 2. АВАТАРКА ГОЛОВИ (Твоя кастомна текстура іконки)
            local id_head = player:hud_add({
                hud_elem_type = "image",
                position = {x = 0.5, y = line.y_pos},
                offset = {x = -205, y = 0}, -- Зсув вліво, щоб стати на початку сірої плашки
                text = line.head,
                scale = {x = 1, y = 1}, -- Якщо малюєш іконки, наприклад, 24x24 або 32x32, масштаб 1 в самий раз
                alignment = {x = 0, y = 0},
            })
            table.insert(p_chat.ids, id_head)

            -- 3. ТЕКСТ ПОВІДОМЛЕННЯ
            local id_text = player:hud_add({
                hud_elem_type = "text",
                position = {x = 0.5, y = line.y_pos},
                offset = {x = -180, y = -10}, -- Відступ вправо від іконки голови
                text = line.msg,
                number = 0xFFFFFF,
                alignment = {x = 1, y = 0}, -- Вирівнювання ліворуч всередині блоку
                scale = {x = 100, y = 100},
            })
            table.insert(p_chat.ids, id_text)
        end
    end
end

-- Перехоплювач повідомлень чату
minetest.register_on_chat_message(function(name, message)
    -- Якщо це команда, віддаємо її стандартному обробнику Luanti
    if message:sub(1, 1) == "/" then return false end

    local sender = minetest.get_player_by_name(name)
    
    -- Перевірка на рівень для відправки повідомлень (якщо рівень менше 3 — блокуємо)
    if sender and human_fortress and human_fortress.edos_data[name] then
        local current_lvl = human_fortress.edos_data[name].level or 0
        if current_lvl < 3 then
            minetest.chat_send_player(name, "§c[Чат] Писати в чат можна тільки з 3-го рівня!")
            return true -- Блокуємо відправку далі
        end
    end

    -- Отримуємо іконку з edit_skin на основі едос-даних відправника
    local head_texture = get_custom_head_icon(sender)
    local formatted_msg = name .. ": " .. message

    -- Оновлюємо чат для всіх підключених гравців
    for _, player in ipairs(minetest.get_connected_players()) do
        local p_name = player:get_player_name()
        
        if not chat_huds[p_name] then
            chat_huds[p_name] = { msg1 = "", msg2 = "", head1 = "", head2 = "", ids = {} }
        end
        
        local p_chat = chat_huds[p_name]
        
        -- Зсув повідомлень вгору (нове стає нижнім, старе піднімається)
        p_chat.msg2 = p_chat.msg1
        p_chat.head2 = p_chat.head1
        
        p_chat.msg1 = formatted_msg
        p_chat.head1 = head_texture

        -- Перемальовуємо інтерфейс гравця
        redraw_chat(player)
    end

    -- Автоматичне зникнення через 8 секунд
    minetest.after(8, function()
        for _, player in ipairs(minetest.get_connected_players()) do
            local p_name = player:get_player_name()
            if chat_huds[p_name] then
                if chat_huds[p_name].msg2 ~= "" then
                    chat_huds[p_name].msg2 = ""
                    chat_huds[p_name].head2 = ""
                else
                    chat_huds[p_name].msg1 = ""
                    chat_huds[p_name].head1 = ""
                end
                redraw_chat(player)
            end
        end
    end)

    return true -- Вимикаємо стандартне виведення тексту Luanti
end)


-- Очистка таблиці при виході гравця
minetest.register_on_leaveplayer(function(player)
    chat_huds[player:get_player_name()] = nil
end)


--===========
--ЧАС
--===========
-- Таблиця для часу (зберігаємо значення в секундах від 0 до 1439)
local player_hf_times = {}
local is_time_running = {} -- Таблиця для керування паузою

-- Функція для запуску/зупинки часу для гравця
function set_hf_time_running(player_name, state)
    is_time_running[player_name] = state
end

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    
    -- Завантажуємо збережений час (за замовчуванням 13:00 = 780 хв)
    player_hf_times[name] = meta:get_int("hf_time_stored")
    if player_hf_times[name] == 0 then player_hf_times[name] = 780 end
    
    -- За замовчуванням час йде, коли гравець в грі
    is_time_running[name] = true 
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player:get_meta():set_int("hf_time_stored", player_hf_times[name])
    player_hf_times[name] = nil
    is_time_running[name] = nil
end)

-- Основний цикл: час рухається ТІЛЬКИ якщо is_time_running == true
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        
        if is_time_running[name] then
            -- Час йде. Щоб 24 години = 24 хвилини, 
            -- нам треба щоб 1 реальна секунда була 1 ігровою хвилиною.
            -- dtime - це час у секундах між кадрами.
            player_hf_times[name] = (player_hf_times[name] + dtime) % 1440
        end
    end
end)
-- ============================================
-- НЕБО
-- ============================================
-- ============================================
-- НЕБО (на базі hf_time)
-- ============================================

local function update_sky(player)
    local name = player:get_player_name()
    local hf_time_minutes = player_hf_times[name] or 780 -- Беремо час гравця
    
    -- Переводимо хвилини в години для легкого порівняння (0.0 - 24.0)
    local hours = hf_time_minutes / 60
    
    local skybox
    -- Ваш графік: День 5:00-22:00, Ніч 22:01-4:49
    if hours >= 22 or hours < 5 then
        skybox = "night"
    elseif hours >= 5 and hours < 10 then -- Ранок (додайте свій діапазон)
        skybox = "morning"
    elseif hours >= 18 and hours < 22 then -- Вечір
        skybox = "evening"
    else
        skybox = "day"
    end
    
    player:set_sky({
        type = "skybox",
        textures = {
            skybox .. "_up.png",
            skybox .. "_down.png",
            skybox .. "_west.png",
            skybox .. "_east.png",
            skybox .. "_north.png",
            skybox .. "_south.png"
        },
        sun = false,
        moon = false,
        stars = false
    })
end

-- Оновлення тепер використовує наш hf_time
local sky_timer = 0
minetest.register_globalstep(function(dtime)
    sky_timer = sky_timer + dtime
    if sky_timer >= 2 then -- Зменшимо до 2 секунд для швидшої реакції
        sky_timer = 0
        for _, player in ipairs(minetest.get_connected_players()) do
            update_sky(player) -- ОСЬ ЦЕЙ РЯДОК БУВ ПРОПУЩЕНИЙ
        end
    end
end)

-- ============================================
-- ЗБЕРЕЖЕННЯ
-- ============================================

minetest.register_on_mods_loaded(function()
    minetest.settings:set("time_speed", "85")
end)

minetest.register_on_leaveplayer(function(player)
    human_fortress.save_data(player:get_player_name())
end)

minetest.register_on_shutdown(function()
    for _, player in pairs(minetest.get_connected_players()) do
        human_fortress.save_data(player:get_player_name())
    end
end)

-- ============================================
-- КОМАНДИ ДЛЯ ДЕБАГУ
-- ============================================

minetest.register_chatcommand("test_menus", {
    func = function(name)
        minetest.chat_send_player(name, "=== ПЕРЕВІРКА МЕНЮ ===")
        minetest.chat_send_player(name, "BUILDING_MENUS = " .. tostring(BUILDING_MENUS))
        if BUILDING_MENUS then
            local list = ""
            for k in pairs(BUILDING_MENUS) do list = list .. k .. " " end
            if list ~= "" then
                minetest.chat_send_player(name, "Доступні меню: " .. list)
            else
                minetest.chat_send_player(name, "❌ BUILDING_MENUS порожній!")
            end
        end
    end
})

minetest.register_chatcommand("list_units", {
    func = function(name)
        if not human_fortress.units_list then
            minetest.chat_send_player(name, "❌ units_list не існує!")
            return
        end
        minetest.chat_send_player(name, "=== ДОСТУПНІ ЮНІТИ ===")
        for k, v in pairs(human_fortress.units_list) do
            minetest.chat_send_player(name, "• " .. k .. " - " .. (v.name or k))
        end
    end
})

minetest.register_chatcommand("check_upgrades", {
    func = function(name)
        minetest.chat_send_player(name, "=== АПГРЕЙДИ " .. name .. " ===")
        local data = human_fortress.edos_data[name]
        if not data then
            minetest.chat_send_player(name, "❌ Немає edos_data!")
            return
        end
        local upgrades = data.upgrades or {}
        local list = ""
        for k, v in pairs(upgrades) do
            list = list .. k .. "=" .. tostring(v) .. " "
        end
        minetest.chat_send_player(name, list ~= "" and list or "❌ Порожньо")
    end
})

minetest.register_chatcommand("give_upgrades", {
    func = function(name)
        if not human_fortress.edos_data[name] then
            minetest.chat_send_player(name, "❌ Немає edos_data")
            return
        end
        human_fortress.edos_data[name].upgrades = {
            town_hall   = true,
            farm        = true,
            barracks    = true,
            wall        = true,
            guard_tower = true,
        }
        human_fortress.save_data(name)
        minetest.chat_send_player(name, "✅ Всі апгрейди видано!")
    end
})

minetest.register_chatcommand("check_buildings", {
    func = function(name)
        minetest.chat_send_player(name, "=== БУДІВЛІ ===")
        if not BUILDING_SCHEMATICS then
            minetest.chat_send_player(name, "❌ BUILDING_SCHEMATICS nil!")
            return
        end
        local count = 0
        for id, b in pairs(BUILDING_SCHEMATICS) do
            count = count + 1
            minetest.chat_send_player(name, "• " .. id .. " - " .. (b.name or "?"))
        end
        minetest.chat_send_player(name, "Всього: " .. count)
    end
})

local function apply_hotbar(name)
    local player = minetest.get_player_by_name(name)
    if not player then return end
    player:hud_set_hotbar_itemcount(9)
    player:hud_set_hotbar_image("custom_hotbar.png")
    player:hud_set_hotbar_selected_image("custom_hotbar_selected.png")
end

minetest.register_on_joinplayer(function(player)
player:hud_set_flags({healthbar = false})
    local name = player:get_player_name()

    -- Фон + текстура кнопок для всіх формспеків
            player:set_formspec_prepend(
        "background9[0,0;0,0;bg_common.png;true;40,40,-40,-40]" ..
        "style_type[button,button_exit,image_button,item_image_button;" ..
        "bgimg=my_button.png;bgimg_middle=4,4;border=false]"
    )

    -- Хотбар: одразу і повторно з затримкою
    apply_hotbar(name)
    minetest.after(1, apply_hotbar, name)
end)


-- Таблиця для збереження ID елементів інтерфейсу для кожного гравця
local player_hearts = {}

-- Функція для оновлення відображення сердець
local function update_custom_hearts(player)
    local name = player:get_player_name()
    if not player_hearts[name] then return end

    local hp = player:get_hp()
    -- Отримуємо максимальне здоров'я (зазвичай 20)
    local max_hp = player:get_properties().hp_max or 20 
    
    local total_hearts = math.floor(max_hp / 2) -- Кількість сердець (10)

    -- Рахуємо скільки повних, половинок та пустих малювати
    local full_hearts = math.floor(hp / 2)
    local has_half = (hp % 2 == 1)

    -- Проходимо по всіх 10 слотах сердець
    for i = 1, total_hearts do
        local texture = "heart_empty.png" -- За замовчуванням пусте

        if i <= full_hearts then
            texture = "heart_full.png"   -- Повне серце
        elseif i == full_hearts + 1 and has_half then
            texture = "heart_half.png"   -- Половинка серця
        end

        -- Оновлюємо текстуру для конкретного слота
        local hud_id = player_hearts[name][i]
        if hud_id then
            player:hud_change(hud_id, "text", texture)
        end
    end
end

-- Створюємо серця при заході гравця на сервер
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    
    -- 1. Сховуємо стандартне здоров'я Luanti
    player:hud_set_flags({ healthbar = false })

    player_hearts[name] = {}

    -- Налаштування позиції на екрані (ставимо приблизно туди, де стандартні)
    -- Позиція (0.5, 1) — це низ екрану, центр.
    local base_pos = { x = 0.5, y = 1.0 }
    
    -- Зміщення в пікселях. Розраховуємо під мікро-пікселі (наприклад, масштаб 4x)
    -- Оскільки текстура 8x8, збільшимо її до 32x32 пікселів на екрані
    local size = 32 
    local start_offset_x = -175 -- Початкова точка зліва від центру
    local offset_y = -86        -- Висота над хотбаром

    -- Створюємо 10 елементів для сердець
    for i = 1, 10 do
        local hud_id = player:hud_add({
            hud_elem_type = "image",
            position = base_pos,
            -- Розставляємо серця одне за одним в ряд
            offset = { x = start_offset_x + ((i - 1) * (size + 4)), y = offset_y },
            text = "heart_empty.png",
            scale = { x = 4, y = 4 }, -- Збільшуємо пікселі у 4 рази (з 8x8 до 32x32)
            alignment = { x = 0, y = 0 },
        })
        table.insert(player_hearts[name], hud_id)
    end

    -- Оновлюємо відразу після створення
    minetest.after(0.1, function()
        if minetest.get_player_by_name(name) then
            update_custom_hearts(player)
        end
    end)
end)

-- Очищаємо таблицю, коли гравець виходить
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player_hearts[name] = nil
end)

-- Перехоплюємо зміну здоров'я, щоб миттєво перемалювати серця
minetest.register_on_player_hpchange(function(player, hp_change, reason)
    -- Оновлюємо серця трохи згодом, коли двигун застосує новий HP
    minetest.after(0, function()
        if player and player:is_player() then
            update_custom_hearts(player)
        end
    end)
end)



-- Використовуємо метод для кожного гравця окремо при вході
--minetest.register_on_joinplayer(function(player)
--    local style = "style_type[button,image_button,item_image_button;bgimg=my_button.png;bgimg_middle=4,4;border=false]"

    
    -- Встановлюємо препенд безпосередньо для об'єкта гравця
--    player:set_formspec_prepend(style .. background)
--end)
print("[Human Fortress RTS] Усі компоненти завантажено!")