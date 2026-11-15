-- Player list shown while the Tab key / on-screen Tab button is held.
-- Works in every game: it only needs the "tabb" bit of the player control.
--
-- Extension point for adding more info later:
--   core.register_tablist_info(function(player) return "text" end)
-- The returned text is shown to the right of the player's name.

local tablist = {}
core.tablist = tablist

local infos = {}
function core.register_tablist_info(func)
	infos[#infos + 1] = func
end

local LOGO = "ws47_logo.png"
local LOGO_SCALE = 0.17          -- the logo is 788x540 px
local ROW_H = 26                 -- px per player line
local PANEL_W = 360              -- px
local REFRESH = 1.0              -- seconds between refreshes while shown

local huds = {}   -- player name -> {ids = {...}, key = string}
local timers = {}

local function remove_hud(player, name)
	local st = huds[name]
	if not st then return end
	if player then
		for _, id in ipairs(st.ids) do
			player:hud_remove(id)
		end
	end
	huds[name] = nil
end

local function build_lines()
	local names = {}
	for _, p in ipairs(core.get_connected_players()) do
		names[#names + 1] = p
	end
	table.sort(names, function(a, b)
		return a:get_player_name():lower() < b:get_player_name():lower()
	end)
	local lines = {}
	for _, p in ipairs(names) do
		local text = p:get_player_name()
		local extra = {}
		for _, f in ipairs(infos) do
			local ok, s = pcall(f, p)
			if ok and type(s) == "string" and s ~= "" then
				extra[#extra + 1] = s
			end
		end
		lines[#lines + 1] = {name = text, extra = table.concat(extra, "  ")}
	end
	return lines
end

local function show_hud(player, name, lines)
	local key = {}
	for _, l in ipairs(lines) do
		key[#key + 1] = l.name .. "\1" .. l.extra
	end
	key = table.concat(key, "\2")
	local st = huds[name]
	if st and st.key == key then
		return -- nothing changed
	end
	remove_hud(player, name)

	local logo_h = math.floor(540 * LOGO_SCALE)
	local rows = math.max(#lines, 1)
	local panel_h = logo_h + 40 + rows * ROW_H + 12
	local ids = {}
	local function add(def)
		ids[#ids + 1] = player:hud_add(def)
	end

	-- semi-transparent background
	add({
		type = "image",
		position = {x = 0.5, y = 0},
		alignment = {x = 0, y = 1},
		offset = {x = 0, y = 8},
		text = "[fill:" .. PANEL_W .. "x" .. panel_h .. ":0,0:#000000B4",
		scale = {x = 1, y = 1},
		z_index = 900,
	})
	-- logo
	add({
		type = "image",
		position = {x = 0.5, y = 0},
		alignment = {x = 0, y = 1},
		offset = {x = 0, y = 12},
		text = LOGO,
		scale = {x = LOGO_SCALE, y = LOGO_SCALE},
		z_index = 901,
	})
	-- header
	add({
		type = "text",
		position = {x = 0.5, y = 0},
		alignment = {x = 0, y = 1},
		offset = {x = 0, y = 12 + logo_h + 4},
		text = #lines .. " / " .. (core.settings:get("max_users") or "?"),
		number = 0xAAAAAA,
		z_index = 902,
	})
	-- players
	local y = 12 + logo_h + 32
	for _, l in ipairs(lines) do
		add({
			type = "text",
			position = {x = 0.5, y = 0},
			alignment = {x = 1, y = 1},
			offset = {x = -PANEL_W / 2 + 16, y = y},
			text = l.name,
			number = 0xFFFFFF,
			z_index = 902,
		})
		if l.extra ~= "" then
			add({
				type = "text",
				position = {x = 0.5, y = 0},
				alignment = {x = -1, y = 1},
				offset = {x = PANEL_W / 2 - 16, y = y},
				text = l.extra,
				number = 0xBBBBBB,
				z_index = 902,
			})
		end
		y = y + ROW_H
	end

	huds[name] = {ids = ids, key = key}
end

core.register_globalstep(function(dtime)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if player:get_player_control().tabb then
			timers[name] = (timers[name] or REFRESH) + dtime
			if timers[name] >= REFRESH or not huds[name] then
				timers[name] = 0
				show_hud(player, name, build_lines())
			end
		elseif huds[name] then
			timers[name] = nil
			remove_hud(player, name)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	huds[name] = nil
	timers[name] = nil
end)
