-- ============================================
-- СПИСОК ВИДІЛЕНИХ ЮНІТІВ (збоку, у режимі командування)
-- ============================================
-- Кожен виділений формикс - рядок з іконкою, іменем і HP.
-- Хрестик у рядку знімає виділення з цього юніта. Верхній хрестик - з усіх.

human_fortress = human_fortress or {}

local MAX_ROWS = 6
local ROW_W, ROW_H, ROW_GAP = 150, 38, 3
local MARGIN = 6
local TOP = 70                      -- відступ зверху (нижче лічильників ресурсів/мінімапи)

local lists = {}   -- lists[name] = { sig = "", ids = {...}, uids = {i -> uid}, hp = {i -> hudid} }

local function clear(player, name)
    local l = lists[name]
    if not l then return end
    for _, id in ipairs(l.ids) do player:hud_remove(id) end
    lists[name] = nil
end

local function selected_ids(name)
    local p = human_fortress.players and human_fortress.players[name]
    return (p and p.selected_ids) or {}
end

local function find_ent(uid)
    local rts = human_fortress.rts
    if not rts then return nil end
    return rts.find_unit(uid)
end

local function build(player, name, uids)
    clear(player, name)
    local l = { ids = {}, uids = {}, hp = {}, sig = table.concat(uids, ",") }
    local function add(def)
        def.position = { x = 1, y = 0 }
        def.z_index = def.z_index or 30
        local id = player:hud_add(def)
        l.ids[#l.ids + 1] = id
        return id
    end

    -- заголовок
    local hy = TOP
    add({ hud_elem_type = "image", offset = { x = -(MARGIN + ROW_W / 2), y = hy },
          text = "hf_sel_head.png", scale = { x = 1, y = 1 }, alignment = { x = 0, y = 0 } })
    l.title = add({ hud_elem_type = "text", offset = { x = -(MARGIN + ROW_W - 8), y = hy },
          text = "Виділено: " .. #uids, number = 0xFFE08A, alignment = { x = 1, y = 0 } })
    add({ hud_elem_type = "image", offset = { x = -(MARGIN + 11), y = hy }, name = "hf_desel_all",
          text = "hf_sel_x.png^[resize:20x20", scale = { x = 1, y = 1 },
          alignment = { x = 0, y = 0 }, touchable = true, z_index = 32 })

    local shown = math.min(#uids, MAX_ROWS)
    for i = 1, shown do
        local uid = uids[i]
        l.uids[i] = uid
        local y = TOP + 22 + (i - 1) * (ROW_H + ROW_GAP) + ROW_H / 2
        local _, ent = find_ent(uid)
        local st = ent and human_fortress.unit_stats and human_fortress.unit_stats(ent)
        add({ hud_elem_type = "image", offset = { x = -(MARGIN + ROW_W / 2), y = y },
              text = "hf_sel_row.png", scale = { x = 1, y = 1 }, alignment = { x = 0, y = 0 } })
        add({ hud_elem_type = "image", offset = { x = -(MARGIN + ROW_W - 21), y = y },
              text = ((st and st.icon) or "human_fortress_worker.png") .. "^[resize:24x24",
              scale = { x = 1, y = 1 }, alignment = { x = 0, y = 0 }, z_index = 31 })
        add({ hud_elem_type = "text", offset = { x = -(MARGIN + ROW_W - 42), y = y - 8 },
              text = (st and st.name) or "Юніт", number = 0xFFFFFF,
              alignment = { x = 1, y = 0 }, z_index = 31 })
        l.hp[i] = add({ hud_elem_type = "text", offset = { x = -(MARGIN + ROW_W - 42), y = y + 8 },
              text = st and (st.hp .. "/" .. st.hp_max) or "?", number = 0x7CFC9A,
              alignment = { x = 1, y = 0 }, z_index = 31 })
        add({ hud_elem_type = "image", offset = { x = -(MARGIN + 20), y = y }, name = "hf_desel_" .. i,
              text = "hf_sel_x.png^[resize:28x28", scale = { x = 1, y = 1 },
              alignment = { x = 0, y = 0 }, touchable = true, z_index = 32 })
    end
    if #uids > shown then
        local y = TOP + 22 + shown * (ROW_H + ROW_GAP) + 8
        add({ hud_elem_type = "text", offset = { x = -(MARGIN + ROW_W - 8), y = y },
              text = "… ще " .. (#uids - shown), number = 0xBFE8FF, alignment = { x = 1, y = 0 } })
    end
    lists[name] = l
end

local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 0.3 then return end
    timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local active = human_fortress.rts and human_fortress.rts.is_active(name)
        local uids = active and selected_ids(name) or {}
        if #uids == 0 then
            if lists[name] then clear(player, name) end
        else
            local sig = table.concat(uids, ",")
            local l = lists[name]
            if not l or l.sig ~= sig then
                build(player, name, uids)
            else
                -- оновлюємо HP
                for i, hid in pairs(l.hp) do
                    local _, ent = find_ent(l.uids[i])
                    if ent and human_fortress.unit_stats then
                        local st = human_fortress.unit_stats(ent)
                        player:hud_change(hid, "text", st.hp .. "/" .. st.hp_max)
                    end
                end
            end
        end
    end
end)

--- Зняти виділення з одного юніта
function human_fortress.deselect_unit(name, uid)
    local p = human_fortress.players and human_fortress.players[name]
    if not p or not p.selected_ids then return end
    local new = {}
    for _, id in ipairs(p.selected_ids) do
        if id ~= uid then new[#new + 1] = id end
    end
    p.selected_ids = new
    if human_fortress.rts and human_fortress.rts.is_active(name) then
        human_fortress.rts.sync(name)
    end
end

minetest.register_on_hud_touch(function(player, hud_element_name)
    local name = player:get_player_name()
    if hud_element_name == "hf_desel_all" then
        local p = human_fortress.players and human_fortress.players[name]
        if p then p.selected_ids = {} end
        if human_fortress.rts and human_fortress.rts.is_active(name) then
            human_fortress.rts.sync(name)
        end
        return
    end
    local idx = hud_element_name:match("^hf_desel_(%d+)$")
    if not idx then return end
    local l = lists[name]
    local uid = l and l.uids[tonumber(idx)]
    if uid then human_fortress.deselect_unit(name, uid) end
end)

minetest.register_on_leaveplayer(function(player)
    lists[player:get_player_name()] = nil
end)
