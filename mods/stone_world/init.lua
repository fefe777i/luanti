local MOD = minetest.get_current_modname()
local STORAGE = minetest.get_mod_storage()
local WORLD_NAME = "stone_world"
local OFFSET = 200000
local SPAWN = vector.new(0, 20, 0)
local ITEM = MOD .. ":teleporter"
local RETURN_KEY = "return_pos"
local WORLD_KEY = "world"

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
				data[area:index(x, y, z)] = stone
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

if minetest.create_subworld then
	minetest.create_subworld(WORLD_NAME)
end

local function move_player(player, world_name, pos)
	local name = player:get_player_name()
	if minetest.transfer_player then
		minetest.transfer_player(name, world_name, pos)
	else
		player:set_pos(pos)
	end
	STORAGE:set_string(WORLD_KEY .. ":" .. name, world_name)
end

local function enter_stone_world(player)
	if not player or not player:is_player() then
		return false
	end

	if not is_stone_world(player:get_pos()) then
		save_return_pos(player)
	end

	move_player(player, WORLD_NAME, SPAWN)

	minetest.after(0.2, function()
		if player:is_player() then
			set_stone_area(
				vector.new(OFFSET - 32, SPAWN.y - 32, SPAWN.z - 32),
				vector.new(OFFSET + 32, SPAWN.y + 32, SPAWN.z + 32)
			)
			player:set_pos(vector.new(OFFSET, SPAWN.y + 2, SPAWN.z))
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
	move_player(player, "overworld", pos)
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

	local name = player:get_player_name()
	local world = STORAGE:get_string(WORLD_KEY .. ":" .. name)
	if world == WORLD_NAME and minetest.get_player_subworld and minetest.transfer_player then
		minetest.after(0.2, function()
			if player:is_player() then
				minetest.transfer_player(name, WORLD_NAME, vector.new(0, 22, 0))
			end
		end)
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
