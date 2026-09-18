local WORLD_1 = "world1"
local WORLD_2 = "world2"

local function switch_world(name)
	if not minetest.switch_world then
		return false
	end
	return minetest.switch_world(name)
end

minetest.register_chatcommand("world", {
	params = "<name>",
	description = "Перемкнутися в інший світ",
	privs = {},

	func = function(_, param)
		param = param:gsub("^%s+", ""):gsub("%s+$", "")
		if param == "" then
			return false, "Вкажи назву світу: /world world1"
		end

		if not switch_world(param) then
			return false, "Не вдалося перемкнути світ"
		end

		return true, "Перепідключення до світу " .. param .. "..."
	end,
})

minetest.register_chatcommand("stoneworld", {
	params = "",
	description = "Перейти у world2",
	privs = {},

	func = function()
		if not switch_world(WORLD_2) then
			return false, "Не вдалося перейти у world2"
		end
		return true, "Перепідключення до world2..."
	end,
})

minetest.register_chatcommand("overworld", {
	params = "",
	description = "Повернутися у world1",
	privs = {},

	func = function()
		if not switch_world(WORLD_1) then
			return false, "Не вдалося перейти у world1"
		end
		return true, "Перепідключення до world1..."
	end,
})
