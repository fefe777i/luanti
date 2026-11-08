-------------------------------------------------
-- Human Fortress RTS - Система часу (Атлас 24 кадри)
-- Персональний час кожного гравця (player_hf_times)
-------------------------------------------------

human_fortress.clock_huds = human_fortress.clock_huds or {}

-- ЧАС КОЖНОГО ГРАВЦЯ (хвилини від 0 до 1439)
local player_hf_times = {}
-- ЛІЧИЛЬНИК ІГРОВИХ ДНІВ КОЖНОГО ГРАВЦЯ (замінює os.date)
local player_hf_days = {}
-- КЕРУВАННЯ ПАУЗОЮ ЧАСУ
local is_time_running = {}

-- ОСТАННЯ ЗДАЧА ПОДАТКУ (ігровий день гравця)
local last_tax = {}

-- Функція для запуску/зупинки часу для гравця
function set_hf_time_running(player_name, state)
    is_time_running[player_name] = state
end

-- ПОТОЧНИЙ ІГРОВИЙ ДЕНЬ ГРАВЦЯ
local function get_current_day(player_name)
    return player_hf_days[player_name] or 0
end

-- ГОДИНА/ХВИЛИНА ГРАВЦЯ З ЙОГО ОСОБИСТОГО ЧАСУ
local function get_player_hour_minute(player_name)
    local t = player_hf_times[player_name] or 780
    local hour = math.floor(t / 60)
    local minute = math.floor(t % 60)
    return hour, minute
end
function human_fortress.get_player_time(player_name)
    local hour, minute = get_player_hour_minute(player_name)
    return hour, minute, get_current_day(player_name)
end

-- ВАРТІСТЬ НАСТУПНОГО РІВНЯ
local function get_next_level_cost(level)
    if level < 10 then return level * 5 + 5
    elseif level < 20 then return level * 20
    elseif level < 30 then return 400 + (level - 20) * 50
    elseif level < 40 then return 1000 + (level - 30) * 250
    elseif level < 100 then return 3500 + (level - 40) * 500
    else 
        local extra = math.floor((level - 100) / 10) * 1000
        return 35000 + extra
    end
end

-- ЧИ МОЖНА ЗДАВАТИ СЬОГОДНІ (за ігровим днем гравця)
local function can_pay_today(player_name)
    local data = human_fortress.edos_data[player_name]
    if not data then return false end
    
    local current_day = get_current_day(player_name)
    local last = last_tax[player_name] or -1
    
    if data.level < 30 then
        return current_day ~= last
    end
    if data.level >= 30 and data.level < 60 then
        return current_day >= last + 2
    end
    if data.level >= 60 and data.level < 90 then
        return current_day >= last + 3
    end
    if data.level >= 90 then
        return current_day >= last + 4
    end
    
    return false
end

-- ПОЗНАЧИТИ ЩО ЗДАВ
local function mark_tax_paid(player_name)
    last_tax[player_name] = get_current_day(player_name)
end

-- 1. HUD годинника
local function create_time_hud(player)
    if human_fortress.is_overworld then return end  -- в overworld немає годинника
    local name = player:get_player_name()
    
    if human_fortress.clock_huds[name] then
        player:hud_remove(human_fortress.clock_huds[name].base)
        player:hud_remove(human_fortress.clock_huds[name].hand)
    end

    local hand_id = player:hud_add({
        hud_elem_type = "image",
        name = "clock_hand",
        position = {x = 0.8, y = 0.2},
        offset = {x = 0, y = 0},
        text = "clock_hand_sheet.png^[sheet:1x24:0,0",
        scale = {x = 4, y = 4},
        alignment = {x = 0, y = 0},
        z_index = 9, 
    })

    local base_id = player:hud_add({
    hud_elem_type = "image",
    name = "clock_base",
    position = {x = 0.8, y = 0.2},
    offset = {x = 0, y = 0},
    text = "clock_base.png",
    scale = {x = 4, y = 4},
    alignment = {x = 0, y = 0},
    z_index = 10,
    touchable = true,
})
    
    human_fortress.clock_huds[name] = {base = base_id, hand = hand_id}
