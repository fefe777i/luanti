-- ============================================
-- ВИПАДКОВІ ПРЕДМЕТИ-РЕСУРСИ У СВІТІ ГРАВЦЯ
-- ============================================
-- Ведмедик, голова формикса, кристал ефіру, мішок рису, камінь версиформу...
-- Ресурси дають ТІЛЬКИ коли по предмету натиснути (тап / клік / ЛКМ / ПКМ).

human_fortress = human_fortress or {}

local MAX_PROPS      = tonumber(minetest.settings:get("human_fortress_props_max")) or 8
local SPAWN_INTERVAL = tonumber(minetest.settings:get("human_fortress_props_interval")) or 45
local SPAWN_RADIUS   = 80
local LIFETIME       = 600
local REACH          = 2.5   -- пошук предмета біля точки тапу

-- res: ключі ресурсів (wood = ефір, stone = версиформ, food = рис)
local VARIANTS = {
    {id = "bear",   mesh = "hf_prop_bear.obj",        tex = "hf_prop_bear.png",
     name = "Плюшевий ведмедик", size = 1.4, weight = 2,
     res = {{"food", 15, 30}, {"wood", 10, 25}}},
    {id = "head",   mesh = "hf_prop_formic_head.obj", tex = "hf_prop_formic_head.png",
     name = "Голова формикса",   size = 1.4, weight = 2,
     res = {{"stone", 20, 40}}},
    {id = "crystal", mesh = "hf_prop_crystal.obj",    tex = "hf_prop_crystal.png",
     name = "Кристал ефіру",     size = 1.3, weight = 3,
     res = {{"wood", 25, 50}}},
    {id = "sack",   mesh = "hf_prop_sack.obj",        tex = "hf_prop_sack.png",
     name = "Мішок рису",        size = 1.3, weight = 3,
     res = {{"food", 25, 50}}},
    {id = "rock",   mesh = "hf_prop_rock.obj",        tex = "hf_prop_rock.png",
     name = "Камінь версиформу", size = 1.3, weight = 3,
     res = {{"stone", 25, 50}}},
}
local BY_ID = {}
local TOTAL_W = 0
for _, v in ipairs(VARIANTS) do BY_ID[v.id] = v; TOTAL_W = TOTAL_W + v.weight end

local RES_LABEL = {wood = "ефіру", stone = "версиформу", food = "рису"}

local function pick_variant()
    local r = math.random() * TOTAL_W
    for _, v in ipairs(VARIANTS) do
        r = r - v.weight
        if r <= 0 then return v end
    end
    return VARIANTS[1]
end

minetest.register_entity("human_fortress:res_prop", {
    initial_properties = {
        visual = "mesh",
        mesh = "hf_prop_bear.obj",
        textures = {"hf_prop_bear.png"},
        visual_size = {x = 1.4, y = 1.4},
        physical = false,
        pointable = true,
        static_save = false,
        collisionbox = {-0.4, 0, -0.4, 0.4, 1.0, 0.4},
        selectionbox = {-0.6, 0, -0.6, 0.6, 1.6, 0.6, rotate = false},
        backface_culling = true,
        glow = 4,
        show_on_minimap = false,
    },
    is_res_prop = true,

    set_variant = function(self, id)
        local v = BY_ID[id] or VARIANTS[1]
        self.variant = v.id
        self.object:set_properties({
            mesh = v.mesh, textures = {v.tex},
            visual_size = {x = v.size, y = v.size},
            nametag = "✦ " .. v.name,
            nametag_color = "#ffe27a",
        })
    end,

    on_activate = function(self, staticdata)
        self.age = 0
        self.spin = (math.random() < 0.5 and -1 or 1) * (0.4 + math.random() * 0.4)
        self.object:set_yaw(math.random() * math.pi * 2)
        self:set_variant(staticdata ~= "" and staticdata or "bear")
    end,

    on_step = function(self, dtime)
        self.age = self.age + dtime
        if self.age > LIFETIME then
            self.object:remove()
            return
        end
        self.object:set_yaw(self.object:get_yaw() + self.spin * dtime)
    end,

    -- прямий клік / удар
    on_punch = function(self, puncher)
        if puncher and puncher:is_player() then
            human_fortress.collect_prop(self.object, puncher)
        end
        return true
    end,
    on_rightclick = function(self, clicker)
        if clicker and clicker:is_player() then
            human_fortress.collect_prop(self.object, clicker)
        end
    end,
})

