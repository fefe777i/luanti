-- ============================================
-- construction.lua - поетапне будівництво.
-- Будують виділені формики (будь-які): біжать до майданчика і "б'ють молотком",
-- а будівля росте блок за блоком знизу вгору. Швидкість = кількість будівельників.
-- ============================================

local storage = minetest.get_mod_storage()

local BLOCKS_PER_SEC = 3      -- блоків за секунду на одного будівельника
local MAX_BUILDERS = 6
local TICK = 0.25
local RUN_SPEED = 3.2

local jobs = {}        -- id -> job
local next_id = 1

-- ---------- Хітбокс майданчика ----------
-- Поки будівля не завершена, на її місці стоїть сутність-хітбокс: по ній можна тапнути
-- (вибрати для перегляду або віддати наказ "Рух" - формики піднімуться будувати).
minetest.register_entity("human_fortress:build_site", {
    initial_properties = {
        visual = "cube",
        textures = { "hf_site_frame.png", "hf_site_frame.png", "hf_site_frame.png",
                     "hf_site_frame.png", "hf_site_frame.png", "hf_site_frame.png" },
        visual_size = { x = 1, y = 1, z = 1 },
        use_texture_alpha = true,
        backface_culling = false,
        shaded = false,
        glow = 8,
        physical = false,
        collide_with_objects = false,
        pointable = true,
        static_save = false,
        collisionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
        selectionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
    },
    is_build_site = true,
    on_punch = function() return true end,   -- не ламається
})

local function spawn_site(job)
    local mn, mx = job.min, job.max
    local w = (mx.x - mn.x) + 1
    local h = (mx.y - mn.y) + 1
    local d = (mx.z - mn.z) + 1
    local center = { x = (mn.x + mx.x) / 2, y = (mn.y + mx.y) / 2, z = (mn.z + mx.z) / 2 }
    local obj = minetest.add_entity(center, "human_fortress:build_site")
    if not obj then return end
    local ent = obj:get_luaentity()
    if ent then ent.job_id = job.id ent.owner = job.owner end
    local hx, hy, hz = w / 2, h / 2, d / 2
    obj:set_properties({
        visual_size = { x = w + 0.1, y = h + 0.1, z = d + 0.1 },
        collisionbox = { -hx, -hy, -hz, hx, hy, hz },
        selectionbox = { -hx, -hy, -hz, hx, hy, hz },
    })
    job.site = obj
end

