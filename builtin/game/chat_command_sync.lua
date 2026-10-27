-- Sends the list of chat commands a player may use to the client, so that the
-- chat can suggest commands after the player types "/".

local function send_commands(name)
	if not core.get_player_by_name(name) then
		return
	end
	local list = {}
	for cmd, def in pairs(core.registered_chatcommands) do
		if core.check_player_privs(name, def.privs or {}) then
			list[#list + 1] = {
				name = cmd,
				params = def.params or "",
				description = def.description or "",
			}
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	core.send_chat_commands(name, list)
end

core.register_on_joinplayer(function(player)
	send_commands(player:get_player_name())
end)

-- Available commands depend on the privileges
-- (Returning true lets the other priv callbacks run too.)
core.register_on_priv_grant(function(name)
	send_commands(name)
	return true
end)
core.register_on_priv_revoke(function(name)
	send_commands(name)
	return true
end)
