-- ============================================
-- СПАВН БІЛЯ ВИЛКИ + РЕГЕНЕРАЦІЯ HP
-- ============================================
-- * вхід у свій світ -> гравець з'являється біля вилки;
-- * смерть -> відродження біля вилки;
-- * HP потроху відновлюється сам.

human_fortress = human_fortress or {}

local function spot_near_fork(name)
    if human_fortress.is_overworld then return nil end   -- станція: свій спавн
    if not get_player_data then return nil end
    local data = get_player_data(name)
    if not data or not data.fork_pos then return nil end
    minetest.load_area(data.fork_pos)
    local spot = human_fortress.find_spot_near and human_fortress.find_spot_near(data.fork_pos, 2, 3)
    return spot or { x = data.fork_pos.x + 2, y = data.fork_pos.y + 1, z = data.fork_pos.z }
end
human_fortress.spot_near_fork = spot_near_fork

-- вхід (у тому числі перехід зі станції у свій світ)
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    minetest.after(1.5, function()
        local p = minetest.get_player_by_name(name)
        if not p then return end
        local spot = spot_near_fork(name)
        if spot then p:set_pos(spot) end
    end)
end)

-- смерть: виходимо з режиму командування, щоб не зависнути з камерою зверху
minetest.register_on_dieplayer(function(player)
    local name = player:get_player_name()
    if human_fortress.rts and human_fortress.rts.is_active(name) and toggle_command_mode then
        toggle_command_mode(player)
    end
end)

-- відродження біля вилки
minetest.register_on_respawnplayer(function(player)
    local spot = spot_near_fork(player:get_player_name())
    if spot then
        player:set_pos(spot)
        return true   -- стандартний спавн не потрібен
    end
end)

-- повільна регенерація: +1 HP (півсерця) кожні REGEN_INTERVAL секунд
local REGEN_INTERVAL = tonumber(minetest.settings:get("human_fortress_regen_interval")) or 4
local regen_timer = 0
minetest.register_globalstep(function(dtime)
    regen_timer = regen_timer + dtime
    if regen_timer < REGEN_INTERVAL then return end
    regen_timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local hp = player:get_hp()
        local max = player:get_properties().hp_max or 20
        if hp > 0 and hp < max then
            player:set_hp(hp + 1)
        end
    end
end)
