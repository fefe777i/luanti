-- ============================================
-- progression.lua
--  * ліміт юнітів і споживання їжі (голод)
--  * ліміт будівель на регіон
--  * рівні прокачок (3 рівні) і прокачка самих будівель
--  * human_fortress.add_resource - прибуток з бонусами
-- Завантажується ДО будівель: його обробник кнопки "Прокачати" має спрацювати першим.
-- ============================================

local storage = minetest.get_mod_storage()
human_fortress = human_fortress or {}

local MAX_RANK = 3
local BASE_UNIT_LIMIT = 8
local FOOD_PERIOD = 60          -- секунд між "обідами"
local STARVE_DAMAGE = 6         -- шкода голодному юніту за хвилину
local COMBAT = {warrior = true, elite_warrior = true, samurai = true, archer = true,
    berserk = true, recruit = true, spearman = true, lizard = true}

-- ---------- Перки прокачок ----------
-- building - яка будівля має бути прокачана до того ж рівня (nil - тільки купівля)
-- per      - бонус за кожен активний рівень
human_fortress.perks = {
    townhall = {building = "townhall", per = 6,
        line = "Ліміт юнітів: +%d"},
    rice_field = {building = "rice_field", per = 0.25,
        line = "Їжа з ферм і рибалок: +%d%%", pct = true},
    carpenter_workshop = {building = "carpenter_workshop", per = 0.25,
        line = "Ефір (дерево): +%d%%", pct = true},
    market = {building = "market", per = 0.20,
        line = "Ейдоси: +%d%%", pct = true},
    barracks = {building = "barracks", per = 0.25,
        line = "Прокорм воїнів: -%d%%", pct = true},
    hardworker = {per = 0.10,
        line = "Усі ресурси від робітників: +%d%%", pct = true},
    calculation = {per = 0.10,
        line = "Додаткова знижка на прокорм: -%d%%", pct = true},
    auto_collector = {per = 15,
        line = "Автозбірник: на %d с швидше"},
    house = {building = "house", per = 3,
        line = "Ліміт юнітів від будинків: +%d"},
    pier = {building = "pier", per = 2,
        line = "Їжа з пірса: +%d за хвилину"},
    warehouse_branch = {building = "warehouse_branch", per = 0.15,
        line = "Експрес-доставка: швидкість +%d%%", pct = true},
    archer_tower = {building = "archer_tower", per = 1,
        line = "Башта лучників: +%d постріл за залп"},
    bank = {building = "bank", per = 250,
        line = "Ліміт кредиту: +%d ейдосів"},
    lizard_nest = {building = "lizard_nest", per = 1,
        line = "Гніздо ящерів: більше місць (рівень будівлі)"},
}
local PERKS = human_fortress.perks

local BUILDING_FORM = {
    ["human_fortress:townhall"] = "townhall",
    ["human_fortress:market_menu"] = "market",
    ["human_fortress:barracks"] = "barracks",
    ["human_fortress:farm"] = "rice_field",
    ["human_fortress:carpenter_workshop"] = "carpenter_workshop",
    ["human_fortress:house_menu"] = "house",
    ["human_fortress:pier_menu"] = "pier",
    ["human_fortress:branch_menu"] = "warehouse_branch",
    ["human_fortress:archer_menu"] = "archer_tower",
    ["human_fortress:bank_menu"] = "bank",
    ["human_fortress:nest_menu"] = "lizard_nest",
}
local BUILDING_NAME = {
    townhall = "Ратуша", market = "Ринок", barracks = "Казарми",
    rice_field = "Ферма", carpenter_workshop = "Плотницька",
    house = "Житлове здання", pier = "Пірс", warehouse_branch = "Філія складу",
    archer_tower = "Башта лучників", bank = "Банк", lizard_nest = "Гніздо ящерів", warehouse = "Склад", auto_collector = "Автозбірник",
}

-- ---------- Ранг прокачки / рівень будівлі ----------
function human_fortress.upgrade_rank(name, id)
    return human_fortress.get_upgrade_rank and human_fortress.get_upgrade_rank(name, id) or 0
end

function human_fortress.building_level(name, btype)
    local d = get_player_data and get_player_data(name)
    return d and d.building_levels and d.building_levels[btype] or 1
