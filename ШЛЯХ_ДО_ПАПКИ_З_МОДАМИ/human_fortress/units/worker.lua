-- ============================================
-- ЮНІТ: УНІВЕРСАЛЬНИЙ РОБІТНИК (Worker)
-- ============================================

local worker_data = {
    name = "Робітник",
    health = 20,
    speed = 2,
    cost = {wood = 50, food = 25},
}

mobs:register_mob("human_fortress:worker", {
    type = "npc",
    passive = true,

    hp_min = 20,
    hp_max = 20,
    collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.3, 0.3},
    visual = "mesh",
    mesh = "worker_rig.glb",
    textures = {{"fom.png"}},
    visual_size = {x=1, y=1},

    animation = {
        speed_normal = 1,
        stand_start = 0,  stand_end = 1,
        walk_start = 2,   walk_end = 3,  walk_speed = 1.2,
        punch_start = 4,  punch_end = 5, punch_speed = 1.3,
        gather_start = 6, gather_end = 7, gather_speed = 1.3,
    },

    on_spawn = function(self)
        self.unit_data = {
            unit_id = "u_" .. tostring(math.random(1000000, 9999999)) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1, 10000)),
        }
        self.inventory = {wood = 0, stone = 0, food = 0}
        return true
    end,

    after_activate = function(self, staticdata, def, dtime)
        -- let units walk through each other instead of blocking one another
        self.object:set_properties({collide_with_objects = false})
    end,

    get_staticdata = function(self)
        local data = {
            unit_data = self.unit_data or {},
            inventory = self.inventory or {wood = 0, stone = 0, food = 0},
            order = self.order,
            goto_destination = self.goto_destination,
            last_gather_pos = self.last_gather_pos,
            has_greeted = self.has_greeted,
            unload_target = self.unload_target,
        }
        return minetest.serialize(data)
    end,

    on_activate = function(self, staticdata, dtime_s)
        if mobs.api and mobs.api.on_activate then
            mobs.api.on_activate(self, staticdata, dtime_s)
        end

        self.unit_data = {}
        self.inventory = {wood = 0, stone = 0, food = 0}
        self.order = nil
        self.goto_destination = nil
        self.last_gather_pos = nil
        self.has_greeted = false
        self.unload_target = nil

        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data and type(data) == "table" then
                self.unit_data = data.unit_data or {}
                self.inventory = data.inventory or {wood = 0, stone = 0, food = 0}
                self.order = data.order
                self.goto_destination = data.goto_destination
                self.last_gather_pos = data.last_gather_pos
                self.has_greeted = data.has_greeted
                self.unload_target = data.unload_target
            end
        end

        local uid = self.unit_data and self.unit_data.unit_id
        if uid and human_fortress.pending_commands and human_fortress.pending_commands[uid] then
            local pending = human_fortress.pending_commands[uid]
            self.unit_data.command = pending.command
            self.unit_data.target = pending.target
            human_fortress.pending_commands[uid] = nil
        end
    end,

    on_die = function(self, pos)
        local drop_pos = pos or self.object:get_pos()
        if not drop_pos then return end

        drop_pos.y = drop_pos.y + 0.5

        minetest.add_item(drop_pos, "human_fortress:versi 25")
        minetest.add_item(drop_pos, "human_fortress:ether_tree 25")

        if self.inventory then
            if (self.inventory.wood or 0) > 0 then
                minetest.add_item(drop_pos, "human_fortress:ether_tree " .. self.inventory.wood)
            end
            if (self.inventory.stone or 0) > 0 then
                minetest.add_item(drop_pos, "human_fortress:versiforn_source " .. self.inventory.stone)
            end
            if (self.inventory.food or 0) > 0 then
                minetest.add_item(drop_pos, "farm:wheat " .. self.inventory.food)
            end
        end

        local owner = self.unit_data and self.unit_data.owner or ""
        if owner ~= "" then
            minetest.chat_send_player(owner, "💀 Твій Формикс загинув у бою! Ресурси випали на землю.")
        end

        local uid = self.unit_data and self.unit_data.unit_id
        if uid and owner ~= "" and human_fortress.players and human_fortress.players[owner] then
            local list = human_fortress.players[owner].selected_ids or {}
            for i = #list, 1, -1 do
                if list[i] == uid then table.remove(list, i) end
            end
        end
        if uid and human_fortress.pending_commands then
            human_fortress.pending_commands[uid] = nil
        end
    end,

    do_custom = function(self, dtime)
        if self.build_lock then return end
        -- Привітання
        self.timer_greet = (self.timer_greet or 0) + dtime
        if self.timer_greet >= 2 then
            self.timer_greet = 0

            local greet_pos = self.object:get_pos()
            local players = minetest.get_objects_inside_radius(greet_pos, 3)

            local player_found = false
            for _, obj in ipairs(players) do
                if obj:is_player() then
                    player_found = true
                    break
                end
            end

            if player_found and not self.has_greeted then
                minetest.sound_play("hello_sound", {pos = greet_pos, max_hear_distance = 10})
                self.has_greeted = true
            elseif not player_found then
                self.has_greeted = false
            end
        end

        -- Захист
        if not self.unit_data then
            self.unit_data = {}
        end
        if not self.inventory then
            self.inventory = {wood = 0, stone = 0, food = 0}
        end

        local owner = self.unit_data.owner or ""

        -- інструмент у руці: кирка для каменю/ґрунту, сокира для ефірних дерев
        if human_fortress.hold_item then
            local tool
            if self.order == "gather" and self.goto_destination then
                local tn = minetest.get_node_or_nil(self.goto_destination)
                local td = tn and minetest.registered_nodes[tn.name]
                if td and td.groups and td.groups.ether_tree then
                    tool = "default:axe_steel"
                elseif tn and not tn.name:find("wheat") then
                    tool = "default:pick_steel"
                end
            end
            human_fortress.hold_item(self, tool)
        end

        local move_to = function(entity, target)
            local pos = entity.object:get_pos()
            if not pos or not target then return end

            local dist = vector.distance(pos, target)
            if dist < 1.5 then return end

            entity.move_timer = (entity.move_timer or 0) + 0.1
            if entity.move_timer < 0.3 then return end
            entity.move_timer = 0

            if not entity.path_nodes or #entity.path_nodes == 0 then
                entity.path_fail_count = (entity.path_fail_count or 0)

                local path = minetest.find_path(pos, target, 20, 1, 4, "A*_strict")
                          or minetest.find_path(pos, target, 20, 2, 4, "A*")

                if path and #path > 1 then
                    entity.path_nodes = path
                    entity.path_fail_count = 0
                    table.remove(entity.path_nodes, 1)
                else
                    entity.path_fail_count = entity.path_fail_count + 1
                    if entity.path_fail_count >= 3 then
                        entity.use_direct_move = true
                        entity.path_fail_count = 0
                    else
                        self:set_animation("stand")
                        return
                    end
                end
            end

            if entity.use_direct_move then
                local dir = vector.direction(pos, target)
                entity.object:set_velocity({
                    x = dir.x * 2.5 * (human_fortress.express_factor and human_fortress.express_factor(entity) or 1),
                    y = entity.object:get_velocity().y,
                    z = dir.z * 2.5 * (human_fortress.express_factor and human_fortress.express_factor(entity) or 1)
                })
                local yaw = math.atan2(-dir.x, dir.z)
                entity.object:set_yaw(yaw)
                self:set_animation("walk")

                if dist < 2.0 then
                    entity.use_direct_move = false
                end
                return
            end

            if entity.path_nodes and #entity.path_nodes > 0 then
                local next_step = entity.path_nodes[1]

                if vector.distance(pos, next_step) < 1.0 then
                    table.remove(entity.path_nodes, 1)
                    if #entity.path_nodes == 0 then return end
                    next_step = entity.path_nodes[1]
                end

                local dir = vector.direction(pos, next_step)
                entity.object:set_velocity({
                    x = dir.x * 2.5 * (human_fortress.express_factor and human_fortress.express_factor(entity) or 1),
                    y = entity.object:get_velocity().y,
                    z = dir.z * 2.5 * (human_fortress.express_factor and human_fortress.express_factor(entity) or 1)
                })
                self:set_animation("walk")
                local yaw = math.atan2(-dir.x, dir.z)
                entity.object:set_yaw(yaw)
            end
        end

        -- Слухач команд
        if self.unit_data.command then
            self.order = self.unit_data.command
            self.goto_destination = self.unit_data.target

            self.path_nodes = nil
            self.path_fail_count = 0
            self.use_direct_move = false
            self.move_timer = 0
            self.unload_target = nil

            self.unit_data.command = nil

            if owner ~= "" then
                minetest.chat_send_player(owner, "👷 Юніт отримав наказ: " .. (self.order or "очікування"))
            end
        end

        -- Рух (MOVE)
        if self.order == "move" and self.goto_destination then
            local pos = self.object:get_pos()
            if vector.distance(pos, self.goto_destination) > 1.5 then
                move_to(self, self.goto_destination)
            else
                self.order = "stand"
                self.path_nodes = nil
                self.object:set_velocity({x=0, y=0, z=0})
                self:set_animation("stand")
            end
            return
        end

        -- Авто-розвантаження
        local total_res = (self.inventory.wood or 0) + (self.inventory.stone or 0) + (self.inventory.food or 0)

        if (total_res >= 300 and not (self._full_until and os.time() < self._full_until)) or self.order == "unload" then
            local pos = self.object:get_pos()

            if not self.unload_target then
                local townhall = minetest.find_node_near(pos, 55, {"human_fortress:townhall"})
                local depot = human_fortress.nearest_depot and human_fortress.nearest_depot(owner, pos, 55)
                if depot and (not townhall or vector.distance(pos, depot) < vector.distance(pos, townhall)) then
                    townhall = depot
                end
                if townhall then
                    self.unload_target = townhall
                else
                    self.object:set_velocity({x=0, y=0, z=0})
                    return
                end
            end

            self.order = "unload"

            if vector.distance(pos, self.unload_target) > 3 then
                move_to(self, self.unload_target)
            else
                self.object:set_velocity({x=0, y=0, z=0})
                self:set_animation("stand")

                local leftover = {wood = 0, stone = 0, food = 0}
                if human_fortress.edos_data and human_fortress.edos_data[owner] then
                    -- ліміт складу: що не влізло - лишається в юніта
                    leftover = human_fortress.deposit_inventory(owner, self.inventory)
                    minetest.chat_send_player(owner, "💰 Робітник розвантажився у Ратуші!")
                end

                self.inventory = {wood = leftover.wood or 0, stone = leftover.stone or 0, food = leftover.food or 0}
                self.path_nodes = nil
                self.unload_target = nil

                if (self.inventory.wood + self.inventory.stone + self.inventory.food) > 0 then
                    minetest.chat_send_player(owner, "📦 Склад повний (ліміт " .. human_fortress.RES_CAP .. "). Робітник чекає з вантажем.")
                    self._full_until = os.time() + 30
                    self.order = "stand"
                    self.goto_destination = nil
                    return
                end

                -- повертаємось до ресурсу; якщо той уже вичерпаний - шукаємо новий поблизу
                local rp = self.last_gather_pos
                    and human_fortress.find_resource_near(self.last_gather_pos, 16, {"human_fortress:versiforn_source", "group:ether_tree"})
                if rp then
                    self.goto_destination = rp
                    self.last_gather_pos = rp
                    self.order = "gather"
                else
                    self.order = "stand"
                    self.goto_destination = nil
                    if self.last_gather_pos and owner ~= "" then
                        minetest.chat_send_player(owner, "⚠️ Ресурс біля місця роботи закінчився - віддай новий наказ")
                    end
                end
            end
            return
        end

        -- Збір ресурсів (GATHER)
        if self.order == "gather" and self.goto_destination then
            local pos = self.object:get_pos()
            local dist = vector.distance(pos, self.goto_destination)

            if dist > 2.5 then
                self.last_gather_pos = self.goto_destination
                move_to(self, self.goto_destination)
                return
            else
                self.object:set_velocity({x=0, y=0, z=0})
                -- збирання (пшениця, їжа) - нахил і підбирання, копання/рубання - удар
                local gn = minetest.get_node_or_nil(self.goto_destination)
                self.gather_anim = (gn and (gn.name:find("wheat") or gn.name:find("food"))) and "gather" or "punch"
                self:set_animation(self.gather_anim)
                self.gather_timer = (self.gather_timer or 0) + dtime

                if self.gather_timer >= 1.5 then
                    local node = minetest.get_node(self.goto_destination)
                    local node_def = minetest.registered_nodes[node.name]
                    local res_type = nil

                    if node_def and node_def.groups and node_def.groups.ether_tree then
                        res_type = "wood"
                    elseif node.name == "human_fortress:versiforn_source" or node.name:find("stone") then
                        res_type = "stone"
                    elseif node.name:find("wheat") or node.name:find("food") then
                        res_type = "food"
                    elseif node_def and node_def.diggable ~= false and node_def.groups
                            and (node_def.groups.crumbly or node_def.groups.cracky or node_def.groups.snappy)
                            and not node.name:find("^human_fortress:") then
                        res_type = "dig"   -- звичайне копання: ґрунт, пісок, гравій, сніг
                    end

                    if res_type == "dig" then
                        minetest.remove_node(self.goto_destination)
                        minetest.sound_play("default_dig_crumbly", {pos = self.goto_destination, gain = 0.5, max_hear_distance = 16}, true)
                        self.order = "stand"
                        self.goto_destination = nil
                        self.gather_timer = 0
                        return
                    end

                    if res_type then
                        local meta = minetest.get_meta(self.goto_destination)

                        if node_def and node_def.groups and node_def.groups.ether_tree then
                            local rem = meta:get_int("remaining")
                            if rem == 0 then rem = node_def._max_ether or 50 end

                            if rem <= 1 then
                                minetest.remove_node(self.goto_destination)
                                self.order = "stand"
                                self.goto_destination = nil
                                minetest.chat_send_player(owner, "🌳 Ефірне дерево повністю вирубано!")
                            else
                                meta:set_int("remaining", rem - 1)
                            end

                            self.inventory[res_type] = (self.inventory[res_type] or 0) + 1
                            minetest.chat_send_player(owner, "📦 Робітник викачує Ефір (+1). Залишилось у дереві: " .. (rem - 1))

                        elseif node.name == "human_fortress:versiforn_source" then
                            self.inventory[res_type] = (self.inventory[res_type] or 0) + 35
                            minetest.set_node(self.goto_destination, {name = "human_fortress:versiform_depleted_stone"})
                            minetest.chat_send_player(owner, "💎 Знайдено Версиформ! Робітник викопав одразу +35 каменю.")

                            local next_ore = minetest.find_node_near(self.goto_destination, 12, {"human_fortress:versiforn_source"})
                            if next_ore then
                                self.goto_destination = next_ore
                                self.path_nodes = nil
                            else
                                self.order = "stand"
                                self.goto_destination = nil
                            end

                        else
                            minetest.remove_node(self.goto_destination)
                            self.inventory[res_type] = (self.inventory[res_type] or 0) + 1
                            self.order = "stand"
                            self.goto_destination = nil
                        end
                    else
                        self.order = "stand"
                        self.goto_destination = nil
                    end
                    self.gather_timer = 0
                end
            end
            return
        end

        -- Бойова логіка
        self.attack_timer = (self.attack_timer or 0) + dtime
        if self.attack_timer >= 2.0 and self.order ~= "move" and self.order ~= "gather" then
            self.attack_timer = 0
            local my_pos = self.object:get_pos()

            for _, obj in ipairs(minetest.get_objects_inside_radius(my_pos, 12)) do
                local lua_ent = obj:get_luaentity()

                if lua_ent and lua_ent.unit_data and lua_ent.unit_data.owner ~= owner and lua_ent.health and lua_ent.health > 0 then
                    if self.attack then
                        self:attack(obj)
                        break
                    else
                        self.order = "attack_target"
                        self.enemy_object = obj
                        break
                    end
                end
            end
        end

        if self.order == "attack_target" and self.enemy_object then
            local target_obj = self.enemy_object
            if target_obj:get_pos() then
                local t_pos = target_obj:get_pos()
                local dist = vector.distance(self.object:get_pos(), t_pos)

                if dist > 2 then
                    move_to(self, t_pos)
                else
                    self.object:set_velocity({x=0, y=0, z=0})
                    self:set_animation("punch")
                    local target_ent = target_obj:get_luaentity()
                    if target_ent and target_ent.health then
                        target_ent.health = target_ent.health - 2
                        if target_ent.health <= 0 then
                            self.order = "stand"
                            self.enemy_object = nil
                            self:set_animation("stand")
                        end
                    end
                end
            else
                self.order = "stand"
                self.enemy_object = nil
                self:set_animation("stand")
            end
        end
    end,
})

