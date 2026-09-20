-- Кам'яний світ: справжній окремий світ (власна карта), а не зсув координат.
-- Працює через систему світів рушія (core.create_dimension / core.travel_to_dimension).

local MOD = core.get_current_modname()
local DIM = "stone_world"
local ITEM = MOD .. ":teleporter"

if not core.create_dimension then
	core.log("warning", "[" .. MOD .. "] Рушій без підтримки світів, мод вимкнено")
	return
end

-- Порожній світ, який заповнюємо каменем у on_generated
-- (якщо світ уже існує, create_dimension просто поверне false)
core.create_dimension(DIM, {mg_name = "singlenode"})

local function stone_content_id()
	local name = core.registered_aliases["mapgen_stone"]
	if not name or not core.registered_nodes[name] then
		name = "default:stone"
		if not core.registered_nodes[name] then
			name = "basenodes:stone"
		end
	end
	if core.registered_nodes[name] then
		return core.get_content_id(name)
	end
end

local stone_id

-- Камінь до висоти y = 0, вище - відкрите небо
core.register_on_generated(function(minp, maxp)
	if core.get_current_dimension() ~= DIM or minp.y > 0 then
		return
	end
	stone_id = stone_id or stone_content_id()
	if not stone_id then
		return
	end

	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local top = math.min(maxp.y, 0)
	for z = minp.z, maxp.z do
		for y = minp.y, top do
			local vi = area:index(minp.x, y, z)
			for _ = minp.x, maxp.x do
				data[vi] = stone_id
				vi = vi + 1
			end
		end
	end
	vm:set_data(data)
	vm:calc_lighting()
	vm:write_to_map()
end)

local function toggle_world(player)
	if not player or not player:is_player() then
		return
	end
	local target = core.get_current_dimension() == DIM and "overworld" or DIM
	local ok, err = core.travel_to_dimension(player, target)
	if not ok then
		core.chat_send_player(player:get_player_name(), tostring(err))
	end
end

core.register_tool(ITEM, {
	description = "Кам'яний світ (телепорт)",
	inventory_image = "default_stone.png",
	stack_max = 1,
	on_use = function(itemstack, user)
		toggle_world(user)
		return itemstack
	end,
	on_place = function(itemstack, user)
		toggle_world(user)
		return itemstack
	end,
})

core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	if not inv:contains_item("main", ITEM) then
		inv:add_item("main", ITEM)
	end
end)

core.register_chatcommand("stoneworld", {
	description = "Телепортуватися у Кам'яний світ",
	func = function(name)
		local ok, err = core.travel_to_dimension(name, DIM)
		if not ok then
			return false, tostring(err)
		end
		return true, "Переходимо у Кам'яний світ..."
	end,
})

core.register_chatcommand("overworld", {
	description = "Повернутися зі Кам'яного світу у звичайний",
	func = function(name)
		local ok, err = core.travel_to_dimension(name, "overworld")
		if not ok then
			return false, tostring(err)
		end
		return true, "Повертаємось у звичайний світ..."
	end,
})