end

-- активний рівень перка = min(ранг прокачки, рівень будівлі)
function human_fortress.perk_level(name, id)
    local rank = human_fortress.upgrade_rank(name, id)
    if rank <= 0 then return 0 end
    local perk = PERKS[id]
    if perk and perk.building then
        rank = math.min(rank, human_fortress.building_level(name, perk.building))
    end
    return rank
end

function human_fortress.perk_value(name, id)
    local perk = PERKS[id]
    if not perk then return 0 end
    return perk.per * human_fortress.perk_level(name, id)
end

-- ---------- Прибуток ресурсів з бонусами ----------
human_fortress.RES_CAP = tonumber(minetest.settings:get("human_fortress_res_cap")) or 1000
human_fortress.RES_CAPPED = {wood = true, stone = true, food = true}

function human_fortress.add_resource(owner, res, amount)
    local data = human_fortress.edos_data and human_fortress.edos_data[owner]
    amount = tonumber(amount) or 0
    if not data or amount <= 0 then return 0 end
    local mult = 1 + human_fortress.perk_value(owner, "hardworker")
    if res == "food" then mult = mult + human_fortress.perk_value(owner, "rice_field")
    elseif res == "wood" then mult = mult + human_fortress.perk_value(owner, "carpenter_workshop")
    elseif res == "score" then mult = mult + human_fortress.perk_value(owner, "market") end
    local got = math.floor(amount * mult + math.random())
    local used = amount
    -- ліміт складу: ефір (wood), версиформ (stone), рис (food)
    if human_fortress.RES_CAPPED[res] then
        local room = math.max(0, human_fortress.RES_CAP - (data[res] or 0))
        if got > room then
            got = room
            used = (mult > 0) and math.min(amount, math.ceil(room / mult)) or 0
        end
    end
    data[res] = (data[res] or 0) + got
    return got, used
end

--- Покласти вміст інвентаря юніта на склад з урахуванням ліміту.
--- Повертає залишок, який не влізло (таблиця wood/stone/food).
function human_fortress.deposit_inventory(owner, inv)
    local left = {}
    for _, res in ipairs({"wood", "stone", "food"}) do
        local n = inv[res] or 0
        if n > 0 then
            local _, used = human_fortress.add_resource(owner, res, n)
            left[res] = math.max(0, n - (used or n))
        else
            left[res] = 0
        end
    end
    for k, v in pairs(inv) do
        if left[k] == nil then left[k] = v end   -- loot та інше лишається
    end
    return left
end

-- ---------- Ліміт юнітів ----------
function human_fortress.unit_limit(owner)
    return BASE_UNIT_LIMIT + math.floor(human_fortress.perk_value(owner, "townhall"))
        + 2 * human_fortress.count_buildings(owner, "house")
        + math.floor(human_fortress.perk_value(owner, "house"))
end

function human_fortress.unit_count(owner)
    local n = human_fortress.count_units and human_fortress.count_units(owner) or 0
    local p = human_fortress.players and human_fortress.players[owner]
    if n == 0 and p and p.units then
        for _, u in pairs(p.units) do
            if u and u.object and u.object:get_pos() then n = n + 1 end
        end
    end
    return n
end

function human_fortress.unit_limit_reached(owner)
    if human_fortress.is_overworld then return false end
    local n, lim = human_fortress.unit_count(owner), human_fortress.unit_limit(owner)
    if n >= lim then
        minetest.chat_send_player(owner, "❌ Ліміт юнітів: " .. n .. "/" .. lim ..
            ". Прокачай Ратушу (дерево прокачки → Ратуша → меню Ратуші).")
        return true
    end
    return false
end

