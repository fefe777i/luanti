local WORLD_NAME = "stone_world"
local SPAWN = vector.new(0, 10, 0)
local ITEM = "stone_world:teleporter"

local function fill_stone(pos, radius, min_y, max_y)
	local vm = VoxelManip()
	local p1 = vector.new(pos.x - radius, min_y, pos.z - radius)
	local p2 = vector.new(pos.x + radius, max_y, pos.z + radius)
	local emin, emax = vm:read_from_map(p1, p2)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local stone = minetest.get_content_id("default:stone")
	for z = p1.z, p2.z do
		for y = p1.y, p2.y do
			for x = p1.x, p2.x do
				local i = area:index(x, y, z)
				data[i] = stone
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map()
	vm:update_map()
end

if minetest.create_subworld then
	minetest.create_subworld(WORLD_NAME)
end

local function teleport_to_stone_world(player)
	if not player or not player:is_player() then
		return
	end
	local name = player:get_player_name()
	if minetest.transfer_player then
		minetest.transfer_player(name, WORLD_NAME, SPAWN)
	else
		player:set_pos(SPAWN)
	end
	minetest.after(0.2, function()
		if player and player:is_player() then
			fill_stone(SPAWN, 32, -32, 32)
			player:set_pos(vector.add(SPAWN, vector.new(0, 2, 0)))
		end
	end)
end

minetest.register_tool(ITEM, {
	description = "Телепорт у Кам'яний світ",
	inventory_image = "default_stone.png",
	stack_max = 1,
	on_use = function(itemstack, user)
		teleport_to_stone_world(user)
		return itemstack
	end,
	on_place = function(itemstack, user)
		teleport_to_stone_world(user)
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
		if player then
			teleport_to_stone_world(player)
			return true, "Телепортація у Кам'яний світ"
		end
		return false, "Гравця не знайдено"
	end,
})
