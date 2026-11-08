-- ============================================
-- ПАНЕЛЬ ЮНІТА (внизу екрана)
-- ============================================
-- Показується, коли гравець дивиться на свого формикса (від 1-ї особи)
-- або в режимі командування - для виділеного юніта.
-- Модель (іконка), ім'я, HP, захист, швидкість, ноша (ефір / версиформ / рис)
-- і кнопка «Здати» зі значком складу, якщо є що здавати.

human_fortress = human_fortress or {}

local MODPATH = minetest.get_modpath("human_fortress")
local PW, PH = 340, 104           -- розмір фону панелі, px
local panels = {}                 -- panels[name] = { ids = {...}, uid = ..., cmd = bool }

-- ---------- допоміжне ----------

local function file_exists(rel)
    local f = io.open(MODPATH .. "/textures/" .. rel, "rb")
    if f then f:close() return true end
    return false
end

local function unit_icon(ent)
    local ul = human_fortress.units_list or {}
    for id, u in pairs(ul) do
        if u.entity == ent.name or ("human_fortress:" .. id) == ent.name then
            if u.icon and u.icon ~= "" then return u.icon, u.name, u.speed end
            local guess = "human_fortress_" .. id .. ".png"
            if file_exists(guess) then return guess, u.name, u.speed end
            return "human_fortress_worker.png", u.name, u.speed
        end
    end
    return "human_fortress_worker.png", "Юніт", nil
end

local function unit_stats(ent)
    local icon, uname, speed = unit_icon(ent)
    local hp = math.floor(ent.health or 0)
    local hp_max = ent.hp_max
        or (ent.initial_properties and ent.initial_properties.hp_max) or hp
    local armor = ent.armor
    if type(armor) == "table" then armor = armor.fleshy end
    local defense = 0
    if type(armor) == "number" then defense = math.max(0, 100 - armor) end
    speed = (ent.unit_data and ent.unit_data.speed) or speed or ent.walk_velocity or 0
    local inv = ent.inventory or {}
    local e, v, r = inv.wood or 0, inv.stone or 0, inv.food or 0
    return {
        icon = icon, name = uname, hp = hp, hp_max = hp_max,
        defense = defense, speed = speed,
        ether = e, vers = v, rice = r, total = e + v + r,
        carry_max = ent.carry_max or 300,
    }
end

human_fortress.unit_stats = unit_stats

--- Юніт, на якого дивиться гравець (чи виділений у режимі командування).
local function find_target(player)
    local name = player:get_player_name()
    local rts = human_fortress.rts
    if rts and rts.is_active(name) then
        local p = human_fortress.players and human_fortress.players[name]
        if p and p.selected_building then return nil end   -- показана панель будівлі
        local ids = (p and p.selected_ids) or {}
        for _, uid in ipairs(ids) do
            local obj, ent = rts.find_unit(uid)
            if obj and ent and ent.unit_data and ent.unit_data.owner == name then
                return obj, ent, #ids
            end
        end
        return nil
    end
    -- поза режимом командування статистику не показуємо
    return nil
end

-- ---------- HUD ----------

local function remove_panel(player, name)
    local p = panels[name]
    if not p then return end
    for _, id in pairs(p.ids) do player:hud_remove(id) end
    panels[name] = nil
end

-- panel-local (lx, ly) від лівого верхнього кута -> зсув від (0.5, 1.0)
local function create_panel(player, name, st)
    local cmd = human_fortress.rts and human_fortress.rts.is_active(name)
    local by = cmd and -12 or -125             -- нижня межа панелі
    local ox, oy = -PW / 2, by - PH
    local function at(lx, ly) return { x = ox + lx, y = oy + ly } end
    local ids = {}
    local function img(key, lx, ly, text, extra)
        local def = {
            hud_elem_type = "image", position = { x = 0.5, y = 1.0 },
            offset = at(lx, ly), text = text, scale = { x = 1, y = 1 },
            alignment = { x = 0, y = 0 }, z_index = 20,
        }
        for k, v in pairs(extra or {}) do def[k] = v end
        ids[key] = player:hud_add(def)
    end
    local function txt(key, lx, ly, text, color, align)
        ids[key] = player:hud_add({
            hud_elem_type = "text", position = { x = 0.5, y = 1.0 },
            offset = at(lx, ly), text = text, number = color or 0xFFFFFF,
            alignment = { x = align or 1, y = 0 }, z_index = 21,
            size = { x = 1, y = 1 },
        })
    end

    img("bg", PW / 2, PH / 2, "hf_unit_panel_bg.png")
    img("portrait", 42, 40, st.icon .. "^[resize:64x64")
    txt("hp", 42, 88, st.hp .. "/" .. st.hp_max, 0xFFFFFF, 0)
    txt("name", 86, 16, st.name, 0xFFE08A)
    txt("defense", 86, 34, "Захист: " .. st.defense .. "%", 0xBFE8FF)
    txt("speed", 86, 51, "Швидкість: " .. st.speed, 0xBFE8FF)
    txt("carry", 200, 34, "Ноша " .. st.total .. "/" .. st.carry_max, 0xFFFFFF)
    -- ресурси: ефір / версиформ / рис
    local rx = { 84, 146, 208 }
    local icons = { "ef.png", "v.png", "r.png" }
    local keys = { "ether", "vers", "rice" }
    for i = 1, 3 do
        img("ri" .. i, rx[i] + 13, 80, icons[i] .. "^[resize:20x20")
        txt("rt" .. i, rx[i] + 26, 80, tostring(st[keys[i]]), 0xFFFFFF)
    end
    -- кнопка «Здати» (значок складу вже на фоні); клікабельна зона поверх нього
    img("deposit", 304, 74, "hf_unit_panel_hit.png",
        { name = "hf_unit_deposit", touchable = true, z_index = 25 })
    txt("deposit_hint", 304, 42, "", 0xFFE08A, 0)

    panels[name] = { ids = ids, cmd = cmd, last = nil }