-- ---------- збір ----------
function human_fortress.collect_prop(obj, player)
    local ent = obj and obj:get_luaentity()
    if not ent or not ent.is_res_prop or ent.collected then return false end
    local name = player:get_player_name()
    local v = BY_ID[ent.variant] or VARIANTS[1]
    local data = human_fortress.edos_data and human_fortress.edos_data[name]
    if not data then return false end

    ent.collected = true
    local parts = {}
    for _, r in ipairs(v.res) do
        local amount = math.random(r[2], r[3])
        local got = human_fortress.add_resource(name, r[1], amount)
        if type(got) == "number" and got > 0 then
            parts[#parts + 1] = "+" .. got .. " " .. RES_LABEL[r[1]]
        end
    end
    if #parts == 0 then
        ent.collected = false
        minetest.chat_send_player(name, "Склад повний — місця для ресурсів немає.")
        return false
    end
    if human_fortress.update_gui then human_fortress.update_gui(player) end

    local pos = obj:get_pos()
    minetest.add_particlespawner({
        amount = 25, time = 0.3,
        minpos = {x = pos.x - 0.4, y = pos.y + 0.2, z = pos.z - 0.4},
        maxpos = {x = pos.x + 0.4, y = pos.y + 1.2, z = pos.z + 0.4},
        minvel = {x = -2, y = 2, z = -2}, maxvel = {x = 2, y = 5, z = 2},
        minacc = {x = 0, y = -9, z = 0}, maxacc = {x = 0, y = -9, z = 0},
        minexptime = 0.6, maxexptime = 1.2, minsize = 1, maxsize = 2.5,
        texture = "default_mese_crystal.png^[colorize:#ffe27a:200",
        glow = 12,
    })
    minetest.sound_play("default_dug_node", {pos = pos, gain = 0.6}, true)
    minetest.chat_send_player(name, v.name .. ": " .. table.concat(parts, ", "))
    obj:remove()
    return true
end

-- тап по землі/будівлі/мінімапі-промаху: шукаємо предмет біля точки
function human_fortress.try_collect_prop(user, pointed_thing)
    if not user or not pointed_thing then return false end
    if pointed_thing.type == "object" and pointed_thing.ref then
        local ent = pointed_thing.ref:get_luaentity()
        if ent and ent.is_res_prop then
            return human_fortress.collect_prop(pointed_thing.ref, user)
        end
        return false
    end
    if pointed_thing.type ~= "node" then return false end
    local p = pointed_thing.intersection_point or pointed_thing.above
    if not p then return false end
    local best, bd
    for _, o in ipairs(minetest.get_objects_inside_radius(p, REACH)) do
        local e = o:get_luaentity()
        if e and e.is_res_prop and not e.collected then
            local op = o:get_pos()
            local d = vector.distance(p, {x = op.x, y = op.y + 0.5, z = op.z})
            if not bd or d < bd then best, bd = o, d end
        end
    end
    if best then return human_fortress.collect_prop(best, user) end
    return false
end

-- командні інструменти: спершу перевіряємо предмет, і лише потім звичайна дія
minetest.register_on_mods_loaded(function()
    for iname, def in pairs(minetest.registered_tools) do
        if iname:find("^human_fortress:cmd_") and def.on_use
                and iname ~= "human_fortress:cmd_exit" then
            local orig = def.on_use
            minetest.override_item(iname, {
                on_use = function(itemstack, user, pointed_thing)
                    if human_fortress.try_collect_prop(user, pointed_thing) then
                        return itemstack
                    end
                    return orig(itemstack, user, pointed_thing)
                end,
            })
        end
    end
end)

-- ---------- спавн ----------
local function random_spot(center)
    for _ = 1, 8 do
        local a = math.random() * math.pi * 2
        local r = 10 + math.random() * (SPAWN_RADIUS - 10)
        local x = math.floor(center.x + math.cos(a) * r)
        local z = math.floor(center.z + math.sin(a) * r)
        local y0 = math.floor(center.y)
        -- спускаємось/піднімаємось уздовж колонки по завантажених нодах
        for dy = 20, -30, -1 do
            local p = {x = x, y = y0 + dy, z = z}
            local n = minetest.get_node_or_nil(p)
            if not n then break end
            local def = minetest.registered_nodes[n.name]
            if def and def.walkable and def.liquidtype == "none" then
                local up1 = minetest.get_node_or_nil({x = x, y = p.y + 1, z = z})
                local up2 = minetest.get_node_or_nil({x = x, y = p.y + 2, z = z})
                local d1 = up1 and minetest.registered_nodes[up1.name]
                local d2 = up2 and minetest.registered_nodes[up2.name]
                if d1 and d2 and not d1.walkable and not d2.walkable
                        and d1.liquidtype == "none" then
                    return {x = x + 0.5, y = p.y + 0.5, z = z + 0.5}
                end
                break
            end
        end
    end
end

local function count_props_near(center)
    local n = 0
    for _, o in ipairs(minetest.get_objects_inside_radius(center, SPAWN_RADIUS + 20)) do
        local e = o:get_luaentity()
        if e and e.is_res_prop then n = n + 1 end
    end
    return n
end

local timer = 0
minetest.register_globalstep(function(dtime)
    if human_fortress.is_overworld then return end   -- лише у світах гравців
    timer = timer + dtime
    if timer < SPAWN_INTERVAL then return end
    timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local center = player:get_pos()
        if get_player_data then
            local d = get_player_data(name)
            if d and d.fork_pos then center = d.fork_pos end
        end
        if count_props_near(center) < MAX_PROPS then
            local spot = random_spot(center)
            if spot then
                local v = pick_variant()
                minetest.add_entity(spot, "human_fortress:res_prop", v.id)
            end
        end
    end
end)

-- адмін-команда для перевірки
minetest.register_chatcommand("spawnprop", {
    description = "Створити предмет-ресурс біля себе [bear|head|crystal|sack|rock]",
    privs = {server = true},
    func = function(name, param)
        local p = minetest.get_player_by_name(name)
        if not p then return end
        local pos = vector.add(p:get_pos(), vector.multiply(p:get_look_dir(), 3))
        local id = BY_ID[param] and param or pick_variant().id
        minetest.add_entity(pos, "human_fortress:res_prop", id)
        return true, "Створено: " .. id
    end,
})
