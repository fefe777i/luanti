local WORLD_1 = "world1"
local WORLD_2 = "world2"

local function switch_player(playername, world)
	return minetest.transfer_player(playername, world, {x = 0, y = 0, z = 0})
end

minetest.register_chatcommand("world", {
	params = "<name>",
	description = "Перейти в інший фізичний світ",
	privs = {},
	func = function(name, param)
		param = param:gsub("^%s+", ""):gsub("%s+$", "")
		if param == "" then
			return false, "Вкажи назву світу: /world world2"
		end
		if not switch_player(name, param) then
			return false, "Світ не знайдений або не вдалося перемкнутися"
		end
		return true, "Перепідключення до " .. param .. "..."
	end,
})

minetest.register_chatcommand("stoneworld", {
	params = "",
	description = "Перейти у world2",
	privs = {},
	func = function(name)
		if not switch_player(name, WORLD_2) then
			return false, "world2 не завантажений"
		end
		return true, "Перепідключення до world2..."
	end,
})

minetest.register_chatcommand("overworld", {
	params = "",
	description = "Повернутися у world1",
	privs = {},
	func = function(name)
		if not switch_player(name, WORLD_1) then
			return false, "world1 не завантажений"
		end
		return true, "Перепідключення до world1..."
	end,
})