end

local function update_panel(player, name, st, cnt)
    local p = panels[name]
    local ids = p.ids
    local function ch(key, field, val) if ids[key] then player:hud_change(ids[key], field, val) end end
    ch("portrait", "text", st.icon .. "^[resize:64x64")
    ch("hp", "text", st.hp .. "/" .. st.hp_max)
    ch("name", "text", st.name .. ((cnt or 1) > 1 and (" (+" .. (cnt - 1) .. ")") or ""))
    ch("defense", "text", "Захист: " .. st.defense .. "%")
    ch("speed", "text", "Швидкість: " .. st.speed)
    ch("carry", "text", "Ноша " .. st.total .. "/" .. st.carry_max)
    ch("rt1", "text", tostring(st.ether))
    ch("rt2", "text", tostring(st.vers))
    ch("rt3", "text", tostring(st.rice))
    -- кнопка здати видна лише коли є що здавати
    ch("deposit", "text", st.total > 0 and "hf_unit_panel_hit.png" or "[combine:1x1")
    ch("deposit_hint", "text", st.total > 0 and "Здати" or "")
end

-- ---------- цикл ----------

local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 0.25 then return end
    timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local obj, ent, cnt = find_target(player)
        if obj and ent then
            local st = unit_stats(ent)
            local cmd = human_fortress.rts and human_fortress.rts.is_active(name) or false
            local p = panels[name]
            if p and p.cmd ~= cmd then remove_panel(player, name); p = nil end
            if not p then
                create_panel(player, name, st)
                p = panels[name]
            end
            p.uid = ent.unit_data.unit_id
            update_panel(player, name, st, cnt)
        elseif panels[name] then
            remove_panel(player, name)
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    panels[player:get_player_name()] = nil
end)

-- кнопка «Здати»
minetest.register_on_hud_touch(function(player, hud_element_name)
    if hud_element_name ~= "hf_unit_deposit" then return end
    local name = player:get_player_name()
    local p = panels[name]
    if not p or not p.uid then return end
    local rts = human_fortress.rts
    local obj, ent
    if rts then obj, ent = rts.find_unit(p.uid) end
    if not ent then
        for _, o in ipairs(minetest.get_objects_inside_radius(player:get_pos(), 40)) do
            local e = o:get_luaentity()
            if e and e.unit_data and e.unit_data.unit_id == p.uid then obj, ent = o, e break end
        end
    end
    if not (ent and ent.unit_data and ent.unit_data.owner == name) then return end
    local inv = ent.inventory or {}
    if (inv.wood or 0) + (inv.stone or 0) + (inv.food or 0) <= 0 then return end
    ent.unit_data.command = "unload"
    ent.unit_data.target = nil
    minetest.chat_send_player(name, "📥 Наказ здати ресурси відправлено")
end)

-- ---------- ліміт складу (страховка для прямих нарахувань) ----------

local cap_timer = 0
minetest.register_globalstep(function(dtime)
    cap_timer = cap_timer + dtime
    if cap_timer < 1 then return end
    cap_timer = 0
    local cap = human_fortress.RES_CAP or 1000
    for _, data in pairs(human_fortress.edos_data or {}) do
        for _, k in ipairs({ "wood", "stone", "food" }) do
            if (data[k] or 0) > cap then data[k] = cap end
        end
    end
end)
