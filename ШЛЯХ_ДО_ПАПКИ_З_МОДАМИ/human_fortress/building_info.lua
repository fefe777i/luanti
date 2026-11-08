-- ============================================
-- ПАНЕЛЬ БУДІВЛІ (внизу, у режимі командування)
-- ============================================
-- Тап інструментом виділення по будівлі (або по майданчику, що будується) показує:
-- HP, рівень, що виробляє / у якому стані, чи є всередині/поруч юніти.

human_fortress = human_fortress or {}

local MODPATH = minetest.get_modpath("human_fortress")
local PW, PH = 340, 104
local bpanels = {}   -- bpanels[name] = { ids = {}, key = "" }

local function file_exists(rel)
    local f = io.open(MODPATH .. "/textures/" .. rel, "rb")
    if f then f:close() return true end
    return false
end

-- обрізати рядок по символах UTF-8
local function cut(str, n)
    str = str or ""
    local out, cnt = {}, 0
    for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        cnt = cnt + 1
        if cnt > n then out[#out + 1] = "…" break end
        out[#out + 1] = ch
    end
    return table.concat(out)
end

-- ---------- пошук будівлі за точкою ----------
function human_fortress.building_at(pos, owner)
    if not human_fortress.known_cores or not human_fortress.get_core_data then return nil end
    for _, core in pairs(human_fortress.known_cores) do
        if type(core) == "table" and core.x then
            local d = human_fortress.get_core_data(core)
            if d and d.min and d.max and (not owner or d.owner == "" or d.owner == owner)
                    and pos.x >= d.min.x and pos.x <= d.max.x
                    and pos.y >= d.min.y and pos.y <= d.max.y
                    and pos.z >= d.min.z and pos.z <= d.max.z then
                return core
            end
        end
    end
end

local function own_units_near(owner, center, radius)
    local n = 0
    for _, o in ipairs(minetest.get_objects_inside_radius(center, radius)) do
        local e = o:get_luaentity()
        if e and e.unit_data and e.unit_data.owner == owner and (e.health or 1) > 0 then
            n = n + 1
        end
    end
    return n
end

local function building_icon(btype, schem)
    local g = "human_fortress_" .. btype .. ".png"
    if file_exists(g) then return g end
    if schem and schem.icon and file_exists(schem.icon) then return schem.icon end
    return "human_fortress_house.png"
end

-- ---------- збір інформації ----------
local function info_core(core_pos)
    local data = human_fortress.get_core_data(core_pos)
    if not data or data.building_type == "" then return nil end
    local btype, owner = data.building_type, data.owner
    local schem = BUILDING_SCHEMATICS and BUILDING_SCHEMATICS[btype] or {}
    local meta = minetest.get_meta(core_pos)
    local max_hp = meta:get_int("building_max_hp")
    local hp = meta:get_int("building_hp")
    if max_hp <= 0 then max_hp = schem.health or schem.max_hp or 100 end
    if hp <= 0 or hp > max_hp then hp = max_hp end
    local lvl = human_fortress.building_level and human_fortress.building_level(owner, btype) or 1

    local center = {
        x = (data.min.x + data.max.x) / 2, y = (data.min.y + data.max.y) / 2,
        z = (data.min.z + data.max.z) / 2,
    }
    local near = own_units_near(owner, center, 12)

    local lines = { "Рівень: " .. lvl }
    if btype == "carpenter_workshop" and human_fortress.carpenter_status then
        local st = human_fortress.carpenter_status(owner, core_pos)
        if st.recipe then
            lines[#lines + 1] = "Виробляє: " .. cut(st.recipe, 14) .. " " .. st.pct .. "%"
        else
            lines[#lines + 1] = "Виробляє: нічого (ПКМ - меню)"
        end
        lines[#lines + 1] = st.worker and "Майстер: є" or "Майстер: немає - надішли юніта!"
    elseif btype == "archer_tower" and human_fortress.tower_garrison then
        local n = human_fortress.tower_garrison(owner, data.building_pos or core_pos)
        local cap = human_fortress.tower_capacity and human_fortress.tower_capacity(owner) or 2
        lines[#lines + 1] = "Гарнізон лучників: " .. n .. "/" .. cap
        lines[#lines + 1] = "Дальність: " .. (human_fortress.tower_range and human_fortress.tower_range(owner, n) or "?")
    elseif btype == "pier" then
        lines[#lines + 1] = "Виробляє: їжу щохвилини"
        lines[#lines + 1] = "Юнітів поруч: " .. near
    else
        lines[#lines + 1] = cut(schem.description or "", 26)
        lines[#lines + 1] = "Юнітів поруч: " .. near
    end

    return {
        key = "core:" .. minetest.pos_to_string(core_pos),
        name = schem.name or btype, icon = building_icon(btype, schem),
        hp_text = hp .. "/" .. max_hp, lines = lines,
    }
end

local function info_site(id)
    local inf = human_fortress.construction_info and human_fortress.construction_info(id)
    if not inf then return nil end
    local schem = BUILDING_SCHEMATICS and BUILDING_SCHEMATICS[inf.type] or {}
    return {
        key = "site:" .. id,
        name = "🏗 " .. (schem.name or inf.type), icon = building_icon(inf.type, schem),
        hp_text = inf.pct .. "%",
        lines = {
            "Будується: " .. inf.pct .. "% (" .. inf.done .. "/" .. inf.total .. ")",
            "Будівельників: " .. inf.builders .. "/" .. inf.max_builders,
            inf.builders == 0 and "Виділи формика > Рух > тап сюди" or "Більше будівельників - швидше",
        },
    }
end

local function get_info(name)
    local p = human_fortress.players and human_fortress.players[name]
    local sel = p and p.selected_building
    if not sel then return nil end
    local info
    if sel.kind == "core" then info = info_core(sel.pos)
    elseif sel.kind == "site" then info = info_site(sel.id) end
    if not info then p.selected_building = nil end   -- будівлі вже нема
    return info
end

-- ---------- HUD ----------
local function remove_panel(player, name)
    local bp = bpanels[name]
    if not bp then return end
    for _, id in pairs(bp.ids) do player:hud_remove(id) end
    bpanels[name] = nil
end

local function create_panel(player, name, info)
    local ox, oy = -PW / 2, -12 - PH
    local function at(lx, ly) return { x = ox + lx, y = oy + ly } end
    local ids = {}
    local function img(key, lx, ly, text)
        ids[key] = player:hud_add({
            hud_elem_type = "image", position = { x = 0.5, y = 1.0 }, offset = at(lx, ly),
            text = text, scale = { x = 1, y = 1 }, alignment = { x = 0, y = 0 }, z_index = 20,
        })
    end
    local function txt(key, lx, ly, text, color, align)
        ids[key] = player:hud_add({
            hud_elem_type = "text", position = { x = 0.5, y = 1.0 }, offset = at(lx, ly),
            text = text, number = color or 0xFFFFFF, alignment = { x = align or 1, y = 0 },
            z_index = 21,
        })
    end
    img("bg", PW / 2, PH / 2, "hf_building_panel_bg.png")
    img("icon", 42, 40, info.icon .. "^[resize:64x64")
    txt("hp", 42, 88, info.hp_text, 0xFFFFFF, 0)
    txt("name", 86, 16, info.name, 0xFFE08A)
    for i = 1, 4 do
        txt("l" .. i, 86, 16 + i * 18, info.lines[i] or "", 0xBFE8FF)
    end
    bpanels[name] = { ids = ids, key = info.key }
end

local function update_panel(player, name, info)
    local ids = bpanels[name].ids
    player:hud_change(ids.hp, "text", info.hp_text)
    player:hud_change(ids.name, "text", info.name)
    for i = 1, 4 do
        player:hud_change(ids["l" .. i], "text", info.lines[i] or "")
    end
end

local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 0.4 then return end
    timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local active = human_fortress.rts and human_fortress.rts.is_active(name)
        local info = active and get_info(name) or nil
        if not info then
            if bpanels[name] then remove_panel(player, name) end
        else
            if bpanels[name] and bpanels[name].key ~= info.key then remove_panel(player, name) end
            if not bpanels[name] then create_panel(player, name, info) end
            update_panel(player, name, info)
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    bpanels[player:get_player_name()] = nil
end)