if not human_fortress.units_list then human_fortress.units_list = {} end
human_fortress.units_list.worker = {
    name = worker_data.name,
    health = worker_data.health,
    speed = worker_data.speed,
    cost = worker_data.cost,
    profession = "basic",
    entity = "human_fortress:worker",
}

function human_fortress.spawn_worker(pos, player_name)
    local ent = minetest.add_entity(pos, "human_fortress:worker")
    if not ent then return nil end
    local luaent = ent:get_luaentity()
    if not luaent then ent:remove() return nil end

    luaent.unit_data = luaent.unit_data or {}
    luaent.unit_data.owner = player_name

    return ent
end

-- ============================================
-- КОМАНДА ДЛЯ СПАВНУ ФОРМИКА (РОБІТНИКА)
-- ============================================

minetest.register_chatcommand("spawn_formix", {
    description = "Заспавнити твого формика (робітника) перед собою",
    privs = {server = true}, -- За потреби можеш змінити привілеї або прибрати, якщо для всіх гравців
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Гравця не знайдено!"
        end

        local pos = player:get_pos()
        local dir = player:get_look_dir()
        -- Спавнимо юніта на 2 блоки попереду гравця
        local spawn_pos = vector.add(pos, vector.multiply(dir, 2))
        spawn_pos.y = math.floor(spawn_pos.y + 0.5)

        -- Викликаємо твою функцію спавну
        local ent = human_fortress.spawn_worker(spawn_pos, name)
        if ent then
            return true, "✅ Формик успішно заспавнений біля тебе!"
        else
            return false, "❌ Помилка при спавні формика."
        end
    end,
})