end
-- Показати/сховати годинник (у режимі командування його немає)
function human_fortress.set_clock_visible(player, visible)
    local name = player:get_player_name()
    if visible then
        if not human_fortress.clock_huds[name] then create_time_hud(player) end
    else
        local h = human_fortress.clock_huds[name]
        if h then
            player:hud_remove(h.base)
            player:hud_remove(h.hand)
            human_fortress.clock_huds[name] = nil
        end
    end
end

minetest.register_on_hud_touch(function(player, button_name)
    if button_name == "clock_base" then
        human_fortress.show_clock_menu(player:get_player_name())
    end
end)
-- 2. Приєднання / вихід гравця: завантаження/збереження часу і дня
local tax_warnings = {}

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    
    player_hf_times[name] = meta:get_int("hf_time_stored")
    if player_hf_times[name] == 0 then player_hf_times[name] = 780 end
    
    player_hf_days[name] = meta:get_int("hf_day_stored")
    
    is_time_running[name] = true
    tax_warnings[name] = false
    
    minetest.after(3, function()
        if player:is_player() and not (human_fortress.rts and human_fortress.rts.is_active(name)) then
            create_time_hud(player)
        end
    end)
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    local meta = player:get_meta()
    
    meta:set_int("hf_time_stored", math.floor(player_hf_times[name] or 780))
    meta:set_int("hf_day_stored", player_hf_days[name] or 0)
    
    player_hf_times[name] = nil
    player_hf_days[name] = nil
    is_time_running[name] = nil
    tax_warnings[name] = nil
end)

-- 3. Основний цикл: рух часу, стрілка годинника, податки
minetest.register_globalstep(function(dtime)
    if human_fortress.is_overworld then return end  -- в overworld немає часу й податків
    -- Рух часу і стрілка
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        
        if is_time_running[name] then
            local old_time = player_hf_times[name] or 780
            local new_time = (old_time + dtime) % 1440
            
            -- Якщо час "перескочив" через 0 -- настав новий ігровий день гравця
            if new_time < old_time then
                player_hf_days[name] = (player_hf_days[name] or 0) + 1
            end
            
            player_hf_times[name] = new_time
        end
        
        local huds = human_fortress.clock_huds[name]
        if huds then
            local hour = get_player_hour_minute(name)
            local frame = math.floor(hour)
            if frame > 23 then frame = 23 end
            if frame < 0 then frame = 0 end
            
            local sheet_mod = "^[sheet:1x24:0," .. tostring(frame)
            player:hud_change(huds.hand, "text", "clock_hand_sheet.png" .. sheet_mod)
        end
    end

    -- ЛОГІКА ПОДАТКІВ (за особистим часом кожного гравця)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local data = human_fortress.edos_data[name]
        
        if not data then goto continue end
        
        local hour, minute = get_player_hour_minute(name)
        
        if tax_warnings[name] == nil then
            tax_warnings[name] = false
        end
        
        -- Попередження о 21:30 (особистий час)
        if hour == 21 and minute == 30 and not tax_warnings[name] and not data.tax_paid then
            if can_pay_today(name) then
                minetest.chat_send_player(name, "§E[Податки]§F Зараз 21:30! Здай Ейдоси до 22:10, або штраф!")
                tax_warnings[name] = true
            else
                tax_warnings[name] = false
            end
        end

        -- Час здачі податку (22:10, особистий час)
        if hour == 22 and minute == 10 then
            if tax_warnings[name] and not data.tax_paid then
                if can_pay_today(name) then
                    local cost = get_next_level_cost(data.level)
                    data.score = data.score - cost
                    data.level = data.level + 1
                    mark_tax_paid(name)
                    
                    if human_fortress.on_level_up then
                        human_fortress.on_level_up(name)
                    end
                    
                    minetest.sound_play("default_tool_breaks", {to_player = name, gain = 1.0})
                    minetest.chat_send_player(name, "§E[ГОЛОС]§F Час вийшов! Я забираю ейдоси які потрібні і це: §R" .. cost .. "§F і перевожу тебе на новий рівень.")
                    
                    if human_fortress.update_gui then 
                        local p = minetest.get_player_by_name(name)
                        if p then
                            human_fortress.update_gui(p) 
                        end
                    end
                else
                    minetest.chat_send_player(name, "§E[ГОЛОС]§F Сьогодні не твій день для податків.")
                end
                
                tax_warnings[name] = false
            end
            
            if data.tax_paid and tax_warnings[name] then
                minetest.chat_send_player(name, "§G[ГОЛОС]§F Молодець що перейшов на рівень вчасно.")
                tax_warnings[name] = false
                
                if human_fortress.update_gui then 
                    local p = minetest.get_player_by_name(name)
                    if p then
                        human_fortress.update_gui(p) 
                    end
                end
            end
        end

        -- О 00:00 (особистий час) скидаємо статус податку
        if hour == 0 and minute == 0 then
            data.tax_paid = false
            tax_warnings[name] = false
        end

        ::continue::
    end
end)

