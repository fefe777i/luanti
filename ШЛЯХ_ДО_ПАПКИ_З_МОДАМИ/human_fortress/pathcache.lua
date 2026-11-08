-- ============================================
-- КЕШ ПОШУКУ ШЛЯХУ (мінус навантаження на сервер)
-- ============================================
-- Обгортка над minetest.find_path (A* на C++): однакові запити багатьох юнітів
-- (той самий старт/ціль) рахуються один раз, невдалі пошуки (найдорожчі) запам'ятовуються
-- на кілька секунд, а за один тік сервера витрачається не більше BUDGET секунд.
-- Якщо ліміт вичерпано - повертається nil, юніти просто повторять пошук наступного разу.

if human_fortress and human_fortress.pathcache_installed then return end
human_fortress = human_fortress or {}
human_fortress.pathcache_installed = true

local orig_find_path = minetest.find_path
local TTL_OK, TTL_FAIL = 6, 5      -- секунд
local BUDGET = 0.008               -- секунд на один тік сервера
local cache = {}
local used = 0
local now = 0
local stat = {hits = 0, calls = 0, skipped = 0}
human_fortress.pathcache_stats = stat

local function r(v) return math.floor(v + 0.5) end

local function copy_path(path)
    local out = {}
    for i, p in ipairs(path) do out[i] = {x = p.x, y = p.y, z = p.z} end
    return out
end

function minetest.find_path(pos1, pos2, searchdistance, max_jump, max_drop, algo)
    local key = table.concat({
        r(pos1.x), r(pos1.y), r(pos1.z), r(pos2.x), r(pos2.y), r(pos2.z),
        searchdistance, max_jump, max_drop, algo or "A*_noprefetch",
    }, ",")
    local c = cache[key]
    if c and now - c.t < (c.path and TTL_OK or TTL_FAIL) then
        stat.hits = stat.hits + 1
        return c.path and copy_path(c.path) or nil
    end
    if used > BUDGET then
        stat.skipped = stat.skipped + 1
        return nil
    end
    local t0 = os.clock()
    local path = orig_find_path(pos1, pos2, searchdistance, max_jump, max_drop, algo)
    used = used + (os.clock() - t0)
    stat.calls = stat.calls + 1
    cache[key] = {t = now, path = path or false}
    return path
end

local clean = 0
minetest.register_globalstep(function(dtime)
    used = 0
    now = now + dtime
    clean = clean + dtime
    if clean > 30 then
        clean = 0
        for k, c in pairs(cache) do
            if now - c.t > TTL_OK then cache[k] = nil end
        end
    end
end)

minetest.register_chatcommand("pathstats", {
    description = "Статистика кешу пошуку шляху",
    privs = {server = true},
    func = function()
        return true, ("запитів у C++: %d, з кешу: %d, пропущено через ліміт: %d"):format(
            stat.calls, stat.hits, stat.skipped)
    end,
})
