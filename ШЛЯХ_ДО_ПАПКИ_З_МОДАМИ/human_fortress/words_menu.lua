-- ============================================
-- МЕНЮ СЛІВ У СТИЛІ «НЕОНОВІ ХМАРИНКИ»
-- ============================================
-- Персонаж у рамці по центру, навколо — слова у "хмаринках" різної форми
-- (кістка, хмара, стрічка, шестикутник), по 6 на сторінку.
-- Внизу — Розум / Сила / Воля. Замінює show_words_menu з words.lua.
-- (words.lua не змінюється: завантажується після нього.)

local FORM = "human_fortress:words2"
local INFO = "human_fortress:words2_info"
local PER_PAGE = 6
local POINTS_PER_LEVEL = 4   -- як у words.lua
local SHAPES = {"bone", "cloud", "tag", "pointed"}
local ATTR_NAMES = {
    mind = "Розум", strength = "Сила", will = "Воля", agility = "Спритність",
    speed = "Швидкість", jump = "Стрибок",
}
local RAR_NAMES = {common = "звичайне", uncommon = "незвичайне", rare = "рідкісне",
    epic = "епічне", legendary = "легендарне"}
local STATUS_ORDER = {pending = 1, researching = 2, accepted = 3, rejected = 4}

local page_of = {}

-- (x, y) для 6 слотів: ліво-верх, право-верх, ліво-середина, право-середина, ліво-низ, право-низ
local SLOTS = {
    {0.4, 0.5}, {11.2, 0.5},
    {0.0, 3.4}, {11.6, 3.4},
    {0.4, 6.3}, {11.2, 6.3},
}
local BW, BH = 4.4, 1.9

local function esc(s) return minetest.formspec_escape(tostring(s or "")) end

