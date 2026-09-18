local MOD = minetest.get_current_modname()
local STORAGE = minetest.get_mod_storage()
local WORLD_NAME = "stone_world"
local SPAWN = vector.new(0, 20, 0)
local ITEM = MOD .. ":teleporter"
local WORLD_KEY = "world"

local function move_player(player, world_name, pos)
	local name = player:get_player_name()

	if not minetest.transfer_player then
		return false
	end

	if not minetest.transfer_player(name, world_name, pos) then
		return false
	end

	STORAGE:set_string(WORLD_KEY .. ":" .. name, world_name)
	return true
end

local function enter_stone_world(player)
	if not player or not player:is_player() then
		return false
	end

	if not minetest.create_subworld or not minetest.create_subworld(WORLD_NAME) then
		return false
	end

	return move_player(player, WORLD_NAME, SPAWN)
end

local function leave_stone_world(player)
	if not player or not player:is_player() then
		return false
	end

	return move_player(player, "overworld", SPAWN)
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

	if world == WORLD_NAME and minetest.transfer_player then
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

		if not enter_stone_world(player) then
			return false, "Не вдалося перейти у Кам'яний світ"
		end

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

		if not leave_stone_world(player) then
			return false, "Не вдалося повернутися у звичайний світ"
		end

		return true, "Ти повернувся у звичайний світ"
	end,
})
