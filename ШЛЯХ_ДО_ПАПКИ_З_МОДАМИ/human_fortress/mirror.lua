-- ============================================
-- ВІДЗЕРКАЛЕННЯ СУТНОСТЕЙ
-- ============================================
-- human_fortress.set_mirror(obj, true/false)  - віддзеркалити модель по осі X.
-- У визначенні сутності (юніта) достатньо вказати  mirror = true,  і вона
-- віддзеркалюється при кожній активації.
-- Рушій масштабує модель за visual_size, від'ємний X дзеркалить її;
-- backface_culling вимикається, щоб віддзеркалена модель не вивернулась навиворіт.

human_fortress = human_fortress or {}

function human_fortress.set_mirror(obj, on)
    if not obj or not obj:get_pos() then return false end
    local props = obj:get_properties()
    if not props then return false end
    local vs = props.visual_size or {x = 1, y = 1, z = 1}
    local ent = obj:get_luaentity()
    if on then
        if ent and ent._mirror_culling == nil then ent._mirror_culling = props.backface_culling end
        obj:set_properties({
            visual_size = {x = -math.abs(vs.x), y = vs.y, z = vs.z},
            backface_culling = false,
        })
    else
        local culling = true
        if ent and ent._mirror_culling ~= nil then culling = ent._mirror_culling end
        obj:set_properties({
            visual_size = {x = math.abs(vs.x), y = vs.y, z = vs.z},
            backface_culling = culling,
        })
    end
    if ent then ent.mirror = on and true or false end
    return true
end

-- сутності з полем mirror = true віддзеркалюються при активації
minetest.register_on_mods_loaded(function()
    for name, def in pairs(minetest.registered_entities) do
        if name:sub(1, 15) == "human_fortress:" and def.mirror then
            local orig = def.on_activate
            def.on_activate = function(self, staticdata, dtime)
                if orig then orig(self, staticdata, dtime) end
                human_fortress.set_mirror(self.object, true)
            end
        end
    end
end)

-- /mirror - віддзеркалити/повернути юніта, на якого дивишся (до 15 вузлів)
minetest.register_chatcommand("mirror", {
    description = "Віддзеркалити юніта, на якого дивишся",
    privs = {server = true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Гравця не знайдено" end
        local eye = vector.add(player:get_pos(), {x = 0, y = player:get_properties().eye_height or 1.6, z = 0})
        local ray = minetest.raycast(eye, vector.add(eye, vector.multiply(player:get_look_dir(), 15)), true, false)
        for pt in ray do
            if pt.type == "object" and pt.ref ~= player then
                local ent = pt.ref:get_luaentity()
                if ent then
                    local on = not ent.mirror
                    human_fortress.set_mirror(pt.ref, on)
                    return true, on and "Віддзеркалено" or "Повернуто"
                end
            end
        end
        return false, "Дивись на юніта"
    end,
})
