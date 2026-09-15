local MOD = minetest.get_current_modname()
local STORAGE = minetest.get_mod_storage()
local OFFSET = 1000000
local SPAWN = vector.new(OFFSET, 20, 0)
local ITEM = MOD .. ":teleporter"
local RETURN_KEY = "return_pos"
local IN_WORLD_KEY = "in_stone_world"

local function is_stone_world(pos)
	return pos.x >= OFFSET - 100000 and pos.x <= OFFSET + 100000
end

local function save_return_pos(player)
	STORAGE:set_string(RETURN_KEY .. ":" .. player:get_player_name(), minetest.pos_to_string(player:get_pos()))
end

local function load_return_pos(player)
	local value = STORAGE:get_string(RETURN_KEY .. ":" .. player:get_player_name())
	if value == "" then
		return nil
	end
	return minetest.string_to_pos(value)
end

local function set_stone_area(minp, maxp)
	if maxp.x < OFFSET - 100000 or minp.x > OFFSET + 100000 then
		return
	end

	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local stone = minetest.get_content_id("default:stone")

	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				local i = area:index(x, y, z)
				data[i] = stone
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map()
	vm:update_map()
end

minetest.register_on_generated(function(minp, maxp)
	if maxp.x < OFFSET - 100000 or minp.x > OFFSET + 100000 then
		return
	end
	set_stone_area(minp, maxp)
end)

local function enter_stone_world(player)
	if not player or not player:is_player() then
		return false
	end

	local name = player:get_player_name()
	if not is_stone_world(player:get_pos()) then
		save_return_pos(player)
	end

	STORAGE:set_string(IN_WORLD_KEY .. ":" .. name, "1")
	player:set_pos(vector.add(SPAWN, vector.new(0, 2, 0)))
	minetest.after(0.2, function()
		if player:is_player() then
			set_stone_area(
				vector.new(SPAWN.x - 32, SPAWN.y - 32, SPAWN.z - 32),
				vector.new(SPAWN.x + 32, SPAWN.y + 32, SPAWN.z + 32)
			)
			player:set_pos(vector.add(SPAWN, vector.new(0, 2, 0)))
		end
	end)
	return true
end

local function leave_stone_world(player)
	if not player or not player:is_player() then
		return false
	end

	local name = player:get_player_name()
	local pos = load_return_pos(player) or vector.new(0, 20, 0)
	STORAGE:set_string(IN_WORLD_KEY .. ":" .. name, "0")
	player:set_pos(pos)
	return true
end

minetest.register_tool(ITEM, {
	description = "Кам'яний світ",
	inventory_image = "default_stone.png",
	stack_max = 1,
	on_use = function(itemstack, user)
		enter_stone_world(user)
		return itemstack
	end,
	on_place = function(itemstack, user)
		enter_stone_world(user)
		return itemstack
	end,
})

minetest.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	if not inv:contains_item("main", ITEM) then
		inv:add_item("main", ITEM)
	end
end)

minetest.register_chatcommand("stoneworld", {
	params = "",
	description = "Телепортуватися у Кам'яний світ",
	privs = {},
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Гравця не знайдено"
		end
		enter_stone_world(player)
		return true, "Ти у Кам'яному світі"
	end,
})

minetest.register_chatcommand("overworld", {
	params = "",
	description = "Повернутися з Кам'яного світу",
	privs = {},
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Гравця не знайдено"
		end
		leave_stone_world(player)
		return true, "Ти повернувся у звичайний світ"
	end,
})
