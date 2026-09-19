local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function transfer(name, world)
	if world == "" then
		return false, "Вкажи назву світу"
	end

	local player = core.get_player_by_name(name)
	if not player then
		return false, "Гравця не знайдено"
	end

	if not core.transfer_player then
		return false, "Цей рушій не має core.transfer_player()"
	end

	local ok = core.transfer_player(name, world, player:get_pos())
	if not ok then
		return false, "Не вдалося перейти у світ: " .. world
	end

	return true, "Перехід у світ " .. world .. " виконано"
end

core.register_chatcommand("world", {
	params = "<назва>",
	description = "Перейти у фізичний світ",
	privs = {server = true},
	func = function(name, param)
		return transfer(name, trim(param))
	end,
})

core.register_chatcommand("worlds", {
	description = "Показати доступні фізичні світи",
	privs = {server = true},
	func = function()
		if not core.list_subworlds then
			return false, "Цей рушій не має core.list_subworlds()"
		end

		local worlds = core.list_subworlds()
		return true, "Світи: " .. table.concat(worlds, ", ")
	end,
})

core.register_chatcommand("myworld", {
	description = "Показати поточний фізичний світ",
	func = function(name)
		if not core.get_player_subworld then
			return false, "Цей рушій не має core.get_player_subworld()"
		end

		return true, "Твій світ: " .. core.get_player_subworld(name)
	end,
})