-- ---------- Прокорм і голод ----------
local function owned_entities(owner)
    local list = {}
    for _, ent in pairs(minetest.luaentities) do
        local ud = ent.unit_data
        if ud and ud.owner == owner and ent.object and ent.object:get_pos() then
            list[#list + 1] = ent
        end
    end
    return list
end

function human_fortress.food_upkeep(owner, ents)
    ents = ents or owned_entities(owner)
    local civ, mil = 0, 0
    for _, e in ipairs(ents) do
        if COMBAT[e.unit_data.type or ""] then mil = mil + 1 else civ = civ + 1 end
    end
    local disc = math.min(0.8, human_fortress.perk_value(owner, "barracks")
        + (human_fortress.upgrade_rank(owner, "calculation") > 0 and 0.15 or 0)
        + human_fortress.perk_value(owner, "calculation"))
    -- робітник їсть 1, воїн 2 їжі за хвилину
    return math.ceil((civ + mil * 2) * (1 - disc)), #ents
end

local hunger = {}
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < FOOD_PERIOD then return end
    timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local data = human_fortress.edos_data and human_fortress.edos_data[name]
        if data and not human_fortress.is_overworld then
            local ents = owned_entities(name)
            local need = human_fortress.food_upkeep(name, ents)
            if need > 0 then
                if (data.food or 0) >= need then
                    data.food = data.food - need
                    hunger[name] = 0
                else
                    data.food = 0
                    hunger[name] = (hunger[name] or 0) + 1
                    minetest.chat_send_player(name, "⚠️ Не вистачає їжі (потрібно " .. need ..
                        "/хв)! Юніти голодують.")
                    if hunger[name] >= 2 then
                        for _, e in ipairs(ents) do
                            local hp = (e.health or e.object:get_hp() or 10) - STARVE_DAMAGE
                            e.health = hp
                            pcall(function() e.object:set_hp(math.max(hp, 0)) end)
                            if hp <= 0 then
                                pcall(function()
                                    e.object:punch(e.object, 1,
                                        {full_punch_interval = 1, damage_groups = {fleshy = 10000}})
                                end)
                                minetest.chat_send_player(name, "💀 Юніт помер від голоду.")
                            end
                        end
                    end
                end
                if human_fortress.save_data then human_fortress.save_data(name) end
            end
        end
    end
end)

-- ---------- Ліміти будівель на регіон ----------
local BUILD_LIMITS = {
    townhall = 1, market = 1, barracks = 2, carpenter_workshop = 2,
    rice_field = 3, warehouse = 2, auto_collector = 3,
    house = 4, pier = 2, warehouse_branch = 2, archer_tower = 4, bank = 1, lizard_nest = 2,
}
human_fortress.building_limits = BUILD_LIMITS

-- збереження списку побудованого між перезапусками
do
    local raw = storage:get_string("hf_buildings")
    local saved = raw ~= "" and minetest.deserialize(raw)
    if type(saved) == "table" then
        human_fortress.buildings = human_fortress.buildings or {}
        for owner, list in pairs(saved) do
            human_fortress.buildings[owner] = human_fortress.buildings[owner] or list
        end
    end
    local function save()
        storage:set_string("hf_buildings", minetest.serialize(human_fortress.buildings or {}))
    end
    local t = 0
    minetest.register_globalstep(function(dt)
        t = t + dt
        if t > 30 then t = 0 save() end
    end)
    minetest.register_on_shutdown(save)
end

function human_fortress.count_buildings(owner, btype, region)
    local n = 0
    for _, b in ipairs(human_fortress.buildings and human_fortress.buildings[owner] or {}) do
        if b.type == btype and b.pos then
            if not region or not human_fortress.location_at
                    or human_fortress.location_at(b.pos) == region then
                n = n + 1
            end
        end
    end
    return n
end

-- true, nil | false, повідомлення
function human_fortress.check_build_limit(owner, btype, pos)
    local lim = BUILD_LIMITS[btype]
    if not lim then return true end
    local region = human_fortress.location_at and human_fortress.location_at(pos) or nil
    local have = human_fortress.count_buildings(owner, btype, region)
        + (human_fortress.pending_constructions and human_fortress.pending_constructions(owner, btype, region) or 0)
    if have >= lim then
        return false, "Ліміт у цьому регіоні: " .. lim .. " (" .. (BUILDING_NAME[btype] or btype) .. ")"
    end
    return true
end

-- ---------- Прокачка будівлі ----------
local function level_cost(level)
    return {score = 200 * level, stone = 100 * level, wood = 100 * level}
end

local function cost_text(c)
    return "💰" .. c.score .. " 🪨" .. c.stone .. " 🌲" .. c.wood
end