-- ---------- Підготовка списку блоків ----------
local function prepare(pos, rotation, filepath)
    local schem = minetest.read_schematic(filepath, {})
    if not schem or not schem.size then return nil end
    local m = math.max(schem.size.x, schem.size.z)
    local minp = {x = pos.x - m, y = pos.y - 1, z = pos.z - m}
    local maxp = {x = pos.x + m, y = pos.y + schem.size.y + 1, z = pos.z + m}
    minetest.load_area(minp, maxp)

    local vm = VoxelManip(minp, maxp)
    local emin, emax = vm:read_from_map(minp, maxp)
    local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
    local d0, p0 = vm:get_data(), vm:get_param2_data()
    local before, bp = {}, {}
    for i = 1, #d0 do before[i] = d0[i] bp[i] = p0[i] end

    if not minetest.place_schematic_on_vmanip(vm, pos, filepath, tostring(rotation), nil, true) then
        return nil
    end
    local d1, p1 = vm:get_data(), vm:get_param2_data()

    local c_air = minetest.CONTENT_AIR
    local clear, blocks = {}, {}
    local cx = pos.x + schem.size.x / 2
    local cz = pos.z + schem.size.z / 2
    for z = emin.z, emax.z do
        for y = emin.y, emax.y do
            for x = emin.x, emax.x do
                local i = area:index(x, y, z)
                if d1[i] ~= before[i] or p1[i] ~= bp[i] then
                    if d1[i] == c_air then
                        if before[i] ~= c_air then clear[#clear + 1] = {x = x, y = y, z = z} end
                    elseif d1[i] ~= minetest.CONTENT_IGNORE then
                        blocks[#blocks + 1] = {
                            p = {x = x, y = y, z = z},
                            name = minetest.get_name_from_content_id(d1[i]),
                            p2 = p1[i],
                            k = y * 100000 + ((x - cx) ^ 2 + (z - cz) ^ 2),
                        }
                    end
                end
            end
        end
    end
    -- знизу вгору, у кожному шарі від центру назовні
    table.sort(blocks, function(a, b) return a.k < b.k end)
    return {blocks = blocks, clear = clear, size = schem.size}
end

-- ---------- Будівельники ----------
local function alive(ent)
    return ent and ent.object and ent.object:get_pos() ~= nil
end

local function release(job)
    for _, ent in ipairs(job.builders) do
        if alive(ent) then
            ent.build_lock, ent.build_target = nil, nil
            ent.order = "stand"
            ent.object:set_velocity({x = 0, y = 0, z = 0})
        end
    end
    job.builders = {}
end

local function move_builder(ent, target, dt)
    local o = ent.object
    local p = o:get_pos()
    local dx, dz = target.x - p.x, target.z - p.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist > 40 or math.abs(target.y - p.y) > 12 then
        o:set_pos({x = target.x, y = target.y + 0.5, z = target.z})
        return true
    end
    if dist > 1.2 then
        local v = o:get_velocity() or {x = 0, y = 0, z = 0}
        o:set_velocity({x = dx / dist * RUN_SPEED, y = v.y, z = dz / dist * RUN_SPEED})
        o:set_yaw(math.atan2(-dx, dz))
        -- застряг? - короткий стрибок
        if (ent._bp and ent._bp.x == math.floor(p.x) and ent._bp.z == math.floor(p.z)) then
            ent._stuck = (ent._stuck or 0) + dt
            if ent._stuck > 1.5 and v.y == 0 then
                o:set_velocity({x = dx / dist * RUN_SPEED, y = 6, z = dz / dist * RUN_SPEED})
                ent._stuck = 0
            end
        else
            ent._stuck = 0
        end
        ent._bp = {x = math.floor(p.x), z = math.floor(p.z)}
        return false
    end
    local v = o:get_velocity() or {x = 0, y = 0, z = 0}
    o:set_velocity({x = 0, y = v.y, z = 0})
    return true
end

-- ---------- Індикатор прогресу ----------
local function hud_update(job, text)
    local pl = minetest.get_player_by_name(job.owner)
    if not pl then return end
    if job.hud then
        pl:hud_change(job.hud, "text", text)
    else
        job.hud = pl:hud_add({
            hud_elem_type = "text", position = {x = 0.5, y = 0.12},
            offset = {x = 0, y = 0}, text = text, number = 0xFFD060, alignment = {x = 0, y = 0},
            z_index = 100,
        })
    end
end

local function hud_remove(job)
    local pl = minetest.get_player_by_name(job.owner)
    if pl and job.hud then pl:hud_remove(job.hud) end
    job.hud = nil
end

-- ---------- Завершення / тік ----------
local function save_jobs()
    local out = {}
    for id, j in pairs(jobs) do
        out[#out + 1] = {owner = j.owner, type = j.type, pos = j.pos, rotation = j.rotation}
    end
    storage:set_string("hf_construction", minetest.serialize(out))
end

local function complete(id)
    local job = jobs[id]
    if not job then return end
    jobs[id] = nil
    release(job)
    hud_remove(job)
    if job.site and job.site:get_pos() then job.site:remove() end
    save_jobs()
    if job.finish then job.finish() end
end

local function step_job(id, job, dt)
    -- залишити живих будівельників
    local live = {}
    for _, e in ipairs(job.builders) do if alive(e) then live[#live + 1] = e end end
    job.builders = live
    if #live == 0 then
        job.idle = (job.idle or 0) + dt
        if job.idle > 0 and not job.warned then
            job.warned = true
            minetest.chat_send_player(job.owner, "⏸ Будівництво зупинилось: немає будівельників. Виділи формика і підтверди будівництво знову на тому ж місці.")
        end
        hud_update(job, "🏗 Будівництво призупинено")
        return
    end

    local total = #job.blocks
    local cur = job.blocks[math.min(job.index, total)]
    local site = cur and cur.p or job.pos
    -- кожен будівельник стоїть біля майданчика на землі, з боку, звідки прийшов
    local center = {x = job.pos.x + job.size.x / 2, z = job.pos.z + job.size.z / 2}
    local working = 0
    for i, ent in ipairs(live) do
        local ang = (i / #live) * 2 * math.pi + job.phase
        local r = math.max(job.size.x, job.size.z) / 2 + 2.5
        local target = {x = center.x + math.cos(ang) * r, y = job.pos.y, z = center.z + math.sin(ang) * r}
        local at = move_builder(ent, target, dt)
        ent.build_working = at
        if at then
            working = working + 1
            -- повернутись обличчям до будівлі
            local dx, dz = center.x - ent.object:get_pos().x, center.z - ent.object:get_pos().z
            ent.object:set_yaw(math.atan2(-dx, dz))
        end
    end

    if working > 0 then
        job.acc = job.acc + working * BLOCKS_PER_SEC * dt
        local n = math.floor(job.acc)
        job.acc = job.acc - n
        for _ = 1, n do
            local b = job.blocks[job.index]
            if not b then break end
            minetest.set_node(b.p, {name = b.name, param2 = b.p2})
            job.index = job.index + 1
            if job.index % 3 == 0 then
                minetest.add_particlespawner({
                    amount = 4, time = 0.1,
                    minpos = {x = b.p.x - 0.4, y = b.p.y - 0.4, z = b.p.z - 0.4},
                    maxpos = {x = b.p.x + 0.4, y = b.p.y + 0.4, z = b.p.z + 0.4},
                    minvel = {x = -1, y = 0.5, z = -1}, maxvel = {x = 1, y = 2, z = 1},
                    minexptime = 0.3, maxexptime = 0.7, minsize = 0.6, maxsize = 1.2,
                    texture = "default_item_smoke.png",
                })
            end
        end
        if n > 0 then
            minetest.sound_play("default_place_node_hard", {pos = site, gain = 0.4, max_hear_distance = 24}, true)
        end
    end

    local pct = math.min(100, math.floor((job.index - 1) / math.max(1, total) * 100))
    hud_update(job, "🏗 Будівництво: " .. pct .. "%   👷 " .. working .. "/" .. #live)
    if job.index > total then complete(id) end
end

local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < TICK then return end
    local dt = timer
    timer = 0
    for id, job in pairs(jobs) do
        local ok, err = pcall(step_job, id, job, dt)
        if not ok then
            minetest.log("error", "[human_fortress] construction: " .. tostring(err))
            complete(id)
        end
    end
end)

-- ---------- API ----------
function human_fortress.pending_constructions(owner, btype, region)
    local n = 0
    for _, j in pairs(jobs) do
        if j.owner == owner and j.type == btype and
                (not region or not human_fortress.location_at or human_fortress.location_at(j.pos) == region) then
            n = n + 1
        end
    end
    return n
end

--- Майданчик, у межі якого потрапляє точка (з невеликим запасом).
function human_fortress.construction_at(pos, owner)
    for id, j in pairs(jobs) do
        local m = j.min
        local M = j.max
        if (not owner or j.owner == owner)
                and pos.x >= m.x - 1 and pos.x <= M.x + 1
                and pos.y >= m.y - 2 and pos.y <= M.y + 2
                and pos.z >= m.z - 1 and pos.z <= M.z + 1 then
            return id, j
        end
    end
end

--- Приєднати формиків до будівництва. Повертає кількість доданих.
function human_fortress.construction_join(id, ents)
    local job = jobs[id]
    if not job then return 0 end
    local added = 0
    for _, e in ipairs(ents) do
        if #job.builders >= MAX_BUILDERS then break end
        if alive(e) and not e.build_lock then
            e.build_lock = true
            e.order = "build"
            e.path_nodes = nil
            job.builders[#job.builders + 1] = e
            added = added + 1
        end
    end
    if added > 0 then
        job.warned = nil
        job.idle = 0
    end
    return added
end

function human_fortress.construction_info(id)
    local job = jobs[id]
    if not job then return nil end
    local total = #job.blocks
    local live = 0
    for _, e in ipairs(job.builders) do if alive(e) then live = live + 1 end end
    return {
        type = job.type, owner = job.owner, total = total,
        done = math.min(total, job.index - 1),
        pct = math.min(100, math.floor((job.index - 1) / math.max(1, total) * 100)),
        builders = live, max_builders = MAX_BUILDERS,
        min = job.min, max = job.max,
    }
end

function human_fortress.start_construction(owner, btype, pos, rotation, filepath, finish, builder_ents)
    if not (minetest.place_schematic_on_vmanip and minetest.read_schematic) then return false end
    local data = prepare(pos, rotation, filepath)
    if not data or #data.blocks == 0 then return false end

    -- розчистити майданчик (дерева, трава)
    for _, c in ipairs(data.clear) do minetest.set_node(c, {name = "air"}) end

    local builders = {}
    for _, e in ipairs(builder_ents or {}) do
        if alive(e) and not e.build_lock and #builders < MAX_BUILDERS then
            e.build_lock = true
            e.order = "build"
            e.path_nodes = nil
            builders[#builders + 1] = e
        end
    end
    if #builders == 0 then return false end

    local id = next_id
    next_id = next_id + 1
    -- межі майданчика за реальними блоками (враховує поворот схеми)
    local mn = {x = math.huge, y = math.huge, z = math.huge}
    local mx = {x = -math.huge, y = -math.huge, z = -math.huge}
    for _, b in ipairs(data.blocks) do
        mn.x = math.min(mn.x, b.p.x) mn.y = math.min(mn.y, b.p.y) mn.z = math.min(mn.z, b.p.z)
        mx.x = math.max(mx.x, b.p.x) mx.y = math.max(mx.y, b.p.y) mx.z = math.max(mx.z, b.p.z)
    end
    jobs[id] = {
        min = mn, max = mx,
        id = id, owner = owner, type = btype, pos = {x = pos.x, y = pos.y, z = pos.z},
        rotation = rotation, size = data.size, blocks = data.blocks, index = 1,
        builders = builders, acc = 0, phase = math.random() * 6.28, finish = finish,
    }
    spawn_site(jobs[id])
    save_jobs()

    local secs = math.ceil(#data.blocks / (#builders * BLOCKS_PER_SEC))
    minetest.chat_send_player(owner, "🏗️ Будівництво розпочато: " .. #data.blocks ..
        " блоків, будівельників " .. #builders .. ", приблизно " .. secs .. " с.")
    return true
end

-- після перезапуску сервера недобудоване добудовується одразу
minetest.after(5, function()
    local raw = storage:get_string("hf_construction")
    local saved = raw ~= "" and minetest.deserialize(raw)
    storage:set_string("hf_construction", "")
    if type(saved) ~= "table" then return end
    for _, j in ipairs(saved) do
        local sch = BUILDING_SCHEMATICS and BUILDING_SCHEMATICS[j.type]
        if sch and sch.schematic then
            local filepath = minetest.get_modpath("human_fortress") .. "/schematics/" .. sch.schematic
            minetest.load_area(j.pos)
            minetest.place_schematic(j.pos, filepath, tostring(j.rotation), nil, false)
            if sch.on_built then sch.on_built(j.owner, j.pos, j.rotation) end
        end
    end
end)
