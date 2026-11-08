-- ============================================
-- world.lua - Карта світу, прокачка та відновлення руди
-- ============================================

local ROCKY     = "default:permafrost_with_stones"
local STONE     = "default:stone"
local ORE       = "human_fortress:versiforn_source"
local DEPLETED  = "human_fortress:versiform_depleted_stone"
local FORK_NODE = "human_fortress:vilka_active"

local DEFAULT_TREES = {
    {name = "human_fortress:ether_tree_small",      w = 5},
    {name = "human_fortress:ether_tree_small_plus", w = 3},
    {name = "human_fortress:ether_tree_medium",     w = 2},
}

local WORLD_BG    = "hf_world_bg.png"
local MAP_TEXTURE = "hf_world_map.png"
local MAP_X, MAP_Y, MAP_SIZE = 4.0, 0.5, 8.0
local ICON_SIZE = 1.1

local REGEN_BASE = 150
local REGEN_STEP = 200

local STEP_SIZE = 40

-- Поля локації:
-- icon, map, desc, grass
-- tree_chance - шанс дерева на новій траві (0.003 = рідко)
-- trees       - свій список дерев
-- ore_blobs   - скільки скупчень руди на кожні 40 шарів зони
-- ore_size    - максимальний радіус скупчення
-- fork, main_fork, near_fork, unlock_by
-- min, max    - зона (суцільний прямокутник); tp - точка телепорту
local LOCATIONS = {
    {
        id = "plains", name = "Рівнини", unlock_by = "plains_upgrade",
        icon = "hf_loc_plains.png", map = {x = 0.22, y = 0.40},
        desc = "Тихі рівнини навколо вашої вилки. Тут починається кожна фортеця: " ..
               "м'які трави, чиста вода і багато місця для першого поселення.",
        grass = "default:dirt_with_grass",
        tree_chance = 0.002, ore_blobs = 25, ore_size = 2,
        fork = {x = -5, y = 42, z = -176},
        main_fork = true,
        near_fork = true,
        min = {x = -106, y = 36, z = -282},
        max = {x = 110,  y = 52, z = -118},
        tp  = {x = -5,   y = 44, z = -176},
    },
    {
        id = "glaciere", name = "Єдрений ледник", unlock_by = "glacier",
        icon = "hf_loc_icec.png", map = {x = 0.47, y = 0.41},
        desc = "Холодні рівнини навколо одні ледники. " ..
               "Холодні трави, холодна вода і багато холодного місця для другого поселення.",
        grass = "default:dirt_with_snow",
        tree_chance = 0.002, ore_blobs = 20, ore_size = 2,
        fork = {x = -4, y = 31, z = -6},
        min = {x = -129, y = 24, z = -118},
        max = {x = 42,    y = 53, z = 106},
        tp  = {x = -6,   y = 31, z = -6},
        feature = "glacier_cache",
    },
    {
        id = "epilit_canyon", name = "Каньйон епілітів", unlock_by = "epilit_canyon",
        icon = "hf_loc_epilit_canyon.png", map = {x = 0.45, y = 0.59},
        desc = "Глибокий каньйон, вистелений гравієм і уламками епілітів. " ..
               "Зона розвідки: тут трапляються бойові трофеї та рідкісна руда.",
        grass = "default:gravel",
        ore_blobs = 20, ore_size = 2,
        fork = {x = 53, y = 39, z = -52},
        tp  = {x = 52, y = 40, z = -52},
        min = {x = 0,   y = 0,  z = -125},
        max = {x = 144, y = 60, z = 59},
        feature = "epilit_cache",
        pads = {"stone", "eidos"},
    },
    {
        id = "twilight_graveyard", name = "Сутінковий могильник",
        icon = "hf_loc_twilight_graveyard.png", map = {x = 0.60, y = 0.35},
        desc = "Похмурі землі, де навіть удень панують сутінки. " ..
               "Старі могили ховають містичні та підземні ресурси.",
        grass = "default:dirt_with_coniferous_litter",
        ore_blobs = 20, ore_size = 2,
        fork = {x = -114, y = 40, z = 45},
        min = {x = -137, y = 28, z = -17},
        max = {x = -3,  y = 41, z = 108},
        tp  = {x = -114, y = 40, z = 42},
        feature = "grave_cache",
        pads = {"ether"},
    },
    {
        id = "monumental_valley", name = "Монументальна могила", unlock_by = "monumental_valley",
        icon = "hf_loc_monumental_valley.png", map = {x = 0.66, y = 0.15},
        desc = "Велетенські кам'яні сходи над могильником. Її породи міцніші за будь-які інші, " ..
               "а покладів каменю тут вистачить на цілі фортеці. Сходи можна покращувати.",
        grass = "default:dirt_with_dry_grass",
        ore_blobs = 20, ore_size = 2,
        fork = {x = -208, y = 57, z = 75},
        tp  = {x = -209, y = 58, z = 75},
        min = {x = -270, y = 10, z = 15},
        max = {x = -127, y = 100, z = 129},
        feature = "monument_cache",
        pads = {"stone"},
    },
    {
        id = "palace_garden", name = "Палацовий сад", unlock_by = "palace_garden",
        icon = "hf_loc_palace_garden.png", map = {x = 0.875, y = 0.275},
        desc = "Занедбаний сад давньої знаті з лабіринтом. Тут ростуть рідкісні породи дерев " ..
               "і рослини, яких більше ніде не знайти.",
        grass = "default:dirt_with_grass",
        tree_chance = 0.004, ore_blobs = 20, ore_size = 2,
        fork = {x = -134, y = 36, z = 204},
        tp  = {x = -135, y = 37, z = 204},
        min = {x = -165, y = 0, z = 106},
        max = {x = -94, y = 90, z = 279},
        feature = "labyrinth_cache",
        pads = {"food", "ether"},
    },
    {
        id = "floating_rocks", name = "Літаючі острови", unlock_by = "floating_rocks",
        icon = "hf_loc_floating_rocks.png", map = {x = 0.875, y = 0.12},
        desc = "Засніжені острови, що ніби висять над землею. " ..
               "Найвища й найдальша зона з найціннішими матеріалами.",
        grass = "default:dirt_with_snow",
        ore_blobs = 25, ore_size = 2,
        fork = {x = -213, y = 40, z = 195},
        tp  = {x = -214, y = 41, z = 195},
        min = {x = -280, y = 20, z = 129},
        max = {x = -166, y = 100, z = 279},
        feature = "sky_cache",
        pads = {"eidos"},
    },
    {
        id = "flat_mountains", name = "Плоскі гори", unlock_by = "flat_mountains",
        icon = "hf_loc_flat_mountains.png", map = {x = 0.63, y = 0.82},
        desc = "Широкі плоскі гори. Після прокачки їхні вершини вкриває червоний камінь, " ..
               "а в надрах ховаються багаті поклади руди.",
        grass = "default:desert_stone",
        ore_blobs = 30, ore_size = 3,
        fork = {x = 196, y = 26, z = 59},
        tp  = {x = 195, y = 27, z = 59},
        min = {x = 100, y = 0, z = -40},
        max = {x = 290, y = 100, z = 121},
        feature = "mountain_cache",
        pads = {"stone", "eidos"},
    },
    {
        id = "despair_gorge", name = "Ущелина відчаю", unlock_by = "gorge_despair",
        icon = "hf_loc_despair_gorge.png", map = {x = 0.86, y = 0.80},
        desc = "Моторошна ущелина зі скляною підлогою над безоднею. Стати на скло — " ..
               "ризик, але руди тут найбагатші у світі.",
        ore_blobs = 40, ore_size = 3,
        fork = {x = 187, y = 53, z = 181},
        tp  = {x = 186, y = 54, z = 181},
        min = {x = 95, y = 0, z = 122},
        max = {x = 260, y = 90, z = 269},
        feature = "despair_cache",
        pads = {"eidos", "stone"},
    },
}

