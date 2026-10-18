-- Workshop 47 / Skin Selector Dialog
-- Skins are shown as a gallery of 3D player models (6 per page).
-- Tap a model to select it, "Wear" to use it, "+ Add" to import a PNG skin.

local PER_PAGE = 6
local COLS = 3

local function get_skins_dir()
	return core.get_texturepath_share() .. DIR_DELIM .. "base" ..
		DIR_DELIM .. "pack" .. DIR_DELIM .. "skins"
end

local function get_skins()
	local dir = get_skins_dir()
	local list = core.get_dir_list(dir, false) or {}
	local skins = {}
	for _, f in ipairs(list) do
		if f:lower():match("%.png$") then
			table.insert(skins, f)
		end
	end
	-- default skin first, the rest alphabetically
	table.sort(skins, function(a, b)
		if a == "character.png" then return b ~= "character.png" end
		if b == "character.png" then return false end
		return a:lower() < b:lower()
	end)
	if #skins == 0 then
		skins = {"character.png"}
	end
	return skins, dir
end

local function page_count(data)
	return math.max(1, math.ceil(#data.skins / PER_PAGE))
end

local function select_skin(data, index)
	data.selected = index
	data.page = math.ceil(index / PER_PAGE)
end

local function short_name(name)
	name = name:gsub("%.[Pp][Nn][Gg]$", "")
	if #name > 15 then
		name = name:sub(1, 14) .. "~"
	end
	return name
end

local function get_formspec(data)
	local skins, skin_dir = data.skins, data.skin_dir
	local sel = data.selected or 1
	local pages = page_count(data)
	local page = math.min(math.max(data.page or 1, 1), pages)
	local blank = core.formspec_escape(defaulttexturedir .. "blank.png")

	local fs = {
		"formspec_version[4]",
		"size[8.4,8.9]",
		ws47_theme.STYLE_PREFIX,
		"box[0,0;8.4,8.9;", ws47_theme.COLOR_BG, "]",
		"label[0.4,0.4;", fgettext("Character Skin"), "]",
	}

	local worn = core.settings:get("ws47_skin")
	if data.new_skin_name and data.new_skin_name ~= "" then
		fs[#fs + 1] = "label[0.4,0.8;" .. core.colorize("#00ff00",
			"Added: " .. core.formspec_escape(data.new_skin_name)) .. "]"
	elseif worn and worn ~= "" then
		fs[#fs + 1] = "label[0.4,0.8;" .. core.colorize("#aaaaaa",
			fgettext("Wearing: ") .. core.formspec_escape(worn)) .. "]"
	end

	local first = (page - 1) * PER_PAGE + 1
	for n = 0, PER_PAGE - 1 do
		local i = first + n
		local skin = skins[i]
		if not skin then
			break
		end
		local col, row = n % COLS, math.floor(n / COLS)
		local x = 0.4 + col * 2.6
		local y = 1.2 + row * 3.4
		local selected = (i == sel)

		fs[#fs + 1] = "box[" .. x .. "," .. y .. ";2.4,3.25;" ..
			(selected and ws47_theme.COLOR_PURPLE or ws47_theme.COLOR_BG_2) .. "]"
		if selected then
			fs[#fs + 1] = "box[" .. (x + 0.06) .. "," .. (y + 0.06) ..
				";2.28,3.13;" .. ws47_theme.COLOR_BG_2 .. "]"
		end
		fs[#fs + 1] = ws47_theme.player_model(x + 0.1, y + 0.1, 2.2, 2.6,
			skin_dir .. DIR_DELIM .. skin, true)
		fs[#fs + 1] = "label[" .. (x + 0.15) .. "," .. (y + 2.95) .. ";" ..
			core.formspec_escape(short_name(skin)) .. "]"
		-- invisible button over the whole card: tap to select
		fs[#fs + 1] = "image_button[" .. x .. "," .. y .. ";2.4,3.25;" ..
			blank .. ";skin_pick_" .. i .. ";;false;false]"
	end

	fs[#fs + 1] = "button[0.4,7.95;1.4,0.7;btn_skin_back;" .. fgettext("Back") .. "]"
	fs[#fs + 1] = "button[1.9,7.95;0.7,0.7;btn_prev;<]"
	fs[#fs + 1] = "label[2.8,8.3;" .. page .. "/" .. pages .. "]"
	fs[#fs + 1] = "button[3.45,7.95;0.7,0.7;btn_next;>]"
	fs[#fs + 1] = "button[4.3,7.95;1.8,0.7;btn_skin_add;" .. fgettext("+ Add Skin") .. "]"
	fs[#fs + 1] = "button[6.2,7.95;1.8,0.7;btn_skin_select;" .. fgettext("Wear Skin") .. "]"

	return table.concat(fs)
end

local function handle_buttons(this, fields)
	local data = this.data

	for key in pairs(fields) do
		local idx = key:match("^skin_pick_(%d+)$")
		if idx then
			idx = tonumber(idx)
			if data.skins[idx] then
				select_skin(data, idx)
				data.new_skin_name = ""
			end
			return true
		end
	end

	if fields.btn_prev then
		data.page = math.max(1, (data.page or 1) - 1)
		return true
	end
	if fields.btn_next then
		data.page = math.min(page_count(data), (data.page or 1) + 1)
		return true
	end

	if fields.btn_skin_add then
		if core.pick_skin_file then
			core.pick_skin_file()
			data.pick_pending = true
		end
		return true
	end

	if fields.btn_skin_select then
		local skin = data.skins[data.selected or 1]
		if skin then
			core.settings:set("ws47_skin", skin)
			core.settings:set("ws47_skin_fullpath",
				data.skin_dir .. DIR_DELIM .. skin)
			-- Save now: the game is often closed without a clean exit, and an
			-- unsaved setting is lost (the chosen skin would reset).
			core.settings:write()
		end
		this:delete()
		return true
	end

	if fields.btn_skin_back then
		this:delete()
		return true
	end

	return false
end

-- Called by the engine ("FilePicked") as soon as the Android file picker is
-- done, so the dialog updates immediately instead of on the next tap.
local function on_file_picked(dlg)
	if not dlg.data.pick_pending or not core.get_picked_skin_path then
		return false
	end
	local path = core.get_picked_skin_path()
	dlg.data.pick_pending = false
	if not path or path == "" then
		dlg.data.new_skin_name = ""
		ui.update()
		return true
	end
	local name = path:match("([^/\\]+)$") or path
	dlg.data.new_skin_name = name
	local skins, dir = get_skins()
	dlg.data.skins = skins
	dlg.data.skin_dir = dir
	for i, n in ipairs(skins) do
		if n == name then
			select_skin(dlg.data, i)
			break
		end
	end
	ui.update()
	return true
end

function create_skin_selector_dlg()
	local dlg
	dlg = dialog_create("skin_selector", get_formspec, handle_buttons,
		function(event)
			if event == "FilePicked" then
				return on_file_picked(dlg)
			end
			return false
		end)
	local skins, dir = get_skins()
	dlg.data.skins = skins
	dlg.data.skin_dir = dir
	dlg.data.new_skin_name = ""
	dlg.data.pick_pending = false
	select_skin(dlg.data, 1)
	local current = core.settings:get("ws47_skin")
	if current then
		for i, n in ipairs(skins) do
			if n == current then
				select_skin(dlg.data, i)
				break
			end
		end
	end
	return dlg
end
