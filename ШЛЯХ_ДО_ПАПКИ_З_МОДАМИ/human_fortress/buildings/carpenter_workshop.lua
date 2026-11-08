-- ============================================
-- БУДІВЛЯ: ПЛОТНИЦЬКА МАЙСТЕРНЯ (carpenter_workshop.lua)
-- Ресурси: wood = 🌲 Ефір, stone = 🪨 Версиформ
-- ============================================

local storage = minetest.get_mod_storage()

local RECIPES = {
    chair = {
        name = "🪑 Стілець",
        item = "kitchen_furniture:chair",
        wood = 8,
        stone = 2,
        count = 1
    },
    ladder = {
        name = "🪜 Драбина",
        item = "default:ladder",
        wood = 6,
        stone = 1,
        count = 2
    },
    table = {
        name = "🪵 Стіл",
        item = "kitchen_furniture:table",
        wood = 14,
        stone = 4,
        count = 1
    },
    chest = {
        name = "📦 Дерев'яна скриня",
        item = "default:chest",
        wood = 18,
        stone = 5,
        count = 1
    }
}

-- Час роботи (секунд), поки поруч стоїть юніт-майстер
local PROD_TIME = { chair = 15, ladder = 10, table = 25, chest = 30 }
local WORKER_RADIUS = 10

-- поточні замовлення: jobs[ключ_майстерні] = {owner, recipe, progress, pos}
local jobs = minetest.deserialize(storage:get_string("carpenter_jobs")) or {}
local function save_jobs() storage:set_string("carpenter_jobs", minetest.serialize(jobs)) end
local function job_key(pos) return minetest.pos_to_string(vector.round(pos)) end

local function workshop_center(pos)
    local d = human_fortress.get_core_data and human_fortress.get_core_data(pos)
    if d and d.min and d.max then
        return { x = (d.min.x + d.max.x) / 2, y = (d.min.y + d.max.y) / 2, z = (d.min.z + d.max.z) / 2 }
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

-- чи є поруч свій юніт (майстер)
local function worker_near(owner, pos)
    for _, o in ipairs(minetest.get_objects_inside_radius(workshop_center(pos), WORKER_RADIUS)) do
        local e = o:get_luaentity()
        if e and e.unit_data and e.unit_data.owner == owner and (e.health or 1) > 0 then
            return true
        end
    end
    return false
end

function human_fortress.carpenter_status(owner, pos)
    local j = jobs[job_key(pos)]
    local st = { worker = worker_near(owner, pos) }
    if j and RECIPES[j.recipe] then
        st.recipe = RECIPES[j.recipe].name
        st.pct = math.min(100, math.floor(j.progress / PROD_TIME[j.recipe] * 100))
    end
    return st
end

-- найближча скриня складу власника
local function nearest_warehouse_chest(owner, from)
    if not (ender_expansion and ender_expansion.chests) then return nil end
    local best, best_d
    for h, c in pairs(ender_expansion.chests) do
        if c.owner == owner then
            local n = minetest.get_node_or_nil(c.pos)
            if n and minetest.get_item_group(n.name, "ender_chest") > 0 then
                local d = vector.distance(from, c.pos)
                if not best_d or d < best_d then best, best_d = vector.new(c.pos), d end
            end
        end
    end
    return best
end

-- виготовлене -> на склад (якщо складу немає або повний - в інвентар, інакше на землю)
local function deliver(owner, recipe, pos)
    local stack = ItemStack(recipe.item .. " " .. recipe.count)
    local where = "на склад"
    local chest = nearest_warehouse_chest(owner, pos)
    if chest then
        stack = ender_expansion.deposit(owner, stack:to_string(), chest)
    end
    if not stack:is_empty() then
        local pl = minetest.get_player_by_name(owner)
        if pl then
            stack = pl:get_inventory():add_item("main", stack)
            where = chest and "на склад (повний), решта в інвентар" or "в інвентар (складу нема)"
        end
    end
    if not stack:is_empty() then
        local c = workshop_center(pos)
        minetest.add_item({ x = c.x, y = pos.y + 1.5, z = c.z }, stack)
        where = "біля майстерні (склад повний, інвентар теж)"
    end
    return where
end