local function inject(name, btype, fs)
    local w, h = fs:match("size%[([%d%.]+),([%d%.]+)%]")
    if not w then return fs end
    h = tonumber(h)
    local perk_id = btype
    local lvl = human_fortress.building_level(name, btype)
    local rank = human_fortress.upgrade_rank(name, perk_id)
    local extra = ""
    local y = h + 0.1
    local n, lim = human_fortress.unit_count(name), human_fortress.unit_limit(name)
    local label = "👥 " .. n .. "/" .. lim .. "   🏗 рівень " .. lvl .. "/" .. MAX_RANK
    extra = extra .. "label[0.3," .. y + 0.2 .. ";" .. minetest.formspec_escape(label) .. "]"
    if lvl >= MAX_RANK then
        extra = extra .. "label[0.3," .. y + 0.8 .. ";✅ Максимальний рівень]"
    elseif rank <= lvl then
        extra = extra .. "label[0.3," .. y + 0.8 .. ";" .. minetest.formspec_escape(
            "🔒 Щоб прокачати: підвищ прокачку у дереві (зараз " .. rank .. ")") .. "]"
    else
        extra = extra .. "button[0.3," .. y + 0.6 .. ";5.4,0.8;bupgrade;" ..
            minetest.formspec_escape("⬆ ПРОКАЧАТИ БУДІВЛЮ → " .. (lvl + 1) .. "  " ..
                cost_text(level_cost(lvl))) .. "]"
    end
    local add_h = 1.7
    if btype == "barracks" then
        extra = extra .. "button[0.3," .. (h + 1.55) .. ";5.4,0.8;recruit_menu;" ..
            minetest.formspec_escape("⚔ Інші бійці: рекрут, спісник, берсерк") .. "]"
        add_h = 2.6
    end
    fs = fs:gsub("size%[[%d%.]+,[%d%.]+%]", function() return "size[" .. w .. "," .. (h + add_h) .. "]" end, 1)
    return fs .. extra
end

local orig_show = minetest.show_formspec
local last_form = {}
minetest.show_formspec = function(name, formname, fs)
    local bt = BUILDING_FORM[formname]
    if bt and type(fs) == "string" and not human_fortress.is_overworld then
        last_form[name] = bt
        local ok, res = pcall(inject, name, bt, fs)
        if ok then fs = res end
    end
    return orig_show(name, formname, fs)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local bt = BUILDING_FORM[formname]
    if bt and fields.recruit_menu then
        if human_fortress.show_recruit_menu then
            human_fortress.show_recruit_menu(player:get_player_name())
        end
        return true
    end
    if not bt or not fields.bupgrade then return end
    local name = player:get_player_name()
    local lvl = human_fortress.building_level(name, bt)
    if lvl >= MAX_RANK then return true end
    if human_fortress.upgrade_rank(name, bt) <= lvl then
        minetest.chat_send_player(name, "🔒 Спершу підвищ прокачку «" .. BUILDING_NAME[bt] .. "» у дереві.")
        return true
    end
    local data = human_fortress.edos_data and human_fortress.edos_data[name]
    local cost = level_cost(lvl)
    for r, a in pairs(cost) do
        if not data or (data[r] or 0) < a then
            minetest.chat_send_player(name, "❌ Не вистачає ресурсів: " .. cost_text(cost))
            return true
        end
    end
    for r, a in pairs(cost) do data[r] = data[r] - a end
    local pd = get_player_data(name)
    pd.building_levels = pd.building_levels or {}
    pd.building_levels[bt] = lvl + 1
    if save_fortress_data then save_fortress_data() end
    minetest.close_formspec(name, formname)
    minetest.chat_send_player(name, "⬆ «" .. BUILDING_NAME[bt] .. "» прокачано до рівня " .. (lvl + 1) ..
        "! Відкрий меню знову.")
    return true
end)

-- команда: статистика
minetest.register_chatcommand("army", {
    description = "Юніти, ліміт і прокорм",
    func = function(name)
        local need, cnt = human_fortress.food_upkeep(name)
        return true, "👥 " .. human_fortress.unit_count(name) .. "/" .. human_fortress.unit_limit(name) ..
            "  🍖 прокорм: " .. need .. "/хв (завантажених юнітів: " .. cnt .. ")"
    end,
})
