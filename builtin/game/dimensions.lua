-- Dimensions: several separate worlds (own map, own seed, own mapgen)
-- inside one world folder, like Overworld/Nether/End in Minecraft.
--
-- Engine API (C++):
--   core.get_current_dimension()            -> name of the loaded dimension
--   core.get_dimension_path()               -> folder with the map of the loaded dimension
--   core.list_dimensions()                  -> {"overworld", ...}
--   core.create_dimension(name[, settings]) -> true | false, error
--   core.switch_dimension(name)             -> true | false, error
--     (singleplayer only: the game restarts itself in the other dimension)
--   core.transfer_player(name, address, port) -> true | false, error
--     (multiplayer: the client of the player continues on another server)
--
-- Helper defined here:
--   core.travel_to_dimension(player, name[, pos]) -> true | false, error
--     Singleplayer: restarts the game in the other dimension.
--     Multiplayer: every dimension runs as its own server (setting "dimension")
--     and the player is sent to it (setting "dimension_servers", see
--     doc/dimensions.md).
--
-- Players, inventories and mod storage are shared by all dimensions, only the
-- map is separate.

local S = core.get_translator("__builtin")

local META_POS = "dimension_pos:"          -- last position in a dimension
local META_ARRIVAL = "dimension_arrival"   -- where to appear after the restart

local MAPGENS = {
	v5 = true, v6 = true, v7 = true, valleys = true,
	carpathian = true, fractal = true, flat = true, singlenode = true,
}

local function get_player(player_or_name)
	if type(player_or_name) == "string" then
		return core.get_player_by_name(player_or_name)
	end
	return player_or_name
end

--
-- Finding a safe place in a dimension that has not been visited yet
--

local function is_free(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def ~= nil and not def.walkable and def.liquidtype == "none"
		and (def.damage_per_second or 0) <= 0
end

local function find_surface(x, z, ymax, ymin)
	for y = ymax, ymin, -1 do
		local def = core.registered_nodes[core.get_node({x = x, y = y, z = z}).name]
		if def and def.walkable
				and is_free({x = x, y = y + 1, z = z})
				and is_free({x = x, y = y + 2, z = z}) then
			return {x = x, y = y + 1, z = z}
		end
	end
end

local function move_to_surface(name)
	local ymin, ymax = -64, 200
	core.emerge_area({x = 0, y = ymin, z = 0}, {x = 15, y = ymax, z = 15},
		function(_, _, calls_remaining)
			if calls_remaining > 0 then
				return
			end
			local player = core.get_player_by_name(name)
			if not player then
				return
			end
			player:set_pos(find_surface(8, 8, ymax, ymin) or {x = 8, y = 10, z = 8})
		end)
end

--
-- Travelling
--

-- "dimension_servers = overworld=30000, nether=30001, end=example.org:30002"
-- returns address ("" = same host as the player connected to) and port
local function get_dimension_server(dimension)
	local list = core.settings:get("dimension_servers") or ""
	for entry in list:gmatch("[^,]+") do
		local name, target = entry:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
		if name == dimension and target then
			local host, port = target:match("^(.*):(%d+)$")
			if host then
				return host, tonumber(port)
			end
			if target:match("^%d+$") then
				return "", tonumber(target)
			end
		end
	end
end

function core.travel_to_dimension(player, dimension, pos)
	player = get_player(player)
	if not player then
		return false, S("Player not found.")
	end
	local meta = player:get_meta()
	local current = core.get_current_dimension()

	if dimension == current then
		if pos then
			player:set_pos(pos)
			return true
		end
		return false, S("You are already in this world.")
	end

	-- Remember where the player left this dimension
	meta:set_string(META_POS .. current, core.pos_to_string(player:get_pos()))

	local target = pos
	if not target then
		local saved = meta:get_string(META_POS .. dimension)
		target = saved ~= "" and core.string_to_pos(saved) or nil
	end
	meta:set_string(META_ARRIVAL, target and core.pos_to_string(target) or "find")

	local ok, err
	if core.is_singleplayer() then
		ok, err = core.switch_dimension(dimension)
	else
		local host, port = get_dimension_server(dimension)
		if not port then
			ok, err = false, S("The world \"@1\" is not available on this server.", dimension)
		else
			local name = player:get_player_name()
			ok, err = core.transfer_player(name, host, port)
			if ok then
				-- Clients that cannot be transferred automatically get the port
				core.after(5, function()
					if core.get_player_by_name(name) then
						core.disconnect_player(name,
							S("Please reconnect to port @1 to enter the world \"@2\".",
							port, dimension))
					end
				end)
			end
		end
	end
	if not ok then
		meta:set_string(META_ARRIVAL, "")
		return false, err
	end
	return true
end

-- The game has been restarted in the new dimension: put the player in place.
-- Delayed so that it happens after all other on_joinplayer handlers.
core.register_on_joinplayer(function(player)
	local meta = player:get_meta()
	local arrival = meta:get_string(META_ARRIVAL)
	if arrival == "" then
		return
	end
	meta:set_string(META_ARRIVAL, "")

	local name = player:get_player_name()
	core.after(0, function()
		local p = core.get_player_by_name(name)
		if not p then
			return
		end
		local pos = core.string_to_pos(arrival)
		if pos then
			p:set_pos(pos)
		else
			move_to_surface(name)
		end
		core.chat_send_player(name,
			S("You arrived in the world: @1", core.get_current_dimension()))
	end)
end)

--
-- Chat commands
--

core.register_chatcommand("dimensions", {
	description = S("List all worlds (dimensions)"),
	func = function()
		return true, S("Worlds: @1. You are in: @2",
			table.concat(core.list_dimensions(), ", "), core.get_current_dimension())
	end,
})

core.register_chatcommand("dimension", {
	params = S("<world>"),
	description = S("Travel to another world (dimension)"),
	privs = {teleport = true},
	func = function(name, param)
		param = param:trim()
		if param == "" then
			return false, S("Worlds: @1. You are in: @2",
				table.concat(core.list_dimensions(), ", "), core.get_current_dimension())
		end
		local ok, err = core.travel_to_dimension(name, param)
		if not ok then
			return false, S("Could not travel: @1", err)
		end
		return true, S("Travelling to the world \"@1\"...", param)
	end,
})

core.register_chatcommand("newdimension", {
	params = S("<name> [<mapgen>]"),
	description = S("Create a new world (dimension) with its own terrain"),
	privs = {server = true},
	func = function(_, param)
		local dim, mapgen = param:match("^(%S+)%s*(%S*)$")
		if not dim then
			return false, S("Usage: /newdimension <name> [<mapgen>]")
		end
		local settings
		if mapgen ~= "" then
			if not MAPGENS[mapgen] then
				local names = {}
				for k in pairs(MAPGENS) do
					names[#names + 1] = k
				end
				table.sort(names)
				return false, S("Unknown map generator: @1. Use: @2",
					mapgen, table.concat(names, ", "))
			end
			settings = {mg_name = mapgen}
		end
		local ok, err = core.create_dimension(dim, settings)
		if not ok then
			return false, S("Could not create the world: @1", err)
		end
		return true, S("World \"@1\" created. Travel there with /dimension @2", dim, dim)
	end,
})