local prod_timer = 0
minetest.register_globalstep(function(dtime)
    prod_timer = prod_timer + dtime
    if prod_timer < 1 then return end
    local dt = prod_timer
    prod_timer = 0
    local changed = false
    for key, j in pairs(jobs) do
        local recipe = RECIPES[j.recipe]
        if not recipe then
            jobs[key] = nil changed = true
        elseif minetest.get_player_by_name(j.owner) and minetest.get_node_or_nil(j.pos) then
            local working = worker_near(j.owner, j.pos)
            local meta = minetest.get_meta(j.pos)
            if working then
                j.progress = j.progress + dt
                if j.progress >= PROD_TIME[j.recipe] then
                    local where = deliver(j.owner, recipe, j.pos)
                    minetest.chat_send_player(j.owner, "✅ Плотницька виготовила: " .. recipe.name ..
                        " ×" .. recipe.count .. " → " .. where)
                    jobs[key] = nil
                    changed = true
                    meta:set_string("infotext", "🪚 Плотницька майстерня\nВласник: " .. j.owner)
                else
                    meta:set_string("infotext", "🪚 Плотницька майстерня\nВиготовляється: " .. recipe.name ..
                        " " .. math.floor(j.progress / PROD_TIME[j.recipe] * 100) .. "%")
                end
            else
                meta:set_string("infotext", "🪚 Плотницька майстерня\n⏸ Потрібен юніт поруч")
            end
        end
    end
    if changed then save_jobs() end
end)

local function get_data(name)
    human_fortress.edos_data = human_fortress.edos_data or {}
    human_fortress.edos_data[name] = human_fortress.edos_data[name] or {}
    return human_fortress.edos_data[name]
end

local function show_menu(player_name, pos)
    local data = get_data(player_name)
    local status = "Вільна. Для роботи потрібен юніт-майстер поруч."
    if pos then
        local st = human_fortress.carpenter_status(player_name, pos)
        if st.recipe then
            status = "Виготовляється: " .. st.recipe .. " " .. st.pct .. "%  " ..
                (st.worker and "(майстер працює)" or "(⏸ немає юніта поруч!)")
        elseif not st.worker then
            status = "Вільна. ⚠ Надішли юніта до майстерні."
        end
    end

    local function btn(x, y, id)
        local r = RECIPES[id]
        local label = r.name .. (r.count > 1 and (" ×" .. r.count) or "") ..
            "\n" .. r.wood .. "🌲 + " .. r.stone .. "🪨"
        return "button[" .. x .. "," .. y .. ";4.2,1;" .. id .. ";" ..
            minetest.formspec_escape(label) .. "]"
    end

    local fs = "formspec_version[4]size[10,7]" ..
        "box[0,0;10,0.8;#2D2D44]" ..
        "label[0.5,0.2;🪚 ПЛОТНИЦЬКА МАЙСТЕРНЯ]" ..
        "label[6.3,0.2;🌲 " .. (data.wood or 0) .. "]" ..
        "label[8,0.2;🪨 " .. (data.stone or 0) .. "]" ..
        "label[0.5,1.05;" .. minetest.formspec_escape(status) .. "]" ..
        btn(0.5, 1.6, "chair") .. btn(5.2, 1.6, "ladder") ..
        btn(0.5, 3, "table")   .. btn(5.2, 3, "chest") ..
        "button[0.5,5.5;4.2,0.8;destroy_building;💥 ЗНИЩИТИ]" ..
        "button[5.2,5.5;4.2,0.8;close;❌ ЗАКРИТИ]"
    minetest.show_formspec(player_name, "human_fortress:carpenter_workshop", fs)
end

local function produce(player_name, recipe_id, pos)
    local recipe = RECIPES[recipe_id]
    if not recipe or not pos then return end

    if not minetest.registered_items[recipe.item] then
        minetest.chat_send_player(player_name, "❌ Предмет не знайдено: " .. recipe.item)
        return
    end

    local key = job_key(pos)
    if jobs[key] then
        minetest.chat_send_player(player_name, "⏳ Майстерня вже зайнята: " ..
            (RECIPES[jobs[key].recipe] and RECIPES[jobs[key].recipe].name or "замовлення"))
        show_menu(player_name, pos)
        return
    end

    local data = get_data(player_name)
    local wood = data.wood or 0
    local stone = data.stone or 0
    if wood < recipe.wood then
        minetest.chat_send_player(player_name, "❌ Недостатньо Ефіру! Потрібно " .. recipe.wood .. ", є " .. wood)
        return
    end
    if stone < recipe.stone then
        minetest.chat_send_player(player_name, "❌ Недостатньо Версиформу! Потрібно " .. recipe.stone .. ", є " .. stone)
        return
    end

    data.wood = wood - recipe.wood
    data.stone = stone - recipe.stone
    if human_fortress.save_data then human_fortress.save_data(player_name) end
    local player = minetest.get_player_by_name(player_name)
    if player and human_fortress.update_gui then human_fortress.update_gui(player) end

    jobs[key] = { owner = player_name, recipe = recipe_id, progress = 0, pos = vector.round(pos) }
    save_jobs()

    local note = worker_near(player_name, pos) and "" or " Надішли юніта до майстерні, інакше робота стоїть!"
    minetest.chat_send_player(player_name, "🪚 Замовлено: " .. recipe.name .. " (" ..
        PROD_TIME[recipe_id] .. " с роботи майстра). Готове піде на склад." .. note)
    show_menu(player_name, pos)