local function shape_for(id)
    local h = 0
    for i = 1, #id do h = (h * 31 + id:byte(i)) % 9973 end
    return SHAPES[h % #SHAPES + 1]
end

local function mmss(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- переводить дослідження, що закінчились, у "pending"
local function refresh_research(data)
    local now = os.time()
    local changed = false
    for _, wd in pairs(data.words or {}) do
        if wd.status == "researching" and wd.start_time then
            local rt = (wd.word and wd.word.research_time) or 60
            if now >= wd.start_time + rt then
                wd.status = "pending"
                wd.researched = true
                wd.researched_time = now
                changed = true
            end
        end
    end
    if changed and save_fortress_data then save_fortress_data() end
end

local function sorted_words(data)
    local list = {}
    for id, wd in pairs(data.words or {}) do
        if type(wd.word) == "table" then
            list[#list + 1] = {id = id, wd = wd, w = wd.word}
        end
    end
    table.sort(list, function(a, b)
        local oa, ob = STATUS_ORDER[a.wd.status] or 9, STATUS_ORDER[b.wd.status] or 9
        if oa ~= ob then return oa < ob end
        return (a.w.word or "") < (b.w.word or "")
    end)
    return list
end

local function reward_lines(list)
    local out = {}
    for _, r in ipairs(list or {}) do
        local sign = r.amount >= 0 and "+" or ""
        if r.type == "edos" then
            out[#out + 1] = sign .. r.amount .. " Ейдосів"
        elseif r.type == "attribute" then
            out[#out + 1] = sign .. r.amount .. " " .. (ATTR_NAMES[r.attr] or r.attr)
        end
    end
    return table.concat(out, ", ")
end

function show_words_menu(player_name)
    local data = get_player_data and get_player_data(player_name)
    if not data then return end
    data.words = data.words or {}
    refresh_research(data)

    local attrs = data.attributes
        or (human_fortress.get_player_attributes and human_fortress.get_player_attributes(player_name))
        or {}
    local ed = human_fortress.edos_data and human_fortress.edos_data[player_name]
    local level = ed and ed.level or 0

    -- модель і скін гравця: беремо той самий вигляд, що й у грі
    local mesh, tex = "character.b3d", "character.png"
    local look = human_fortress.player_look and human_fortress.player_look[player_name]
    if look and look.mesh then
        mesh = look.mesh
        tex = table.concat(look.textures, ",")
    elseif edit_skin then
        if edit_skin.get_mesh_for_level then mesh = edit_skin.get_mesh_for_level(level) end
        local po = minetest.get_player_by_name(player_name)
        if po and edit_skin.get_skin_texture then tex = edit_skin.get_skin_texture(po) end
    end

    local list = sorted_words(data)
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    local page = math.min(math.max(page_of[player_name] or 1, 1), pages)
    page_of[player_name] = page

    local fs = {
        "formspec_version[6]size[16,9]padding[0.01,0.01]bgcolor[#000000;true]",
        "background[0,0;16,9;hf_words_bg.png;true]",
        "style_type[image_button;border=false;textcolor=#ffffff]",
        "style_type[button;border=false]",
        -- рамка з персонажем
        "image[5.5,1.0;5,7;hf_words_frame.png]",
        "model[5.7,1.4;4.6,5.3;player_preview;", esc(mesh), ";", esc(tex),
        ";0,180;false;true;0,0]",
        "label[7.55,0.6;Ур: ", tostring(level), "]",
    }

    -- слоти
    for slot = 1, PER_PAGE do
        local item = list[(page - 1) * PER_PAGE + slot]
        local x, y = SLOTS[slot][1], SLOTS[slot][2]
        if item then
            local w, st = item.w, item.wd.status
            local shape = shape_for(item.id)
            local img = "hf_bubble_" .. shape .. "_" .. (w.rarity or "common") .. ".png"
            local label = w.word or "?"
            local style = ""
            if st == "researching" then
                local left = (item.wd.start_time or 0) + (w.research_time or 60) - os.time()
                img = img .. "^[multiply:#888888"
                label = label .. "\n⏳ " .. mmss(left)
            elseif st == "pending" then
                label = "❗ " .. label
            elseif st == "accepted" then
                label = label .. "\n✔"
            elseif st == "rejected" then
                img = img .. "^[multiply:#777777"
                label = label .. "\n✖"
            end
            fs[#fs + 1] = string.format("image_button[%g,%g;%g,%g;%s;wd_%s;%s]",
                x, y, BW, BH, img, esc(item.id), esc(label))
            fs[#fs + 1] = string.format("tooltip[wd_%s;%s]", esc(item.id),
                esc((w.description or "") .. " (" .. (RAR_NAMES[w.rarity] or "") .. ", рів. " .. (w.level or 1) .. ")"))
        else
            fs[#fs + 1] = string.format("image[%g,%g;%g,%g;hf_bubble_%s_empty.png]",
                x, y, BW, BH, SHAPES[slot % #SHAPES + 1])
        end
    end

    -- Розум / Сила / Воля
    local stats = {
        {"hf_icon_mind.png", attrs.mind or 0, "Розум"},
        {"hf_icon_strength.png", attrs.strength or 0, "Сила"},
        {"hf_icon_will.png", attrs.will or 0, "Воля"},
    }
    for i, s in ipairs(stats) do
        local x = 5.75 + (i - 1) * 1.55
        local pts = tonumber(s[2]) or 0
        fs[#fs + 1] = string.format("image[%g,6.7;0.9,0.9;%s]", x, s[1])
        fs[#fs + 1] = string.format("label[%g,7.85;Рів. %d]", x, math.floor(pts / POINTS_PER_LEVEL))
        fs[#fs + 1] = string.format("label[%g,8.2;%s оч.]", x, tostring(pts))
        fs[#fs + 1] = string.format("tooltip[%g,6.7;0.9,0.9;%s: %d оч., рівень %d (кожні %d оч. = +1 рівень)]",
            x, s[3], pts, math.floor(pts / POINTS_PER_LEVEL), POINTS_PER_LEVEL)
    end

    -- сторінки
    fs[#fs + 1] = "image_button[6.2,8.1;0.6,0.6;hf_words_prev.png;words2_prev;]"
    fs[#fs + 1] = "label[7.8,8.4;" .. page .. "/" .. pages .. "]"
    fs[#fs + 1] = "image_button[9.2,8.1;0.6,0.6;hf_words_next.png;words2_next;]"
    fs[#fs + 1] = "image_button[14.8,7.9;1,1;hf_words_history.png;words2_history;]"
    fs[#fs + 1] = "tooltip[words2_history;Історія слів]"
    fs[#fs + 1] = "image_button[14.8,0.2;1,1;hf_words_back.png;words2_back;]"
    fs[#fs + 1] = "tooltip[words2_back;Назад]"

    minetest.show_formspec(player_name, FORM, table.concat(fs))
end

local function show_info(player_name, id)
    local data = get_player_data(player_name)
    local wd = data and data.words and data.words[id]
    if not wd or type(wd.word) ~= "table" then return end
    local w = wd.word
    local st = wd.status
    local status_txt = ({
        researching = "⏳ Досліджується",
        accepted = "✔ Прийнято",
        rejected = "✖ Відхилено",
    })[st] or st
    local lines = {
        "formspec_version[6]size[9,7]bgcolor[#0A0A1A;true]",
        "label[0.5,0.6;", esc(w.word), "]",
        "label[0.5,1.2;", esc(w.description), "]",
        "label[0.5,1.8;Рівень ", tostring(w.level or 1), " | ", esc(RAR_NAMES[w.rarity] or ""), "]",
        "label[0.5,2.4;", esc(status_txt), "]",
    }
    if st == "researching" then
        local left = (wd.start_time or 0) + (w.research_time or 60) - os.time()
        lines[#lines + 1] = "label[0.5,3.0;Залишилось: " .. mmss(left) .. "]"
    else
        lines[#lines + 1] = "label[0.5,3.2;✅ Якщо прийняти: " .. esc(reward_lines(w.rewards and w.rewards.accept)) .. "]"
        lines[#lines + 1] = "label[0.5,3.9;❌ Якщо відмовитись: " .. esc(reward_lines(w.rewards and w.rewards.reject)) .. "]"
    end
    lines[#lines + 1] = "button[3,5.6;3,0.9;back;🔙 Назад]"
    minetest.show_formspec(player_name, INFO, table.concat(lines))
end


-- історія: усі прийняті / відхилені слова та що за них отримано
local HIST = "human_fortress:words2_history"
local function show_history(player_name)
    local data = get_player_data(player_name)
    local rows = {}
    for id, wd in pairs(data and data.words or {}) do
        if type(wd.word) == "table" and (wd.status == "accepted" or wd.status == "rejected") then
            rows[#rows + 1] = wd
        end
    end
    table.sort(rows, function(a, b) return (a.researched_time or 0) > (b.researched_time or 0) end)

    local fs = {
        "formspec_version[6]size[12,9]bgcolor[#0A0A1A;true]",
        "label[0.5,0.6;📜 Історія слів: ", tostring(#rows), "]",
        "button[10,0.25;1.5,0.7;hist_back;Назад]",
        "box[0.4,1.2;11.2,7.3;#14142A]",
    }
    if #rows == 0 then
        fs[#fs + 1] = "label[0.8,2;Поки що немає прийнятих чи відхилених слів.]"
    else
        local rowh = 1.0
        local total = #rows * rowh
        fs[#fs + 1] = "scroll_container[0.5,1.3;10.6,7.1;hist_scroll;vertical;0.1]"
        for i, wd in ipairs(rows) do
            local w = wd.word
            local acc = wd.status == "accepted"
            local y = (i - 1) * rowh
            local head = (acc and minetest.colorize("#6bff8a", "✔ Прийнято: ")
                or minetest.colorize("#ff6b6b", "✖ Відхилено: ")) .. minetest.colorize("#ffffff", w.word or "?")
            local got = reward_lines(w.rewards and (acc and w.rewards.accept or w.rewards.reject))
            fs[#fs + 1] = "label[0.2," .. (y + 0.25) .. ";" .. esc(head) .. "]"
            fs[#fs + 1] = "label[0.2," .. (y + 0.65) .. ";" .. esc("Отримано: " .. (got ~= "" and got or "—")) .. "]"
        end
        fs[#fs + 1] = "scroll_container_end[]"
        fs[#fs + 1] = "scrollbaroptions[max=" .. math.max(0, math.floor((total - 7.1) * 10 + 5)) .. "]"
        fs[#fs + 1] = "scrollbar[11.1,1.3;0.4,7.1;vertical;hist_scroll;0]"
    end
    minetest.show_formspec(player_name, HIST, table.concat(fs))
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()
    if formname == HIST then
        if fields.hist_back then show_words_menu(name) end
        return true
    end
    if formname == INFO then
        if fields.back then show_words_menu(name) end
        return true
    end
    if formname ~= FORM then return false end

    if fields.words2_back then
        if show_vilka_menu then show_vilka_menu(name) end
        return true
    end
    if fields.words2_history then
        show_history(name)
        return true
    end
    if fields.words2_prev then
        page_of[name] = (page_of[name] or 1) - 1
        show_words_menu(name)
        return true
    end
    if fields.words2_next then
        page_of[name] = (page_of[name] or 1) + 1
        show_words_menu(name)
        return true
    end
    for field in pairs(fields) do
        if field:sub(1, 3) == "wd_" then
            local id = field:sub(4)
            local data = get_player_data(name)
            local wd = data and data.words and data.words[id]
            if wd and wd.status == "pending" then
                -- вибір «прийняти / відмовитись» — старе меню з words.lua
                for _, cb in ipairs(minetest.registered_on_player_receive_fields) do
                    if cb(player, "human_fortress:words", {["word_" .. id] = "1"}) then break end
                end
            elseif wd then
                show_info(name, id)
            end
            return true
        end
    end
    return true
end)

minetest.register_on_leaveplayer(function(player)
    page_of[player:get_player_name()] = nil
end)
