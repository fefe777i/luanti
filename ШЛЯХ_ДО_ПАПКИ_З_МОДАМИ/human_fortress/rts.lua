-- ============================================
-- RTS-КАМЕРА, РАМКИ ВИДІЛЕННЯ ТА СТРІЛКИ НАКАЗІВ
-- ============================================
-- Працює разом з рушієм цього форку: player:set_camera({rts = {...}}) вмикає
-- вигляд зверху, де камеру рухають пальцем (один палець - рух, два - зум),
-- а кнопки джойстика/стрибка тощо ховаються.
--
-- Цей файл:
--   * вмикає/вимикає камеру (RTS.enter / RTS.exit)
--   * малює рамку під виділеними юнітами (бачить лише власник)
--   * малює стрілки від юніта до цілі його наказу (бачить лише власник)
--
-- Налаштування (minetest.conf, необов'язкові):
--   human_fortress_rts_radius  - півсторона квадрата, де можна рухати камеру (120)
--   human_fortress_rts_pitch   - кут нахилу камери до горизонту, градуси (62)
--   human_fortress_rts_dist_min / human_fortress_rts_dist_max - зум (12 / 55)

human_fortress = human_fortress or {}
local RTS = {}
human_fortress.rts = RTS

local function num_setting(key, default)
    return tonumber(minetest.settings:get(key)) or default
end

local active = {}      -- active[name] = { was_visible = bool }
local rings = {}       -- rings[name][unit_id] = ObjectRef
local unit_cache = {}  -- unit_id -> ObjectRef (щоб не шукати юніта за радіусом щоразу)

-- ============================================
-- ДОПОМІЖНЕ
-- ============================================

local function get_selected(name)
    local p = human_fortress.players and human_fortress.players[name]
    return (p and p.selected_ids) or {}
end

local function valid_unit(obj, uid)
    if not obj then return nil end
    local pos = obj:get_pos() -- nil, якщо об'єкт уже видалено
    if not pos then return nil end
    local ent = obj:get_luaentity()
    if ent and ent.unit_data and ent.unit_data.unit_id == uid then
        return obj, ent
    end
    return nil
end

--- Знайти юніта за його unit_id (з кешем). Повертає ObjectRef, luaentity або nil.
function RTS.find_unit(uid)
    if not uid then return nil end
    local obj, ent = valid_unit(unit_cache[uid], uid)
    if obj then return obj, ent end
    unit_cache[uid] = nil
    return nil
end

local function rescan(player)
    local pos = player:get_pos()
    if not pos then return end
    for _, o in ipairs(minetest.get_objects_inside_radius(pos, 300)) do
        local ent = o:get_luaentity()
        if ent and ent.unit_data and ent.unit_data.unit_id then
            unit_cache[ent.unit_data.unit_id] = o
        end
    end
end

-- ============================================
-- КАМЕРА
-- ============================================

function RTS.is_active(name)
    return active[name] ~= nil
end

function RTS.enter(player, base_pos)
    local name = player:get_player_name()
    if active[name] then return end
    base_pos = base_pos or player:get_pos()

    local r = num_setting("human_fortress_rts_radius", 120)
    active[name] = { was_visible = player:get_properties().is_visible ~= false }

    player:set_camera({
        mode = "first",
        rts = {
            min = { x = base_pos.x - r, z = base_pos.z - r },
            max = { x = base_pos.x + r, z = base_pos.z + r },
            pitch = num_setting("human_fortress_rts_pitch", 62),
            yaw = 0,
            dist_min = num_setting("human_fortress_rts_dist_min", 12),
            dist_max = num_setting("human_fortress_rts_dist_max", 55),
        },
    })
    -- без прицілу й предмета в руці: камера дивиться зверху
    player:hud_set_flags({ crosshair = false, wielditem = false })
    -- аватар висить у повітрі під камерою - ховаємо його від усіх
    player:set_properties({ is_visible = false })
end

function RTS.exit(player)
    local name = player:get_player_name()
    local st = active[name]
    if not st then return end
    active[name] = nil

    RTS.clear_rings(name)
    player:set_camera({ mode = "any", rts = false })
    player:hud_set_flags({ crosshair = true, wielditem = true })
    player:set_properties({ is_visible = st.was_visible })
end

-- ============================================
-- РАМКА ВИДІЛЕННЯ
-- ============================================

minetest.register_entity("human_fortress:select_ring", {
    initial_properties = {
        visual = "mesh",
        mesh = "human_fortress_flat_quad.obj",
        textures = { "human_fortress_rts_select.png" },
        visual_size = { x = 1.6, y = 1.6, z = 1.6 },
        use_texture_alpha = true,
        backface_culling = false,
        shaded = false,
        glow = 14,
        physical = false,
        collide_with_objects = false,
        pointable = false, -- тап проходить крізь рамку до юніта
        static_save = false,
    },
    on_activate = function(self, staticdata)
        -- бачить лише власник (staticdata = ім'я гравця)
        if staticdata and staticdata ~= "" then
            self.object:set_observers({ [staticdata] = true })
        end
    end,
})

local function ring_size(obj)
    local props = obj:get_properties()
    local cb = props and props.collisionbox or { -0.3, 0, -0.3, 0.3, 1.7, 0.3 }
    local w = math.max(cb[4] - cb[1], cb[6] - cb[3])
    return math.max(1.4, w * 2.0 + 0.6)
end

function RTS.clear_rings(name)
    local list = rings[name]
    if not list then return end
    for _, ring in pairs(list) do
        if ring:get_pos() then ring:remove() end
    end
    rings[name] = nil
end

--- Синхронізувати рамки з поточним виділенням (викликається щокроку).
function RTS.sync(name)
    local player = minetest.get_player_by_name(name)
    if not player then return end
    rings[name] = rings[name] or {}
    local mine = rings[name]

    local want = {}
    for _, uid in ipairs(get_selected(name)) do want[uid] = true end

    -- прибрати рамки з тих, кого більше не виділено
    for uid, ring in pairs(mine) do
        if not want[uid] then
            if ring:get_pos() then ring:remove() end
            mine[uid] = nil
        end
    end

    for uid in pairs(want) do
        local obj = RTS.find_unit(uid)
        if not obj then
            -- не знайшли в кеші: оновлюємо кеш (не частіше ніж раз на секунду)
            local st = active[name]
            local now = minetest.get_us_time()
            if st and (not st.last_scan or now - st.last_scan > 1000000) then
                st.last_scan = now
                rescan(player)
                obj = RTS.find_unit(uid)
            end
        end

        local ring = mine[uid]
        if obj then
            local pos = obj:get_pos()
            local target = { x = pos.x, y = pos.y + 0.06, z = pos.z }
            if not ring or not ring:get_pos() then
                ring = minetest.add_entity(target, "human_fortress:select_ring", name)
                if ring then
                    local s = ring_size(obj)
                    ring:set_properties({ visual_size = { x = s, y = s, z = s } })
                    mine[uid] = ring
                end
            elseif ring then
                ring:move_to(target, true)
            end
        elseif ring then
            -- юніт у сплячому чанку або загинув
            if ring:get_pos() then ring:remove() end
            mine[uid] = nil
        end
    end
end

-- ============================================
-- СТРІЛКИ НАКАЗІВ
-- ============================================

local ORDER_COLORS = {
    move          = "#4cff4c",
    attack        = "#ff4c4c",
    attack_target = "#ff4c4c",
    gather        = "#ffd84c",
    enter         = "#4cc8ff",
    unload        = "#4cc8ff",
    deposit       = "#4cc8ff",
    repair        = "#ffa64c",
    build         = "#ffa64c",
}

local DOT_SPEED = 3.0       -- вузлів за секунду
local ARROW_PERIOD = 0.5    -- як часто оновлюємо стрілки, с

local function is_pos(t)
    return type(t) == "table" and type(t.x) == "number"
            and type(t.y) == "number" and type(t.z) == "number"
end

--- Який наказ виконує юніт і куди. Повертає order, target_pos або nil.
function RTS.get_order(ent)
    local ud = ent.unit_data or {}
    -- наказ щойно відправлено, юніт ще його не прочитав
    if ud.command and is_pos(ud.target) then
        return ud.command, ud.target
    end
    local order = ent.order
    if not order or order == "stand" then return nil end
    if order == "attack_target" and ent.enemy_object then
        local ok, p = pcall(function() return ent.enemy_object:get_pos() end)
        if ok and is_pos(p) then return order, p end
        return nil
    end
    if is_pos(ent.goto_destination) then
        return order, ent.goto_destination
    end
    return nil
end

local function tint(texture, color)
    return texture .. "^[multiply:" .. color
end

local function draw_arrow(name, from, to, color)
    local dist = vector.distance(from, to)
    if dist < 1.2 then return end
    local dir = vector.direction(from, to)

    -- "бігучі" крапки вздовж лінії
    local n = math.min(24, math.max(1, math.floor(dist / 1.5)))
    local spacing = dist / n
    local life = ARROW_PERIOD + 0.05
    local tex = tint("human_fortress_rts_dot.png", color)
    for i = 0, n - 1 do
        local p = vector.add(from, vector.multiply(dir, spacing * (i + 0.5)))
        p.y = p.y + 0.4
        minetest.add_particle({
            pos = p,
            velocity = vector.multiply(dir, math.min(DOT_SPEED, spacing / ARROW_PERIOD)),
            expirationtime = life,
            size = 2.2,
            texture = tex,
            glow = 14,
            playername = name,
        })
    end

    -- стрілка-вказівник над ціллю
    minetest.add_particle({
        pos = { x = to.x, y = to.y + 1.6, z = to.z },
        velocity = { x = 0, y = -1.0, z = 0 },
        expirationtime = life,
        size = 4,
        texture = tint("human_fortress_rts_head.png", color),
        glow = 14,
        playername = name,
    })
end

--- Короткий спалах на цілі наказу (відгук на тап).
function RTS.flash(name, pos, color)
    color = color or "#4cff4c"
    local tex = tint("human_fortress_rts_dot.png", color)
    for i = 1, 14 do
        local a = (i / 14) * math.pi * 2
        minetest.add_particle({
            pos = { x = pos.x, y = pos.y + 0.3, z = pos.z },
            velocity = { x = math.cos(a) * 3, y = 0.2, z = math.sin(a) * 3 },
            acceleration = { x = -math.cos(a) * 3, y = 0, z = -math.sin(a) * 3 },
            expirationtime = 0.6,
            size = 3,
            texture = tex,
            glow = 14,
            playername = name,
        })
    end
end

--- Контур прямокутника на землі (для виділення рамкою). Бачить лише власник.
function RTS.draw_rect(name, a, b, color, seconds)
    color = color or "#4cff4c"
    seconds = seconds or 1.5
    local x1, x2 = math.min(a.x, b.x), math.max(a.x, b.x)
    local z1, z2 = math.min(a.z, b.z), math.max(a.z, b.z)
    local y = math.max(a.y, b.y) + 0.5
    local tex = tint("human_fortress_rts_dot.png", color)
    local function edge(ax, az, bx, bz)
        local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
        local n = math.min(60, math.max(1, math.floor(len / 1.0)))
        for i = 0, n do
            local t = i / n
            minetest.add_particle({
                pos = { x = ax + (bx - ax) * t, y = y, z = az + (bz - az) * t },
                expirationtime = seconds,
                size = 2.5,
                texture = tex,
                glow = 14,
                playername = name,
            })
        end
    end
    edge(x1, z1, x2, z1); edge(x2, z1, x2, z2)
    edge(x2, z2, x1, z2); edge(x1, z2, x1, z1)
end

-- ============================================
-- ВИДІЛЕННЯ РАМКОЮ З ЕКРАНА (рушій шле поле rts_box)
-- ============================================

local function parse_vec(str)
    local x, y, z = str:match("^%s*([%-%d%.eE+]+),([%-%d%.eE+]+),([%-%d%.eE+]+)%s*$")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return { x = x, y = y, z = z } end
    return nil
end

local function cross(a, b)
    return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

--- "ex,ey,ez;r1;r2;r3;r4": позиція камери та напрямки променів через 4 кути
--- рамки. Повертає eye і 4 площини піраміди (нормалі дивляться всередину).
function RTS.parse_box(str)
    if type(str) ~= "string" or #str > 400 then return nil end
    local parts = {}
    for p in str:gmatch("[^;]+") do parts[#parts + 1] = p end
    if #parts ~= 5 then return nil end
    local eye = parse_vec(parts[1])
    local rays = {}
    for i = 1, 4 do rays[i] = parse_vec(parts[i + 1]) end
    if not eye or not rays[1] or not rays[2] or not rays[3] or not rays[4] then return nil end

    local center = { x = 0, y = 0, z = 0 }
    for i = 1, 4 do
        center.x = center.x + rays[i].x
        center.y = center.y + rays[i].y
        center.z = center.z + rays[i].z
    end
    local planes = {}
    for i = 1, 4 do
        local n = cross(rays[i], rays[i % 4 + 1])
        if dot(n, center) < 0 then n = { x = -n.x, y = -n.y, z = -n.z } end
        planes[i] = n
    end
    return eye, planes
end

--- Id всіх юнітів гравця, які на екрані потрапляють у рамку.
function RTS.select_in_box(name, str)
    local eye, planes = RTS.parse_box(str)
    if not eye then return nil end
    local player = minetest.get_player_by_name(name)
    if not player then return nil end

    local ids = {}
    for _, obj in ipairs(minetest.get_objects_inside_radius(eye, 300)) do
        local ent = obj:get_luaentity()
        local ud = ent and ent.unit_data
        if ud and ud.owner == name and ud.unit_id then
            local pos = obj:get_pos()
            if pos then
                local props = obj:get_properties()
                local cb = props and props.collisionbox
                -- беремо точку посередині тіла юніта
                local p = { x = pos.x - eye.x, y = pos.y + (cb and cb[5] or 1.4) * 0.5 - eye.y, z = pos.z - eye.z }
                local inside = true
                for i = 1, 4 do
                    if dot(planes[i], p) < 0 then inside = false break end
                end
                if inside then
                    ids[#ids + 1] = ud.unit_id
                    unit_cache[ud.unit_id] = obj
                end
            end
        end
    end
    return ids
end

function RTS.color_for(order)
    return ORDER_COLORS[order] or "#ffffff"
end

local function draw_orders(name)
    for _, uid in ipairs(get_selected(name)) do
        local obj, ent = RTS.find_unit(uid)
        if obj and ent then
            local order, target = RTS.get_order(ent)
            if order and target then
                draw_arrow(name, obj:get_pos(), target, RTS.color_for(order))
            end
        end
    end
end

-- ============================================
-- ГОЛОВНИЙ ЦИКЛ
-- ============================================

local ring_timer, arrow_timer, prune_timer = 0, 0, 0

minetest.register_globalstep(function(dtime)
    ring_timer = ring_timer + dtime
    arrow_timer = arrow_timer + dtime
    prune_timer = prune_timer + dtime

    if ring_timer >= 0.1 then
        ring_timer = 0
        for name in pairs(active) do
            RTS.sync(name)
        end
    end

    if arrow_timer >= ARROW_PERIOD then
        arrow_timer = 0
        for name in pairs(active) do
            draw_orders(name)
        end
    end

    -- час від часу чистимо кеш від мертвих юнітів
    if prune_timer >= 30 then
        prune_timer = 0
        for uid, obj in pairs(unit_cache) do
            if not valid_unit(obj, uid) then unit_cache[uid] = nil end
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    RTS.clear_rings(name)
    active[name] = nil
end)