end

-- ============================================
-- ЗНИЩЕННЯ
-- ============================================

local function destroy_building(player_name, computer_pos)
    local meta = minetest.get_meta(computer_pos)
    if meta:get_string("owner") ~= player_name then
        minetest.chat_send_player(player_name, "❌ Це чужа будівля!")
        return false
    end

    local building_pos = minetest.deserialize(meta:get_string("building_pos"))
    if not building_pos then
        minetest.chat_send_player(player_name, "❌ Помилка даних будівлі!")
        return false
    end

    jobs[job_key(computer_pos)] = nil
    save_jobs()

    local refund = math.floor(meta:get_int("building_cost") * 0.7)
    local data = get_data(player_name)
    data.score = (data.score or 0) + refund

    if minetest.get_node(computer_pos).name == "human_fortress:building_computer" then
        minetest.remove_node(computer_pos)
    end

    local list = human_fortress.buildings and human_fortress.buildings[player_name]
    if list then
        for i, b in ipairs(list) do
            if b.type == "carpenter_workshop" and vector.equals(b.pos, building_pos) then
                table.remove(list, i)
                break
            end
        end
    end

    if human_fortress.save_data then
        human_fortress.save_data(player_name)
    end

    minetest.chat_send_player(player_name, "💥 Будівлю знищено, повернено " .. refund .. " Ейдосів")
    return true
end

-- ============================================
-- МЕНЮ
-- ============================================

if not BUILDING_MENUS then BUILDING_MENUS = {} end

BUILDING_MENUS.carpenter_workshop = function(player_name, computer_pos)
    local meta = minetest.get_meta(computer_pos)
    local owner = meta:get_string("owner")
    if owner ~= "" and owner ~= player_name then
        minetest.chat_send_player(player_name, "❌ Це чужа будівля!")
        return
    end

    local tmp = minetest.deserialize(storage:get_string("carpenter_workshop_tmp")) or {}
    tmp[player_name] = computer_pos
    storage:set_string("carpenter_workshop_tmp", minetest.serialize(tmp))

    show_menu(player_name, computer_pos)
end

-- ============================================
-- ОБРОБНИК ПОДІЙ
-- ============================================

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "human_fortress:carpenter_workshop" then return end

    local name = player:get_player_name()
    local tmp = minetest.deserialize(storage:get_string("carpenter_workshop_tmp")) or {}
    local pos = tmp[name]

    if fields.close or fields.quit then return true end

    if fields.destroy_building then
        if pos then
            if destroy_building(name, pos) then
                tmp[name] = nil
                storage:set_string("carpenter_workshop_tmp", minetest.serialize(tmp))
                minetest.close_formspec(name, formname)
            end
        end
        return true
    end

    for recipe_id in pairs(RECIPES) do
        if fields[recipe_id] then
            if pos then
                produce(name, recipe_id, pos)
            end
            return true
        end
    end

    return true
end)

-- ============================================
-- ДАНІ БУДІВЛІ
-- ============================================

return {
    id = "carpenter_workshop",
    data = {
        name = "🪚 Плотницька майстерня",
        description = "Виробництво дерев'яних меблів та конструкцій",
        level = 1,
        unlock_required = "town_hall",
        cost = {
            score = 0,
            wood = 120,   -- Ефір
            stone = 80    -- Версиформ
        },
        schematic = "carpenter_workshop.mts",
        icon = "human_fortress_carpenter.png",
        color = "#A66A32",

        on_built = function(player_name, pos)
            -- підлаштуй зсув під свою схему
            local computer_pos = {x = pos.x + 2, y = pos.y + 1, z = pos.z + 2}
            minetest.set_node(computer_pos, {name = "human_fortress:building_computer"})

            local meta = minetest.get_meta(computer_pos)
            meta:set_string("building_type", "carpenter_workshop")
            meta:set_string("owner", player_name)
            meta:set_int("building_cost", 100)
            meta:set_string("infotext", "🪚 Плотницька майстерня\nВласник: " .. player_name .. "\nПКМ - меню")
            meta:set_string("building_pos", minetest.serialize(pos))

            human_fortress.buildings = human_fortress.buildings or {}
            human_fortress.buildings[player_name] = human_fortress.buildings[player_name] or {}
            table.insert(human_fortress.buildings[player_name], {
                type = "carpenter_workshop",
                pos = pos
            })

            minetest.chat_send_player(player_name, "🪚 Плотницька майстерня побудована!")
        end
    }
}