-- КОМАНДА ДЛЯ ПЕРЕВІРКИ СТАТУСУ ПОДАТКІВ
minetest.register_chatcommand("tax_status", {
    func = function(name)
        local data = human_fortress.edos_data[name]
        if not data then
            minetest.chat_send_player(name, "§RПомилка: дані не знайдені!")
            return
        end
        
        local last = last_tax[name] or -1
        local current = get_current_day(name)
        local can = can_pay_today(name)
        local hour, minute = get_player_hour_minute(name)
        
        minetest.chat_send_player(name, "=== СТАТУС ПОДАТКІВ ===")
        minetest.chat_send_player(name, "Рівень: " .. data.level)
        minetest.chat_send_player(name, "Твій ігровий час: " .. string.format("%02d:%02d", hour, minute))
        minetest.chat_send_player(name, "Остання здача: день " .. last)
        minetest.chat_send_player(name, "Поточний ігровий день: " .. current)
        minetest.chat_send_player(name, "Можна здати сьогодні: " .. (can and "✅ ТАК" or "❌ НІ"))
        
        if data.level >= 30 and data.level < 60 then
            minetest.chat_send_player(name, "Режим: раз на 2 дні")
        elseif data.level >= 60 and data.level < 90 then
            minetest.chat_send_player(name, "Режим: раз на 3 дні")
        elseif data.level >= 90 then
            minetest.chat_send_player(name, "Режим: раз на 4 дні")
        else
            minetest.chat_send_player(name, "Режим: щодня")
        end
    end
})

-- КОМАНДА ДЛЯ ЗМІНИ ОСОБИСТОГО ЧАСУ ГРАВЦЯ
minetest.register_chatcommand("set_time", {
    params = "<година> [хвилина] або <хвилини_від_0_до_1439>",
    description = "Змінити свій особистий ігровий час",
    func = function(name, param)
        local args = {}
        for word in param:gmatch("%S+") do
            table.insert(args, tonumber(word))
        end
        
        if #args == 0 then
            minetest.chat_send_player(name, "§RВикористання: /set_time <година> [хвилина] або /set_time <хвилини>")
            minetest.chat_send_player(name, "§FПриклад: /set_time 14 30 (або /set_time 870)")
            return
        end
        
        local new_total_minutes = 0
        
        if #args >= 2 then
            local hour = args[1]
            local minute = args[2]
            
            if hour < 0 or hour > 23 or minute < 0 or minute > 59 then
                minetest.chat_send_player(name, "§RПомилка: Година має бути від 0 до 23, а хвилина від 0 до 59!")
                return
            end
            
            new_total_minutes = (hour * 60) + minute
        else
            local total = args[1]
            if total < 0 or total > 1439 then
                minetest.chat_send_player(name, "§RПомилка: Значення має бути в межах від 0 до 1439 хвилин!")
                return
            end
            
            new_total_minutes = total
        end
        
        -- Оновлюємо час гравця
        player_hf_times[name] = new_total_minutes
        
        -- Оновлюємо стрілку годинника і НЕБО миттєво!
        local p = minetest.get_player_by_name(name)
        if p then
            update_sky(p)
        end
        
        local hour, minute = get_player_hour_minute(name)
        minetest.chat_send_player(name, "§E[Час]§F Твій особистий час успішно змінено на §G" .. string.format("%02d:%02d", hour, minute) .. "§F.")
    end
})