human_fortress.LOCATIONS = LOCATIONS

-- Карта володіння колонками (zone_map.lua): яка локація володіє колонкою (x,z)
do
    local ok, ZMAP = pcall(dofile, minetest.get_modpath("human_fortress") .. "/zone_map.lua")
    if ok and type(ZMAP) == "table" then
        local cache = {}
        local function row(z)
            local idx = z - ZMAP.oz + 1
            local r = cache[idx]
            if r == nil then
                r = false
                local str = ZMAP.rows[idx]
                if str and str ~= "" then
                    r = {}
                    for a, b, v in str:gmatch("(%d+):(%d+):(%d+)") do
                        r[#r + 1] = {tonumber(a) + ZMAP.ox, tonumber(b) + ZMAP.ox, ZMAP.zones[tonumber(v) + 1]}
                    end
                end
                cache[idx] = r
            end
            return r
        end
        function human_fortress.zone_owner(x, z)
            local r = row(z)
            if not r then return nil end
            for i = 1, #r do
                if x >= r[i][1] and x <= r[i][2] then return r[i][3] end
            end
            return nil
        end
    end
end

-- id локації (регіону), у якій лежить позиція
function human_fortress.location_at(pos)
    local owner = human_fortress.zone_owner and human_fortress.zone_owner(pos.x, pos.z)
    if owner then return owner end
    for _, l in ipairs(LOCATIONS) do
        if l.min and l.max and pos.x >= l.min.x and pos.x <= l.max.x
                and pos.z >= l.min.z and pos.z <= l.max.z then
            return l.id
        end
    end
    return "other"
end

-- ============================================
-- ДОПОМІЖНІ ФУНКЦІЇ
-- ============================================

local function dim_name(player_name)
    return player_name .. "_world"
end

local function find_loc(id)
    for _, l in ipairs(LOCATIONS) do
        if l.id == id then return l end
    end
end

local function is_loc_unlocked(data, loc)
    local key = loc.unlock_by or loc.id
    return data.upgrades and data.upgrades[key] == true
end

local function cid(name)
    if name and minetest.registered_nodes[name] then
        return minetest.get_content_id(name)
    end
    return nil
end

local function regen_cost(count)
    return REGEN_BASE + REGEN_STEP * (count or 0)
end

local function esc(s)
    return minetest.formspec_escape(s)
end

local function is_solid(pos)
    local node = minetest.get_node_or_nil(pos)
    if not node then return nil end
    local def = minetest.registered_nodes[node.name]
    if not def then return true end
    return def.walkable ~= false
end

local function find_spot_near(pos, min_r, max_r)
    for r = min_r, max_r do
        for dx = -r, r do
            for dz = -r, r do
                if math.max(math.abs(dx), math.abs(dz)) == r then
                    for dy = -1, 3 do
                        local feet  = {x = pos.x + dx, y = pos.y + dy, z = pos.z + dz}
                        local head  = {x = feet.x, y = feet.y + 1, z = feet.z}
                        local below = {x = feet.x, y = feet.y - 1, z = feet.z}
                        if is_solid(feet) == false and is_solid(head) == false
                                and is_solid(below) == true then
                            return {x = feet.x, y = feet.y, z = feet.z}
                        end
                    end
                end
            end
        end
    end
    return {x = pos.x + 2, y = pos.y + 1, z = pos.z}
end

human_fortress.find_spot_near = find_spot_near

local function build_tree_list(loc)
    local list, total = {}, 0
    for _, t in ipairs(loc.trees or DEFAULT_TREES) do
        local id = cid(t.name)
        if id then
            total = total + t.w
            table.insert(list, {id = id, w = t.w})
        end
    end
    return list, total
end

local function pick_tree(list, total)
    local r = math.random() * total
    for _, t in ipairs(list) do
        r = r - t.w
        if r <= 0 then return t.id end
    end
    return list[#list].id
end

-- ============================================
-- ВИЛКА ЛОКАЦІЇ
-- ============================================

local function is_bad_ground(pos)
    local n = minetest.get_node_or_nil(pos)
    if not n then return true end
    local def = minetest.registered_nodes[n.name]
    if not def or def.walkable == false then return true end
    if n.name:find("ether_tree") then return true end
    local g = def.groups or {}
    return (g.tree or g.leaves or g.leafdecay) and true or false
end

local function find_surface(cx, cz, ymin, ymax)
    for y = ymax, ymin + 1, -1 do
        local here  = {x = cx, y = y,     z = cz}
        local up    = {x = cx, y = y + 1, z = cz}
        local below = {x = cx, y = y - 1, z = cz}
        local n, nu = minetest.get_node_or_nil(here), minetest.get_node_or_nil(up)
        if n and nu and n.name == "air" and nu.name == "air"
                and is_solid(below) == true and not is_bad_ground(below) then
            return here
        end
    end
end

local function ensure_fork(player_name, loc)
    local data = get_player_data(player_name)
    data.loc_forks = data.loc_forks or {}

    local pos = loc.fork
    if not pos and loc.min and loc.max then
        local cx = math.floor((loc.min.x + loc.max.x) / 2)
        local cz = math.floor((loc.min.z + loc.max.z) / 2)
        minetest.load_area({x = cx - 10, y = loc.min.y, z = cz - 10},
                           {x = cx + 10, y = loc.max.y, z = cz + 10})
        for r = 0, 10 do
            for dx = -r, r do
                for dz = -r, r do
                    if not pos and math.max(math.abs(dx), math.abs(dz)) == r then
                        pos = find_surface(cx + dx, cz + dz, loc.min.y, loc.max.y)
                    end
                end
            end
            if pos then break end
        end
    end
    pos = pos or loc.tp
    if not pos then return nil end

    pos = {x = pos.x, y = pos.y, z = pos.z}
    minetest.load_area(pos)
    if minetest.get_node(pos).name ~= FORK_NODE then
        minetest.set_node(pos, {name = FORK_NODE})
    end
    minetest.get_meta(pos):set_string("owner", player_name)
    if human_fortress.register_vilka then human_fortress.register_vilka(pos, player_name) end

    data.loc_forks[loc.id] = pos
    if loc.main_fork then data.fork_pos = pos end
    save_fortress_data()
    return pos
end

function human_fortress.place_loc_fork(player_name, loc_id)
    local loc = find_loc(loc_id)
    if not loc then return false, "нема такої локації" end
    local pos = ensure_fork(player_name, loc)
    if not pos then return false, "не вдалося знайти місце для вилки" end
    return true, pos
end

function human_fortress.place_fork(player_name, pos)
    minetest.set_node(pos, {name = FORK_NODE})
    minetest.get_meta(pos):set_string("owner", player_name)
    if human_fortress.register_vilka then human_fortress.register_vilka(pos, player_name) end

    local data = get_player_data(player_name)
    data.fork_pos = {x = pos.x, y = pos.y, z = pos.z}
    save_fortress_data()
end

-- ============================================
-- ГЕНЕРАЦІЯ ЛОКАЦІЇ
-- mode = "upgrade": трава на всій зоні, дерева, скупчення руди, вилка
-- mode = "regen":   тільки виснажений камінь -> руда
-- ============================================

local busy = {}

local function run_location(player_name, loc, mode, on_done)
    if not loc.min or not loc.max then return false, "для локації не задано координати" end

    local key = player_name .. ":" .. loc.id
    if busy[key] then return false, "локація вже обробляється, зачекай" end

    local c_air   = cid("air")
    local c_stone = cid(STONE)
    local c_ore   = cid(ORE)
    local c_rocky, c_new, c_depleted
    local tree_list, tree_total = {}, 0

    if mode == "regen" then
        c_depleted = cid(DEPLETED)
        if not c_depleted then return false, "блок '" .. DEPLETED .. "' не існує" end
        if not c_ore then return false, "блок руди '" .. ORE .. "' не існує" end
    else
        c_rocky = cid(ROCKY)
        if not c_rocky then return false, "блок '" .. ROCKY .. "' не існує" end
        if loc.grass then
            c_new = cid(loc.grass)
            if not c_new then return false, "блок '" .. tostring(loc.grass) .. "' не існує" end
        end
        tree_list, tree_total = build_tree_list(loc)
        if not c_ore then
            minetest.chat_send_player(player_name,
                "⚠️ Блок руди '" .. ORE .. "' не існує, руда не згенерується")
        end
    end

    local data = get_player_data(player_name)
    data.world_levels = data.world_levels or {}

    busy[key] = true
    local z, z_end = loc.min.z, loc.max.z
    local ore_count, grass_count = 0, 0

    local step
    local function safe_step()
        local ok, err = pcall(step)
        if not ok then
            busy[key] = nil
            minetest.log("error", "[human_fortress] world: " .. tostring(err))
            minetest.chat_send_player(player_name, "❌ Помилка генерації: " .. tostring(err))
            if on_done then on_done(nil, tostring(err)) end
        end
    end

    step = function()
        local z2 = math.min(z + STEP_SIZE - 1, z_end)
        local p1 = {x = loc.min.x, y = loc.min.y, z = z}
        local p2 = {x = loc.max.x, y = loc.max.y, z = z2}

        local vm = VoxelManip()
        local emin, emax = vm:read_from_map(p1, p2)
        local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
        local d = vm:get_data()

        local zo = human_fortress.zone_owner
        local function mine(x, z)
            if not zo then return true end
            return zo(x, z) == loc.id
        end

        for vz = p1.z, p2.z do
            for vx = p1.x, p2.x do
                if mode == "regen" or mine(vx, vz) then
                for vy = p1.y, p2.y do
                    local vi = area:index(vx, vy, vz)
                    local id = d[vi]

                    if mode == "regen" then
                        if id == c_depleted then
                            d[vi] = c_ore
                            ore_count = ore_count + 1
                        end
                    elseif c_new and id == c_rocky then
                        d[vi] = c_new
                        grass_count = grass_count + 1
                        if tree_total > 0 and (loc.tree_chance or 0) > 0
                                and vy < p2.y
                                and d[vi + area.ystride] == c_air
                                and math.random() < loc.tree_chance then
                            d[vi + area.ystride] = pick_tree(tree_list, tree_total)
                        end
                    end
                end
                end
            end
        end

        -- Скупчення руди (всередині породи, неглибоко під поверхнею)
        if mode == "upgrade" and c_ore and (loc.ore_blobs or 0) > 0 then
            local max_r = loc.ore_size or 2
            local function ground(n)
                return n == c_stone or n == c_rocky or (c_new and n == c_new)
            end
            for _ = 1, loc.ore_blobs do
                for _try = 1, 80 do
                    local bx = math.random(p1.x, p2.x)
                    local bz = math.random(p1.z, p2.z)
                    if mine(bx, bz) then
                        local top
                        for y = p2.y, p1.y, -1 do
                            local n = d[area:index(bx, y, bz)]
                            if ground(n) then top = y break end
                        end
                        local by = top and (top - math.random(1, 5))
                        if by and by >= p1.y then
                            local r = math.random(1, max_r)
                            for dx = -r, r do
                                for dy = -r, r do
                                    for dz = -r, r do
                                        if dx * dx + dy * dy + dz * dz <= r * r + 1 then
                                            local x, y, zz = bx + dx, by + dy, bz + dz
                                            if area:contains(x, y, zz) and mine(x, zz) then
                                                local i = area:index(x, y, zz)
                                                if ground(d[i]) then
                                                    d[i] = c_ore
                                                    ore_count = ore_count + 1
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            break
                        end
                    end
                end
            end
        end

        vm:set_data(d)
        vm:calc_lighting()
        vm:write_to_map(true)

        z = z2 + 1
        if z <= z_end then
            minetest.after(0.1, safe_step)
            return
        end

        -- кінець: виправити світло на всій зоні
        minetest.load_area(loc.min, loc.max)
        minetest.fix_light(loc.min, loc.max)

        if mode == "upgrade" then
            data.world_levels[loc.id] = true
            save_fortress_data()
            local fork_pos = ensure_fork(player_name, loc)
            if human_fortress.generate_location_extras then
                pcall(human_fortress.generate_location_extras, player_name, loc, fork_pos)
            end
            minetest.chat_send_player(player_name,
                "✅ Локацію «" .. loc.name .. "» прокачано! Трави: " .. grass_count ..
                ", руди: " .. ore_count ..
                (fork_pos and ". 🍴 Вилку поставлено." or ". ⚠️ Вилку поставити не вдалося."))
        end

        busy[key] = nil
        if on_done then on_done(ore_count) end
    end

    -- спочатку догенерувати зону, щоб мапген не перезаписав наші зміни
    minetest.chat_send_player(player_name, "⏳ Підготовка зони...")
    minetest.emerge_area(loc.min, loc.max, function(_, _, remaining)
        if remaining == 0 then safe_step() end
    end)
    return true
end

function human_fortress.upgrade_location(player_name, loc_id)
    local loc = find_loc(loc_id)
    if not loc then return false, "нема такої локації" end

    local data = get_player_data(player_name)
    data.world_levels = data.world_levels or {}
    if data.world_levels[loc_id] then return false, "вже прокачано" end

    local ok, err = run_location(player_name, loc, "upgrade")
    if not ok then
        minetest.chat_send_player(player_name, "❌ " .. tostring(err))
    end
    return ok, err
end

function human_fortress.regenerate_location(player_name, loc_id)
    local loc = find_loc(loc_id)
    if not loc then return false, "нема такої локації" end

    local data = get_player_data(player_name)
    data.world_levels = data.world_levels or {}
    data.world_regens = data.world_regens or {}

    if not is_loc_unlocked(data, loc) then return false, "локація ще заблокована" end
    if not data.world_levels[loc_id] then return false, "спочатку прокачай локацію" end

    local count = data.world_regens[loc_id] or 0
    local cost = regen_cost(count)
    local edos = human_fortress.edos_data and human_fortress.edos_data[player_name]
    if not edos or (edos.score or 0) < cost then
        return false, "недостатньо ейдосів, треба " .. cost
    end

    edos.score = edos.score - cost
    data.world_regens[loc_id] = count + 1
    save_fortress_data()

    local function refund()
        local e = human_fortress.edos_data and human_fortress.edos_data[player_name]
        if e then e.score = (e.score or 0) + cost end
        data.world_regens[loc_id] = count
        save_fortress_data()
    end

    local ok, err = run_location(player_name, loc, "regen", function(found, e)
        if not found then
            refund()
        elseif found == 0 then
            refund()
            minetest.chat_send_player(player_name,
                "ℹ️ У «" .. loc.name .. "» нема виснаженої руди, ейдоси повернуто.")
        else
            minetest.chat_send_player(player_name,
                "🔄 «" .. loc.name .. "»: відновлено руди: " .. found)
        end
        local p = minetest.get_player_by_name(player_name)
        if p and human_fortress.update_gui then human_fortress.update_gui(p) end
    end)

    if not ok then
        refund()
        return false, err
    end
    return true
end

-- ============================================
-- ТЕЛЕПОРТ
-- ============================================

local function travel(player, target)
    local name = player:get_player_name()
    minetest.close_formspec(name, "")
    local ok, err = minetest.travel_to_dimension(player, dim_name(name), target)
    if not ok then
        minetest.chat_send_player(name, "❌ " .. tostring(err))
    end
end

local function teleport_to_loc(player, loc)
    local name = player:get_player_name()
    local data = get_player_data(name)

    if not is_loc_unlocked(data, loc) then
        minetest.chat_send_player(name, "🔒 Спочатку розблокуй локацію в прокачці")
        return
    end

    local target
    if loc.near_fork and data.fork_pos then
        target = find_spot_near(data.fork_pos, 2, 3)
    elseif loc.tp then
        target = loc.tp
    elseif data.loc_forks and data.loc_forks[loc.id] then
        target = find_spot_near(data.loc_forks[loc.id], 2, 3)
    end

    if not target then
        minetest.chat_send_player(name, "❌ Для цієї локації не задано телепорт")
        return
    end
    travel(player, target)
end

-- ============================================
-- МЕНЮ: КАРТА
-- ============================================

function show_world_menu(player_name)
    local data = get_player_data(player_name)

    local fs = "formspec_version[6]" ..
        "size[16,9]" ..
        "no_prepend[]" ..
        "bgcolor[#0A0A1A;true]"

    if WORLD_BG then
        fs = fs .. "image[0,0;16,9;" .. esc(WORLD_BG) .. "]"
    end

    fs = fs .. string.format("image[%.2f,%.2f;%.2f,%.2f;%s]",
        MAP_X, MAP_Y, MAP_SIZE, MAP_SIZE, esc(MAP_TEXTURE)) ..
        "style_type[image_button;border=false]"

    for _, loc in ipairs(LOCATIONS) do
        local x = MAP_X + loc.map.x * MAP_SIZE - ICON_SIZE / 2
        local y = MAP_Y + loc.map.y * MAP_SIZE - ICON_SIZE / 2

        local tex = loc.icon
        if not is_loc_unlocked(data, loc) then
            tex = tex .. "^[multiply:#555555"
        end

        fs = fs .. string.format("image_button[%.2f,%.2f;%.2f,%.2f;%s;loc_%s;]",
            x, y, ICON_SIZE, ICON_SIZE, esc(tex), loc.id)
        fs = fs .. string.format("tooltip[loc_%s;%s]", loc.id, esc(loc.name))
    end

    fs = fs ..
        "style_type[button;bgimg=my_button.png;bgimg_middle=4,4;border=false]" ..
        "button[0.5,0.5;3,0.8;back;🔙 НАЗАД]" ..
        "button[0.5,1.6;3,0.8;tp_fork;🍴 ДО ВИЛКИ]"

    minetest.show_formspec(player_name, "human_fortress:world", fs)
end

-- ============================================
-- МЕНЮ: ВІКНО ЛОКАЦІЇ
-- ============================================

local function show_location_menu(player_name, loc)
    local data = get_player_data(player_name)
    data.world_levels = data.world_levels or {}
    data.world_regens = data.world_regens or {}

    local unlocked = is_loc_unlocked(data, loc)
    local upgraded = data.world_levels[loc.id]
    local count = data.world_regens[loc.id] or 0
    local cost = regen_cost(count)
    local edos = human_fortress.edos_data and human_fortress.edos_data[player_name]
    local score = edos and edos.score or 0

    local status
    if not unlocked then
        status = "🔒 Заблоковано"
    elseif upgraded then
        status = "✅ Прокачано"
    else
        status = "⏳ Чекає на прокачку"
    end

    local fs = "formspec_version[6]" ..
        "size[11,8]" ..
        "bgcolor[#0A0A1A;true]" ..
        "box[0,0;11,1;#2D2D44]" ..
        "label[0.5,0.5;" .. esc(loc.name) .. "]" ..
        "box[0.4,1.4;2.2,2.2;#1E1E2E]" ..
        "image[0.5,1.5;2,2;" .. esc(loc.icon) .. "]" ..
        "label[3,1.7;" .. esc(status) .. "]" ..
        "textarea[3,2.1;7.5,2;;;" .. esc(loc.desc) .. "]" ..
        "label[0.5,4.3;💰 Твої ейдоси: " .. score .. "]"

    if unlocked then
        fs = fs .. "button[0.5,5;4.9,1;tp_" .. loc.id .. ";📍 Телепорт]"
    else
        fs = fs .. "label[0.5,5.4;Розблокуй цю локацію в дереві прокачки]"
    end

    if unlocked and upgraded then
        fs = fs .. "button[5.6,5;4.9,1;regen_" .. loc.id .. ";" ..
            esc("🔄 Перегенерувати (" .. cost .. ")") .. "]"
        fs = fs .. "label[5.6,6.3;Виснажена руда знову стане рудою]"
        fs = fs .. "label[5.6,6.7;Перегенерацій: " .. count .. ". Наступна: " .. cost .. "]"
    end

    fs = fs .. "button[0.5,6.9;3,0.8;back_map;🔙 До карти]"

    minetest.show_formspec(player_name, "human_fortress:world_loc", fs)
end

-- ============================================
-- ОБРОБНИК ФОРМ
-- ============================================

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()

    if formname == "human_fortress:world" then
        if fields.quit then return true end

        if fields.back then
            if show_vilka_menu then show_vilka_menu(name) end
            return true
        end

        if fields.tp_fork then
            local data = get_player_data(name)
            if not data.fork_pos then
                minetest.chat_send_player(name, "❌ Вилку ще не поставлено")
                return true
            end
            travel(player, find_spot_near(data.fork_pos, 2, 3))
            return true
        end

        for field in pairs(fields) do
            local id = field:match("^loc_(.+)$")
            if id then
                local loc = find_loc(id)
                if loc then show_location_menu(name, loc) end
                return true
            end
        end
        return true
    end

    if formname == "human_fortress:world_loc" then
        if fields.quit then return true end

        if fields.back_map then
            show_world_menu(name)
            return true
        end

        for field in pairs(fields) do
            local id = field:match("^tp_(.+)$")
            if id then
                local loc = find_loc(id)
                if loc then teleport_to_loc(player, loc) end
                return true
            end

            id = field:match("^regen_(.+)$")
            if id then
                local loc = find_loc(id)
                if loc then
                    local ok, err = human_fortress.regenerate_location(name, id)
                    if ok then
                        minetest.chat_send_player(name,
                            "🔄 Відновлення руди в «" .. loc.name .. "» запущено...")
                    else
                        minetest.chat_send_player(name, "❌ " .. tostring(err))
                    end
                    show_location_menu(name, loc)
                end
                return true
            end
        end
        return true
    end
end)

-- ============================================
-- КОМАНДИ ДЛЯ СТВОРЕННЯ СВІТУ
-- /pos1 <id>, /pos2 <id>, /savedpos <id>, /vilkapos [id], /tppos [id], /locs
-- ============================================

local OVR_FILE = minetest.get_worldpath() .. "/hf_locations.json"
local overrides = {}
local selection = {}

do
    local f = io.open(OVR_FILE, "r")
    if f then
        overrides = minetest.parse_json(f:read("*a")) or {}
        f:close()
    end
    for id, o in pairs(overrides) do
        local loc = find_loc(id)
        if loc then
            for _, k in ipairs({"min", "max", "fork", "tp"}) do
                if o[k] then loc[k] = o[k] end
            end
        end
    end
end

local function save_overrides()
    local f = io.open(OVR_FILE, "w")
    if f then
        f:write(minetest.write_json(overrides, true))
        f:close()
    end
end

local function fmt(p)
    return string.format("{x = %d, y = %d, z = %d}", p.x, p.y, p.z)
end

local function player_pos(name)
    local p = minetest.get_player_by_name(name)
    if not p then return nil end
    return vector.round(p:get_pos())
end

local function resolve_loc(name, param)
    param = param:trim()
    if param ~= "" then
        local loc = find_loc(param)
        if not loc then return nil, "❌ Нема локації '" .. param .. "'. Список: /locs" end
        return loc
    end
    local p = player_pos(name)
    if p then
        for _, l in ipairs(LOCATIONS) do
            if l.min and l.max
                    and p.x >= l.min.x and p.x <= l.max.x
                    and p.y >= l.min.y and p.y <= l.max.y
                    and p.z >= l.min.z and p.z <= l.max.z then
                return l
            end
        end
    end
    return nil, "❌ Вкажи id локації, напр. /vilkapos plains"
end

local function set_sel(name, param, key)
    local id = param:trim()
    local loc = find_loc(id)
    if not loc then return false, "❌ Нема локації '" .. id .. "'. Список: /locs" end
    local p = player_pos(name)
    if not p then return false, "❌ Гравця не знайдено" end
    selection[name] = selection[name] or {}
    selection[name][id] = selection[name][id] or {}
    selection[name][id][key] = p
    return true, "📍 " .. key .. " [" .. id .. "] = " .. fmt(p)
end

minetest.register_chatcommand("pos1", {
    params = "<id локації>",
    description = "Перший кут зони локації",
    privs = {server = true},
    func = function(name, param) return set_sel(name, param, "p1") end,
})

minetest.register_chatcommand("pos2", {
    params = "<id локації>",
    description = "Другий кут зони локації",
    privs = {server = true},
    func = function(name, param) return set_sel(name, param, "p2") end,
})

minetest.register_chatcommand("savedpos", {
    params = "<id локації>",
    description = "Зберегти зону локації (pos1 + pos2)",
    privs = {server = true},
    func = function(name, param)
        local id = param:trim()
        local loc = find_loc(id)
        if not loc then return false, "❌ Нема локації '" .. id .. "'. Список: /locs" end
        local s = selection[name] and selection[name][id]
        if not s or not s.p1 or not s.p2 then
            return false, "❌ Спочатку /pos1 " .. id .. " і /pos2 " .. id
        end

        local mn = {x = math.min(s.p1.x, s.p2.x), y = math.min(s.p1.y, s.p2.y), z = math.min(s.p1.z, s.p2.z)}
        local mx = {x = math.max(s.p1.x, s.p2.x), y = math.max(s.p1.y, s.p2.y), z = math.max(s.p1.z, s.p2.z)}

        loc.min, loc.max = mn, mx
        overrides[id] = overrides[id] or {}
        overrides[id].min, overrides[id].max = mn, mx
        save_overrides()
        selection[name][id] = nil

        local snippet = "min = " .. fmt(mn) .. ",\nmax = " .. fmt(mx) .. ","
        minetest.log("action", "[human_fortress] " .. id .. ":\n" .. snippet)
        return true, "✅ Збережено «" .. id .. "» (діє одразу):\n" .. snippet
    end,
})

minetest.register_chatcommand("vilkapos", {
    params = "[id локації]",
    description = "Зберегти позицію вилки локації (де стоїш)",
    privs = {server = true},
    func = function(name, param)
        local loc, err = resolve_loc(name, param)
        if not loc then return false, err end
        local p = player_pos(name)
        if not p then return false, "❌ Гравця не знайдено" end

        loc.fork = p
        overrides[loc.id] = overrides[loc.id] or {}
        overrides[loc.id].fork = p
        save_overrides()
        return true, "🍴 Вилка [" .. loc.id .. "]:\nfork = " .. fmt(p) .. ","
    end,
})

minetest.register_chatcommand("tppos", {
    params = "[id локації]",
    description = "Зберегти точку телепорту локації (де стоїш)",
    privs = {server = true},
    func = function(name, param)
        local loc, err = resolve_loc(name, param)
        if not loc then return false, err end
        local p = player_pos(name)
        if not p then return false, "❌ Гравця не знайдено" end

        loc.tp = p
        overrides[loc.id] = overrides[loc.id] or {}
        overrides[loc.id].tp = p
        save_overrides()
        return true, "📍 Телепорт [" .. loc.id .. "]:\ntp = " .. fmt(p) .. ","
    end,
})

minetest.register_chatcommand("locs", {
    description = "Список локацій і що для них задано",
    privs = {server = true},
    func = function()
        local out = {}
        for _, l in ipairs(LOCATIONS) do
            table.insert(out, string.format("%s: зона %s, вилка %s, tp %s",
                l.id, l.min and l.max and "✅" or "❌",
                l.fork and "✅" or "❌", l.tp and "✅" or "❌"))
        end
        return true, table.concat(out, "\n")
    end,
})

minetest.register_chatcommand("pos", {
    description = "Показати координати для таблиці локацій",
    func = function(name)
        local p = player_pos(name)
        return true, fmt(p)
    end,
})

minetest.register_chatcommand("node", {
    description = "Назва блоку під ногами",
    func = function(name)
        local p = player_pos(name)
        return true, "Під ногами: " .. minetest.get_node({x = p.x, y = p.y - 1, z = p.z}).name
    end,
})

print("[Human Fortress] World system loaded")