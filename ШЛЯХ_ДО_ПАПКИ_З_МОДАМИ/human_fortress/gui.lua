-------------------------------------------------
-- Human Fortress RTS - HUD та Інтерфейс
-------------------------------------------------

human_fortress = human_fortress or {}
human_fortress.edos_data   = human_fortress.edos_data or {}
human_fortress.hud_ids     = human_fortress.hud_ids or {}
human_fortress.player_pose = human_fortress.player_pose or {}  -- [ім'я] = "sit"/"lay"/nil

local storage = minetest.get_mod_storage()

-- Кеші
local unit_counts = {}
local unit_count_timer = 0
local hud_timer = 0
local current_anim = {}   -- [ім'я] = "walk:1"
local PS = {}             -- стан кожного гравця (голова, стрибок, емоції, аватар)
local now = 0             -- час гри, секунди

-------------------------------------------------
-- 0. Моделі гравця за рівнем + анімації
-------------------------------------------------

-- {мін. рівень, модель, текстура, eye_height, visual_size,
--  жіноча модель, жіноча текстура, жіноча друга текстура (шкіра: голова+руки)}
-- glTF має 10 одиниць на ноду, тому visual_size = старий / 10
local PLAYER_MODELS = {
    {0,  "player_lvl_0.gltf",  "player_lvl_0.png",  1.0, 0.80},
    {10, "player_lvl_10.gltf", "player_lvl_10.png", 1.2, 0.80},
    {20, "player_lvl_20.gltf", "player_lvl_20.png", 1.4, 0.80},
    {30, "player_lvl_30.gltf", "player_lvl_30.png", 1.5, 0.81,
         "player_lvl_30_f.gltf", "player_lvl_30_f.png", "player_lvl_30_f_skin.png"},
    {40, "player_lvl_40.gltf", "player_lvl_40.png", 1.6, 0.89,
         "player_lvl_40_f.gltf", "player_lvl_40_f.png"},
    {50, "player_lvl_50.gltf", "character.png",     1.7, 1.3,
         "player_lvl_50_f.gltf", "player_lvl_50_f.png"},
}

-- Діапазони в секундах (цілі числа!), швидкість = 1
local ANIMS = {
    stand     = {x = 0,  y = 3},
    walk      = {x = 4,  y = 5},
    run       = {x = 6,  y = 7},
    mine      = {x = 8,  y = 9},
    walk_mine = {x = 10, y = 11},
    sit       = {x = 12, y = 13},
    lay       = {x = 14, y = 15},
    jump      = {x = 16, y = 17},
    fall      = {x = 18, y = 19},
    land      = {x = 20, y = 21},
    wave      = {x = 22, y = 24},
    dance     = {x = 25, y = 27},
    clap      = {x = 28, y = 29},
    bow       = {x = 30, y = 32},
    cheer     = {x = 33, y = 34},
    salute    = {x = 35, y = 36},
    shrug     = {x = 37, y = 39},
}

-- Які анімації НЕ зациклені (зупиняються на останньому кадрі)
local NO_LOOP = {jump = true, land = true, bow = true, salute = true, shrug = true}

-- "Звичайні" анімації: для свого гравця клієнт вибирає їх сам за клавішами
local NORMAL = {stand = true, walk = true, run = true, mine = true, walk_mine = true}

-- Запасний варіант (коли аватар вимкнено): клієнт анімує СВОГО гравця за 4 слотами.
local function set_local_normal(player, run)
    player:set_local_animation(
        ANIMS.stand, run and ANIMS.run or ANIMS.walk, ANIMS.mine, ANIMS.walk_mine, 1)
end

local function set_local_special(player, range, speed)
    player:set_local_animation(range, range, range, range, speed)
end

local function apply_local_animations(player)
    if not player or not player:is_player() then return end
    set_local_normal(player, false)
    local st = PS[player:get_player_name()]
    if st then st.lkey = nil end
end

-- Стать: "male" / "female" / "" (ще не обирав)
local function get_gender(player)
    return player:get_meta():get_string("hf_gender")
end

-- Примусова поза: human_fortress.set_player_pose(player, "sit") ; nil = зняти
function human_fortress.set_player_pose(player, pose)
    if not player or not player:is_player() then return end
    human_fortress.player_pose[player:get_player_name()] = pose
end

-------------------------------------------------
-- 0.01 Аватар: тіло гравця як окремий об'єкт (видно і від 1-ї особи)
-------------------------------------------------

-- Справжня модель гравця стає прозорою, а замість неї показується аватар,
-- прикріплений до гравця. Його анімує сервер, тому анімації точні.
-- Рушій (форк) сам показує власне тіло від 1-ї особи й застосовує серверні анімації
-- до локального гравця (client setting fp_own_body, за замовчуванням увімкнено),
-- тому окремий об'єкт-аватар більше не потрібен. true = старий режим з fp_body.
local USE_AVATAR = false
-- Зсув аватара назад (в 1/10 ноди), щоб погляд вниз падав на груди, а не на плечі
local FP_BACK = -1.0
-- Множник розміру аватара (змінюється командою /avatar_scale 0.9)
local AVATAR_MULT = tonumber(storage:get_string("avatar_mult")) or 1.0

local TRANSP = "[combine:1x1"   -- повністю прозора текстура
local ONE = {x = 1, y = 1, z = 1}

minetest.register_entity("human_fortress:fp_body", {
    initial_properties = {
        visual = "mesh",
        mesh = "player_lvl_0.gltf",
        textures = {"player_lvl_0.png"},
        visual_size = {x = 1, y = 1, z = 1},
        physical = false,
        collide_with_objects = false,
        pointable = false,        -- щоб не заважав виділенню юнітів / кліку
        static_save = false,
        backface_culling = true,  -- зсередини голови нічого не видно
        is_visible = true,
    },
    -- staticdata = serialize{owner, mesh, textures, vsize}: властивості виставляються
    -- ОДРАЗУ при створенні (інакше буде дефолтний розмір і текстура)
    on_activate = function(self, staticdata)
        local d = minetest.deserialize(staticdata or "")
        if type(d) == "table" then
            self.owner = d.owner
            self.object:set_properties({
                mesh = d.mesh, textures = d.textures, visual_size = d.vsize,
            })
        end
    end,
    on_step = function(self)
        if not self.owner or not minetest.get_player_by_name(self.owner) then
            self.object:remove()
        end
    end,
})

local function avatar_valid(st)
    if not st or not st.fp then return false end
    local ok, pos = pcall(st.fp.get_pos, st.fp)
    return ok and pos ~= nil
end

-- режим командування: гравця не видно (ні моделі, ні скіна, ні ніка)
local cmd_saved_nt = {}
local function cmd_hidden(player)
    local rts = human_fortress.rts
    return rts and rts.is_active(player:get_player_name()) or false
end

local function avatar_wanted(player)
    return USE_AVATAR and not cmd_hidden(player)
        and player:get_meta():get_string("hf_fpbody") ~= "0"
end

local function scaled(vsize)
    return {x = vsize.x * AVATAR_MULT, y = vsize.y * AVATAR_MULT, z = vsize.z * AVATAR_MULT}
end

-- Справжню модель робимо прозорою (is_visible=false у деяких збірках не спрацьовує
-- і ховав би ще й прикріплені об'єкти). Розмір 1, щоб аватар не наслідував масштаб.
local function hide_real_model(player)
    player:set_properties({
        is_visible = true,
        textures = {TRANSP, TRANSP, TRANSP},
        visual_size = ONE,
    })
end

local function refresh_avatar(player, mesh, texlist, vsize)
    local name = player:get_player_name()
    local st = PS[name]
    if not st then return end

    if not avatar_wanted(player) then
        if avatar_valid(st) then st.fp:remove() end
        st.fp = nil
        if st.saved_nt then player:set_nametag_attributes(st.saved_nt); st.saved_nt = nil end
        return
    end

    if not avatar_valid(st) then
        local sdata = minetest.serialize({
            owner = name, mesh = mesh, textures = texlist, vsize = scaled(vsize),
        })
        local obj = minetest.add_entity(player:get_pos(), "human_fortress:fp_body", sdata)
        if not obj then
            -- не вийшло: повертаємо звичайну модель
            player:set_properties({textures = texlist, visual_size = vsize})
            return
        end
        -- forced_visible = true: інакше прикріплений об'єкт ховається у виді від 1-ї особи
        obj:set_attach(player, "", {x = 0, y = 0, z = FP_BACK}, {x = 0, y = 0, z = 0}, true)
        st.fp = obj
        st.head_sent = nil

        -- нікнейм переходить на аватар
        local nt = player:get_nametag_attributes()
        if nt then
            st.saved_nt = st.saved_nt or nt
            obj:set_nametag_attributes({
                text = (nt.text and nt.text ~= "") and nt.text or name,
                color = nt.color, bgcolor = nt.bgcolor,
            })
            player:set_nametag_attributes({text = ""})
        end
    end

    -- на випадок зміни моделі/текстури/статі
    st.fp:set_properties({mesh = mesh, textures = texlist, visual_size = scaled(vsize)})
    hide_real_model(player)
    current_anim[name] = nil    -- надіслати аватару анімацію
end

local function toggle_avatar(name)
    local player = minetest.get_player_by_name(name)
    if not player then return false, "Гравця не знайдено" end
    local meta = player:get_meta()
    local off = meta:get_string("hf_fpbody") == "0"
    meta:set_string("hf_fpbody", off and "1" or "0")
    human_fortress.update_player_model(player)
    return true, off and "Аватар увімкнено" or "Аватар вимкнено (стара модель гравця)"
end

minetest.register_chatcommand("avatar", {
    description = "Увімкнути/вимкнути аватар (тіло як окремий об'єкт, видно від 1-ї особи)",
    func = toggle_avatar,
})
minetest.register_chatcommand("fpbody", {
    description = "Те саме, що /avatar",
    func = toggle_avatar,
})

minetest.register_chatcommand("avatar_scale", {
    params = "<число, напр. 0.9>",
    description = "Підігнати розмір аватара (1 = як у моделі)",
    func = function(name, param)
        local v = tonumber(param)
        if not v or v < 0.2 or v > 3 then
            return false, "Поточний множник: " .. AVATAR_MULT .. ". Використання: /avatar_scale 0.9"
        end
        AVATAR_MULT = v
        storage:set_string("avatar_mult", tostring(v))
        for _, p in ipairs(minetest.get_connected_players()) do
            human_fortress.update_player_model(p)
        end
        return true, "Множник розміру аватара: " .. v
    end,
})

-------------------------------------------------
-- 0.02 Оновлення моделі гравця
-------------------------------------------------

function human_fortress.update_player_model(player)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    local data = human_fortress.edos_data[name]
    local level = (data and data.level) or 0

    local m = PLAYER_MODELS[1]
    for _, entry in ipairs(PLAYER_MODELS) do
        if level >= entry[1] then m = entry end
    end

    -- модель і текстури за статтю
    local mesh, texlist = m[2], {m[3]}
    if get_gender(player) == "female" and m[6] then
        mesh = m[6]
        texlist = {m[7]}
        if m[8] then texlist[2] = m[8] end   -- 2-й матеріал (шкіра: голова + руки)
    end

    -- обраний скін перекриває основну текстуру
    if rawget(_G, "ws47_skins") then
        local e = ws47_skins.get_choice(player)
        if e then texlist[1] = ws47_skins.texture_for_level(e, level) end
    end

    -- запам'ятовуємо справжній вигляд (для превʼю в меню слів тощо)
    human_fortress.player_look = human_fortress.player_look or {}
    human_fortress.player_look[name] = {mesh = mesh, textures = texlist}

    local vsize = {x = m[5], y = m[5], z = m[5]}
    local use_avatar = PS[name] ~= nil and avatar_wanted(player)
    local hidden = cmd_hidden(player)

    -- вихід з режиму командування: повертаємо нік перед тим, як аватар його забере
    if not hidden and cmd_saved_nt[name] then
        player:set_nametag_attributes(cmd_saved_nt[name])
        cmd_saved_nt[name] = nil
    end

    player:set_properties({
        visual = "mesh",
        mesh = mesh,
        is_visible = true,
        textures = use_avatar and {TRANSP, TRANSP, TRANSP} or texlist,
        visual_size = use_avatar and ONE or vsize,
        eye_height = m[4],
        sprite_yaw_correction = 0,
    })

    apply_local_animations(player)
    current_anim[name] = nil
    if PS[name] then
        PS[name].head_sent = nil
        refresh_avatar(player, mesh, texlist, vsize)
    end

    if hidden then
        -- режим командування: прозорий, без ніка
        local nt = player:get_nametag_attributes()
        if nt and not cmd_saved_nt[name] then
            if not nt.text or nt.text == "" then nt.text = name end
            cmd_saved_nt[name] = nt
        end
        player:set_nametag_attributes({ text = "" })
        player:set_properties({
            is_visible = false,
            textures = { TRANSP, TRANSP, TRANSP },
        })
    end
end

-------------------------------------------------
-- 0.05 Голова за напрямком погляду, тіло відстає
-------------------------------------------------

local MAX_HEAD_YAW = math.rad(50)   -- на скільки голова може повернутись відносно тіла
-- 40°, щоб камера лишалась всередині голови аватара (інакше голова "лізе" в кадр)
local MAX_HEAD_PITCH = math.rad(40)

-- Якщо голова повертається в протилежний бік / киває навпаки: /head_flip yaw  або  /head_flip pitch
local YAW_SIGN   = storage:get_int("yaw_sign");   if YAW_SIGN == 0 then YAW_SIGN = 1 end
local PITCH_SIGN = storage:get_int("pitch_sign"); if PITCH_SIGN == 0 then PITCH_SIGN = 1 end

minetest.register_chatcommand("head_flip", {
    params = "yaw | pitch",
    description = "Перевернути напрямок повороту/кивку голови, якщо він неправильний",
    func = function(name, param)
        if param == "yaw" then
            YAW_SIGN = -YAW_SIGN; storage:set_int("yaw_sign", YAW_SIGN)
        elseif param == "pitch" then
            PITCH_SIGN = -PITCH_SIGN; storage:set_int("pitch_sign", PITCH_SIGN)
        else
            return false, "yaw=" .. YAW_SIGN .. " pitch=" .. PITCH_SIGN ..
                "  (використай: /head_flip yaw  або  /head_flip pitch)"
        end
        for _, p in ipairs(minetest.get_connected_players()) do
            local s = PS[p:get_player_name()]
            if s then s.head_sent = nil end
        end
        return true, "Тепер yaw=" .. YAW_SIGN .. " pitch=" .. PITCH_SIGN
    end,
})

local function angle_diff(a, b)   -- a - b у діапазоні [-pi, pi]
    return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function update_head(player, name, st, dt, ctrl, pose, speed_h)
    if not player.set_bone_override then return end

    local look = player:get_look_horizontal()
    local pitch = player:get_look_vertical()
    if not st.body then st.body = look end

    local moving = ctrl.up or ctrl.down or ctrl.left or ctrl.right or speed_h > 0.5
    local diff = angle_diff(look, st.body)

    if moving or st.emote or pose then
        -- під час руху / емоції / пози тіло швидко вирівнюється за поглядом
        st.idle = 0
        st.body = st.body + diff * math.min(1, dt * (moving and 10 or 6))
    else
        st.idle = st.idle + dt
        if math.abs(diff) > MAX_HEAD_YAW then
            -- повернув голову надто сильно -> тіло піджимається слідом
            st.body = look - (diff > 0 and MAX_HEAD_YAW or -MAX_HEAD_YAW)
        elseif st.idle > 1.2 then
            -- стоїть спокійно -> тіло повільно догоняє голову
            st.body = st.body + diff * math.min(1, dt * 1.5)
        end
    end

    diff = clamp(angle_diff(look, st.body), -MAX_HEAD_YAW, MAX_HEAD_YAW)

    local lying = (pose == "lay")
    local root_y = lying and 0 or -diff * YAW_SIGN
    local head_y = lying and 0 or  diff * YAW_SIGN
    local head_x = lying and 0 or clamp(pitch, -MAX_HEAD_PITCH, MAX_HEAD_PITCH) * PITCH_SIGN

    local sent = st.head_sent
    if not sent or math.abs(sent[1] - root_y) > 0.03 or math.abs(sent[2] - head_y) > 0.03
            or math.abs(sent[3] - head_x) > 0.03 then
        st.head_sent = {root_y, head_y, head_x}
        -- кістки крутимо на аватарі (якщо він є), інакше на моделі гравця
        local target = avatar_valid(st) and st.fp or player
        -- root: поворот тіла + невеликий зсув назад (щоб погляд униз падав на груди)
        target:set_bone_override("root", {
            rotation = {vec = vector.new(0, root_y, 0), interpolation = 0.1},
            position = {vec = vector.new(0, 0, (target == player) and FP_BACK or 0), interpolation = 0.1},
        })
        target:set_bone_override("head", {
            rotation = {vec = vector.new(head_x, head_y, 0), interpolation = 0.1},
        })
    end
end

-------------------------------------------------
-- 0.1 Анімації: ходьба / стрибок / падіння / приземлення / емоції
-------------------------------------------------

local EMOTE_LIST = {
    {id = "wave",   label = "Привіт"},
    {id = "dance",  label = "Танець"},
    {id = "clap",   label = "Оплески"},
    {id = "bow",    label = "Уклін"},
    {id = "cheer",  label = "Ура!"},
    {id = "salute", label = "Честь"},
    {id = "shrug",  label = "Не знаю"},
    {id = "sit",    label = "Сісти"},
}
local EMOTE_IDS = {}
for _, e in ipairs(EMOTE_LIST) do EMOTE_IDS[e.id] = true end

local function node_def_at(pos)
    return minetest.registered_nodes[minetest.get_node(pos).name]
end

-- Чи стоїть гравець на землі (вода/драбина теж рахуються як "на землі")
local function is_on_ground(player, vel)
    local pos = player:get_pos()
    local here = node_def_at(pos)
    if here and (here.liquidtype ~= "none" or here.climbable) then return true end
    if math.abs(vel.y) > 0.6 then return false end
    local below = node_def_at({x = pos.x, y = pos.y - 0.15, z = pos.z})
    return (below and below.walkable) and true or false
end

local function choose_animation(player, name, st, ctrl)
    -- рух або стрибок скасовує емоцію
    local keys = ctrl.up or ctrl.down or ctrl.left or ctrl.right
    if keys or ctrl.jump then
        st.emote = nil
        if st.sit_emote then
            st.sit_emote = false
            human_fortress.player_pose[name] = nil
        end
    end

    local pose = human_fortress.player_pose[name]
    if pose then return pose, 1 end

    if st.land_until > now then return "land", 1 end

    -- стрибок / падіння тільки при справжньому стрибку чи падінні
    -- (політ у fly-режимі їх не вмикає)
    if st.air_state then return st.air_state, 1 end

    if st.emote then return st.emote, 1 end

    local digging = ctrl.LMB or ctrl.RMB
    local anim
    if keys and digging then
        anim = "walk_mine"
    elseif keys then
        anim = ctrl.aux1 and "run" or "walk"
    elseif digging then
        anim = "mine"
    else
        anim = "stand"
    end
    return anim, (ctrl.sneak and keys) and 0.6 or 1
end

local function update_player(player, dt)
    local name = player:get_player_name()
    local st = PS[name]
    if not st then return end

    local ctrl = player:get_player_control()
    local vel = player:get_velocity() or {x = 0, y = 0, z = 0}
    local on_ground = is_on_ground(player, vel)

    -- стан повітря / приземлення
    if on_ground then
        if st.air_state and st.fall_min < -5 then
            st.land_until = now + 0.4
        end
        st.air_state = nil; st.air = 0; st.fall_min = 0
    else
        st.air = st.air + dt
        st.fall_min = math.min(st.fall_min, vel.y)
        if st.air_state == "jump" then
            if vel.y < -1.0 then st.air_state = "fall" end
        elseif st.air_state == "fall" then
            if vel.y > 3.5 then st.air_state = "jump" end
        else
            if vel.y > 3.5 then
                st.air_state = "jump"
            elseif vel.y < -2.5 and st.air > 0.15 then
                st.air_state = "fall"
            end
        end
    end

    local anim, speed = choose_animation(player, name, st, ctrl)

    -- анімація від сервера: аватару (якщо він є), інакше моделі гравця
    local key = anim .. ":" .. speed
    if current_anim[name] ~= key then
        current_anim[name] = key
        st.anim_start = now
        local range = ANIMS[anim] or ANIMS.stand
        local target = avatar_valid(st) and st.fp or player
        target:set_animation(range, speed, 0, not NO_LOOP[anim])
    end

    -- запасний варіант без аватара: слоти клієнта для СВОГО гравця
    if not avatar_valid(st) then
        local lkey
        if NORMAL[anim] then
            lkey = "N:" .. ((anim == "run") and "run" or "walk")
            if st.lkey ~= lkey then
                st.lkey = lkey
                set_local_normal(player, anim == "run")
            end
        else
            local range = ANIMS[anim] or ANIMS.stand
            local hold = NO_LOOP[anim] and anim ~= "jump" and anim ~= "land"
                and (now - (st.anim_start or now)) >= (range.y - range.x) + 0.05
            lkey = "S:" .. anim .. (hold and ":hold" or "") .. ":" .. speed
            if st.lkey ~= lkey then
                st.lkey = lkey
                if hold then
                    set_local_special(player, {x = range.y, y = range.y}, speed)
                else
                    set_local_special(player, range, speed)
                end
            end
        end
    end

    -- раз на 2 с: аватар живий і прикріплений? справжня модель досі прозора?
    -- (інші моди, напр. броня, могли повернути їй текстури)
    st.fp_timer = (st.fp_timer or 0) + dt
    if st.fp_timer > 2 then
        st.fp_timer = 0
        if cmd_hidden(player) then
            player:set_properties({ is_visible = false })
        elseif avatar_wanted(player) then
            local ok_att = avatar_valid(st) and (st.fp:get_attach() ~= nil)
            if ok_att then
                hide_real_model(player)
            else
                if avatar_valid(st) then st.fp:remove() end
                st.fp = nil
                human_fortress.update_player_model(player)
            end
        end
    end

    update_head(player, name, st, dt, ctrl, human_fortress.player_pose[name],
        math.sqrt(vel.x * vel.x + vel.z * vel.z))
end

local local_anim_timer = 0
minetest.register_globalstep(function(dtime)
    now = now + dtime
    local_anim_timer = local_anim_timer + dtime
    local reapply = false
    if local_anim_timer >= 3 then
        local_anim_timer = 0
        reapply = true
    end
    for _, player in ipairs(minetest.get_connected_players()) do
        if reapply then
            local st = PS[player:get_player_name()]
            if st then st.lkey = nil end
        end
        update_player(player, dtime)
    end
end)

-------------------------------------------------
-- 0.2 Колесо емоцій (як у Bedrock)
-------------------------------------------------

local function emote_wheel_formspec()
    local fs = {
        "formspec_version[6]",
        "size[13,10]",
        "bgcolor[#000000B0;true]",
        "label[5.3,0.6;Колесо емоцій]",
    }
    local cx, cy = 6.5, 5.1
    local rx, ry = 4.4, 3.5
    local n = #EMOTE_LIST
    for i, e in ipairs(EMOTE_LIST) do
        local ang = -math.pi / 2 + (i - 1) * (2 * math.pi / n)
        local bx = cx + rx * math.cos(ang)
        local by = cy + ry * math.sin(ang)
        fs[#fs + 1] = string.format("button_exit[%.2f,%.2f;3,1.1;em_%s;%s]",
            bx - 1.5, by - 0.55, e.id, minetest.formspec_escape(e.label))
    end
    fs[#fs + 1] = string.format("button_exit[%.2f,%.2f;2.4,1.2;em_stop;Стоп]", cx - 1.2, cy - 0.6)
    return table.concat(fs)
end

local function show_emote_wheel(player)
    if not player or not player:is_player() then return end
    minetest.show_formspec(player:get_player_name(), "human_fortress:emotes", emote_wheel_formspec())
end

local function play_emote(player, id)
    local name = player:get_player_name()
    local st = PS[name]
    if not st then return end
    st.emote = nil
    if st.sit_emote then
        st.sit_emote = false
        human_fortress.player_pose[name] = nil
    end
    if id == "stop" or not id then return end
    if id == "sit" then
        human_fortress.player_pose[name] = "sit"
        st.sit_emote = true
    elseif EMOTE_IDS[id] and ANIMS[id] then
        st.emote = id
    end
    current_anim[name] = nil
    st.lkey = nil
end
human_fortress.play_emote = play_emote

minetest.register_chatcommand("emote", {
    params = "[wave|dance|clap|bow|cheer|salute|shrug|sit|stop]",
    description = "Колесо емоцій (або одразу емоція)",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Гравця не знайдено" end
        param = param:trim()
        if param == "" then
            show_emote_wheel(player)
            return true, ""
        end
        if param == "stop" or param == "sit" or EMOTE_IDS[param] then
            play_emote(player, param)
            return true, ""
        end
        return false, "Невідома емоція: " .. param
    end,
})

-- Предмет для телефону / без чату: правий клік (або "використати") відкриває колесо
minetest.register_craftitem("human_fortress:emote_wheel", {
    description = "Колесо емоцій",
    inventory_image = "human_fortress_fom.png",
    stack_max = 1,
    on_use = function(itemstack, user)
        show_emote_wheel(user); return itemstack
    end,
    on_secondary_use = function(itemstack, user)
        show_emote_wheel(user); return itemstack
    end,
    on_place = function(itemstack, user)
        show_emote_wheel(user); return itemstack
    end,
})

-------------------------------------------------
-- 0.3 Вибір статі (при першому вході) + /gender
-------------------------------------------------

-- Якщо в превʼю модель дивиться спиною — зміни на "0,0" (або крути мишкою)
local PREVIEW_ROT = "0,180"

local function gender_formspec()
    local boy_model,  boy_tex  = "player_lvl_50.gltf",   "character.png"
    local girl_model, girl_tex = "player_lvl_50_f.gltf", "player_lvl_50_f.png"
    return table.concat({
        "formspec_version[6]",
        "size[13,10]",
        "bgcolor[#000000CC;true]",
        "label[4.2,0.7;Хто ти? Обери свого героя]",
        -- ЗЛІВА дівчина, СПРАВА хлопець
        "model[0.5,1.2;5.5,6.5;model_girl;", girl_model, ";", girl_tex, ";",
            PREVIEW_ROT, ";false;true;0,2;1]",
        "model[7,1.2;5.5,6.5;model_boy;", boy_model, ";", boy_tex, ";",
            PREVIEW_ROT, ";false;true;0,2;1]",
        "button[1.5,8;3.5,1;girl;Я дівчина]",
        "button[8,8;3.5,1;boy;Я хлопець]",
    })
end

local function show_gender_menu(player)
    if not player or not player:is_player() then return end
    minetest.show_formspec(player:get_player_name(), "human_fortress:gender", gender_formspec())
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "human_fortress:emotes" then
        for _, e in ipairs(EMOTE_LIST) do
            if fields["em_" .. e.id] then play_emote(player, e.id); return true end
        end
        if fields.em_stop then play_emote(player, "stop") end
        return true
    end

    if formname ~= "human_fortress:gender" then return false end

    local choice
    if fields.girl then
        choice = "female"
    elseif fields.boy then
        choice = "male"
    end

    if choice then
        player:get_meta():set_string("hf_gender", choice)
        minetest.close_formspec(player:get_player_name(), "human_fortress:gender")
        human_fortress.update_player_model(player)
        minetest.chat_send_player(player:get_player_name(),
            choice == "female" and "Ти обрала дівчину 👧" or "Ти обрав хлопця 👦")
    elseif fields.quit and get_gender(player) == "" then
        -- закрив меню Esc-ом, не вибравши — показуємо знову
        minetest.after(0.3, function() show_gender_menu(player) end)
    end
    return true
end)

minetest.register_chatcommand("gender", {
    description = "Змінити стать персонажа",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Гравця не знайдено" end
        show_gender_menu(player)
        return true, "Меню вибору відкрито"
    end,
})

-------------------------------------------------
-- Події входу (модель, стан, вибір статі, колесо емоцій)
-------------------------------------------------

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    PS[name] = {
        body = nil, idle = 0, air = 0, air_state = nil, fall_min = 0,
        land_until = 0, emote = nil, sit_emote = false,
        head_sent = nil, lkey = nil, anim_start = 0, fp = nil, fp_timer = 0,
    }
    -- вимикаємо стандартні анімації player_api (якщо він є)
    if rawget(_G, "player_api") and player_api.player_attached then
        player_api.player_attached[name] = true
    end
    minetest.after(0.5, function()
        if player and player:is_player() then
            human_fortress.update_player_model(player)
        end
    end)
    -- перший вхід: питаємо хто ти
    minetest.after(3, function()
        if player and player:is_player() and get_gender(player) == "" then
            show_gender_menu(player)
        end
    end)
    -- один раз видаємо предмет "Колесо емоцій"
    minetest.after(4, function()
        if not player or not player:is_player() then return end
        local meta = player:get_meta()
        if meta:get_string("hf_emote_item") == "" then
            local inv = player:get_inventory()
            if inv and inv:room_for_item("main", "human_fortress:emote_wheel") then
                inv:add_item("main", "human_fortress:emote_wheel")
                meta:set_string("hf_emote_item", "1")
                minetest.chat_send_player(name, "Колесо емоцій: предмет у інвентарі або команда /emote")
            end
        end
    end)
end)

minetest.register_on_respawnplayer(function(player)
    minetest.after(0.2, function()
        if player and player:is_player() then
            local name = player:get_player_name()
            current_anim[name] = nil
            if PS[name] then
                PS[name].head_sent = nil; PS[name].emote = nil
                PS[name].land_until = 0; PS[name].air = 0; PS[name].air_state = nil
            end
            human_fortress.update_player_model(player)
        end
    end)
end)

-------------------------------------------------
-- Подарунок за 3 рівень
-------------------------------------------------

local function spawn_level3_gift(player)
    if not player or not player:is_player() then return end

    local pos = player:get_pos()
    pos.y = pos.y + 5

    minetest.add_entity(pos, "human_fortress:level_gift")

    minetest.chat_send_player(player:get_player_name(),
        "🎁 Вітаю з 3 рівнем! Подарунок падає зверху!")
end

minetest.register_entity("human_fortress:level_gift", {
    initial_properties = {
        physical = false,
        visual = "sprite",
        visual_size = {x = 2, y = 2},
        textures = {"gift_box.png"},
    },

    on_step = function(self, dtime)
        if not self.object then return end

        local pos = self.object:get_pos()
        pos.y = pos.y - 5 * dtime

        if pos.y < 0 then
            self.object:remove()
        else
            self.object:set_pos(pos)
        end
    end,
})

-------------------------------------------------
-- Літери МОВА
-------------------------------------------------

local letters = {
    {name = "m", letter = "м"},
    {name = "o", letter = "о"},
    {name = "v", letter = "в"},
    {name = "a", letter = "а"}
}

for _, l in ipairs(letters) do
    minetest.register_node("human_fortress:letter_" .. l.name, {
        description = "Буква " .. string.upper(l.letter),
        tiles = {"letter_" .. l.letter .. ".png"},
        groups = {dig_immediate = 3},
        drawtype = "signlike",
        walkable = false,
        paramtype = "light",
        paramtype2 = "wallmounted",
        drop = "",
    })
end

local function is_letter(nodename)
    return nodename == "human_fortress:letter_m" or
           nodename == "human_fortress:letter_o" or
           nodename == "human_fortress:letter_v" or
           nodename == "human_fortress:letter_a"
end

-- Перевірка чи всі літери стоять правильно (оголошена ДО punchnode)
local function check_letters(player)
    if not player then return end

    local pos = player:get_pos()
    local player_name = player:get_player_name()
    local letters_found = {}
    local all_correct = true

    for x = -10, 10 do
        for z = -10, 10 do
            local check_pos = {x = pos.x + x, y = pos.y, z = pos.z + z}
            local node = minetest.get_node(check_pos)

            if is_letter(node.name) then
                table.insert(letters_found, node)
                if node.param2 ~= 0 then
                    all_correct = false
                end
            end
        end
    end

    if #letters_found == 4 and all_correct then
        minetest.chat_send_all("🎉 Гравець " .. player_name .. " склав слово МОВА!")

        local d = human_fortress.edos_data[player_name]
        if d then
            d.score = (d.score or 0) + 100
        end

        minetest.chat_send_player(player_name, "✅ +100 ейдосів!")
    end
end

-- Поворот при натисканні (wallmounted: param2 тільки 0..5)
minetest.register_on_punchnode(function(pos, node, puncher)
    if not puncher or not puncher:is_player() then return end

    if is_letter(node.name) then
        minetest.swap_node(pos, {
            name = node.name,
            param2 = (node.param2 + 1) % 6
        })

        check_letters(puncher)
    end
end)

-- Чи може гравець говорити
local function can_player_speak(name)
    local data = human_fortress.edos_data[name]
    if not data then return true end
    return (data.level or 1) >= 3
end
human_fortress.can_player_speak = can_player_speak

-------------------------------------------------
-- 1. Оновлення HUD
-------------------------------------------------

function human_fortress.update_hud(player)
    if not player or not player:is_player() then return end

    local name = player:get_player_name()
    local hud = human_fortress.hud_ids[name]
    local data = human_fortress.edos_data[name]

    if not hud or not data then return end

    if hud.rice_text then
        player:hud_change(hud.rice_text, "text", (data.food or 0) .. "/" .. human_fortress.RES_CAP)
    end
    if hud.vers_text then
        player:hud_change(hud.vers_text, "text", (data.stone or 0) .. "/" .. human_fortress.RES_CAP)
    end
    if hud.efir_text then
        player:hud_change(hud.efir_text, "text", (data.wood or 0) .. "/" .. human_fortress.RES_CAP)
    end
    if hud.edos_text then
        player:hud_change(hud.edos_text, "text", tostring(data.score or 0))
    end

    if hud.level_text then
        player:hud_change(hud.level_text, "text", "Lvl " .. tostring(data.level or 1))

        if hud.last_level ~= data.level then
            hud.last_level = data.level
            human_fortress.update_player_model(player)

            if data.level == 3 then
                spawn_level3_gift(player)
            end
        end
    end

    if hud.unit_text then
        player:hud_change(hud.unit_text, "text", tostring(unit_counts[name] or 0))
    end
end

-- 2. "Міст" для оновлення всього
function human_fortress.update_gui(player)
    if not player or not player:is_player() then return end

    human_fortress.update_hud(player)

    if rawget(_G, "unified_inventory") and unified_inventory.get_formspec then
        minetest.after(0.1, function()
            if player and player:is_player() then
                player:set_inventory_formspec(unified_inventory.get_formspec(player))
            end
        end)
    end
end

-------------------------------------------------
-- 3. Створення HUD елементів
-------------------------------------------------

local function create_hud(player)
    if not player or not player:is_player() then return end
    if human_fortress.is_overworld then return end  -- в overworld немає HUD ресурсів
    local name = player:get_player_name()

    if not human_fortress.edos_data[name] then
        minetest.after(1, function()
            if player and player:is_player() then
                create_hud(player)
            end
        end)
        return
    end

    if human_fortress.hud_ids[name] then
        for _, id in pairs(human_fortress.hud_ids[name]) do
            if type(id) == "number" then
                player:hud_remove(id)
            end
        end
    end

    local hud = {
        rice_icon = player:hud_add({
            hud_elem_type = "image", position = {x = 0, y = 0}, offset = {x = 70, y = 35},
            text = "human_fortress_r.png", scale = {x = 2.2, y = 2.2}, alignment = {x = 0, y = 0},
        }),
        rice_text = player:hud_add({
            hud_elem_type = "text", position = {x = 0, y = 0}, offset = {x = 88, y = 35},
            text = "0/" .. human_fortress.RES_CAP, number = 0xFFFFFF, alignment = {x = 0, y = 0},
        }),
        vers_icon = player:hud_add({
            hud_elem_type = "image", position = {x = 0, y = 0}, offset = {x = 70, y = 100},
            text = "human_fortress_v.png", scale = {x = 2.2, y = 2.2}, alignment = {x = 0, y = 0},
        }),
        vers_text = player:hud_add({
            hud_elem_type = "text", position = {x = 0, y = 0}, offset = {x = 88, y = 100},
            text = "0/" .. human_fortress.RES_CAP, number = 0xFFFFFF, alignment = {x = 0, y = 0},
        }),
        efir_icon = player:hud_add({
            hud_elem_type = "image", position = {x = 0, y = 0}, offset = {x = 70, y = 170},
            text = "human_fortress_ef.png", scale = {x = 2.2, y = 2.2}, alignment = {x = 0, y = 0},
        }),
        efir_text = player:hud_add({
            hud_elem_type = "text", position = {x = 0, y = 0}, offset = {x = 88, y = 170},
            text = "0/" .. human_fortress.RES_CAP, number = 0xFFFFFF, alignment = {x = 0, y = 0},
        }),
        -- Лічильник юнітів
        unit_icon = player:hud_add({
            hud_elem_type = "image", position = {x = 0, y = 0}, offset = {x = 200, y = 35},
            text = "human_fortress_fom.png", scale = {x = 2.2, y = 2.2}, alignment = {x = 0, y = 0},
        }),
        unit_text = player:hud_add({
            hud_elem_type = "text", position = {x = 0, y = 0}, offset = {x = 235, y = 35},
            text = "0", number = 0x00FFFF, alignment = {x = 0, y = 0},
        }),
        edos_icon = player:hud_add({
            hud_elem_type = "image", position = {x = 0, y = 0.5}, offset = {x = 20, y = 0},
            text = "edos.png", scale = {x = 3.5, y = 3.5}, alignment = {x = 1, y = 0},
        }),
        edos_text = player:hud_add({
            hud_elem_type = "text", position = {x = 0, y = 0.5}, offset = {x = 75, y = 0},
            text = "0", number = 0xFFFF00, alignment = {x = 1, y = 0},
        }),
        level_text = player:hud_add({
            hud_elem_type = "text", position = {x = 0, y = 0.55}, offset = {x = 70, y = 0},
            text = "Lvl 1", number = 0x00FF00, alignment = {x = 1, y = 0},
        }),
        last_level = 1
    }

    human_fortress.hud_ids[name] = hud

    minetest.after(0.2, function()
        if player and player:is_player() then
            human_fortress.update_gui(player)
        end
    end)
end

-------------------------------------------------
-- 4. Події
-------------------------------------------------

minetest.register_on_joinplayer(function(player)
    minetest.after(2, function()
        if not player or not player:is_player() then return end
        if rawget(_G, "hud_settings") and hud_settings.apply then
            hud_settings.apply(player)
        end
        create_hud(player)
    end)
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    local st = PS[name]
    if avatar_valid(st) then st.fp:remove() end
    human_fortress.hud_ids[name] = nil
    human_fortress.player_pose[name] = nil
    unit_counts[name] = nil
    current_anim[name] = nil
    PS[name] = nil
end)

-------------------------------------------------
-- 5. Крок (HUD + підрахунок юнітів)
-------------------------------------------------

minetest.register_globalstep(function(dtime)
    hud_timer = hud_timer + dtime
    if hud_timer >= 0.5 then
        for _, player in ipairs(minetest.get_connected_players()) do
            human_fortress.update_hud(player)
        end
        hud_timer = 0
    end

    unit_count_timer = unit_count_timer + dtime
    if unit_count_timer >= 2.0 then
        for _, player in ipairs(minetest.get_connected_players()) do
            local name = player:get_player_name()
            local count = 0

            local objs = minetest.get_objects_inside_radius(player:get_pos(), 300)
            for _, obj in ipairs(objs) do
                local ent = obj:get_luaentity()
                if ent and ent.unit_data and ent.unit_data.owner == name then
                    count = count + 1
                end
            end

            unit_counts[name] = count
        end
        unit_count_timer = 0
    end
end)