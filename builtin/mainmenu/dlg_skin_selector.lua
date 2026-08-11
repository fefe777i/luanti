-- Workshop 47 / Skin Selector Dialog

local function get_skins_dir()
	return core.get_texturepath_share() .. DIR_DELIM .. "base" ..
		DIR_DELIM .. "pack" .. DIR_DELIM .. "skins"
end

local function get_skins()
	local dir = get_skins_dir()
	local list = core.get_dir_list(dir, false) or {}
	local skins = {}
	for _, f in ipairs(list) do
		if f:match("%.png$") then
			table.insert(skins, f)
		end
	end
	if #skins == 0 then
		skins = {"character.png"}
	end
	return skins, dir
end

local function get_formspec(data)
	local skins, skin_dir = data.skins, data.skin_dir
	local sel = data.selected or 1
	local skin_file = skins[sel] or "character.png"
	local rel_tex = "skins/" .. skin_file

	local escaped_skins = {}
	for _, s in ipairs(skins) do
		table.insert(escaped_skins, core.formspec_escape(s))
	end
	local list_str = table.concat(escaped_skins, ",")

	local new_skin_msg = ""
	if data.new_skin_name and data.new_skin_name ~= "" then
		new_skin_msg = "label[5.5,5.4;" .. core.colorize("#00ff00",
			"Added: " .. core.formspec_escape(data.new_skin_name)) .. "]"
	end

	return table.concat({
		"formspec_version[4]",
		"size[11,8]",
		ws47_theme.STYLE_PREFIX,
		"box[0,0;11,8;", ws47_theme.COLOR_BG, "]",
		"label[0.5,0.4;", fgettext("Character Skin"), "]",
		"label[0.5,0.8;", fgettext("Choose how you look on servers"), "]",

		"model[0.5,1.5;4.5,5.5;skin_preview;character.b3d;",
			core.formspec_escape(rel_tex), ";0,180;false;0,0;0;false]",

		"label[5.5,1.4;", fgettext("Available skins:"), "]",
		"textlist[5.5,1.8;5,3.2;skin_list;", list_str, ";", sel, "]",

		new_skin_msg,

		"label[5.5,5.8;", fgettext("Selected: "), core.formspec_escape(skin_file), "]",

		"button[5.5,6.3;2.3,0.7;btn_skin_select;", fgettext("Wear Skin"), "]",
		"button[7.9,6.3;2.3,0.7;btn_skin_back;", fgettext("Back"), "]",

		"button[5.5,7.1;2.3,0.7;btn_skin_add;", fgettext("+ Add Skin"), "]",
		"button[7.9,7.1;2.3,0.7;btn_skin_refresh;", fgettext("Refresh"), "]",
	})
end

local function handle_buttons(this, fields)
	if fields.skin_list then
		local evt = core.explode_textlist_event(fields.skin_list)
		if evt.type == "CHG" or evt.type == "DCL" then
			this.data.selected = evt.row
			return true
		end
	end

	if fields.btn_skin_refresh then
		local skins, dir = get_skins()
		this.data.skins = skins
		this.data.skin_dir = dir
		return true
	end

	if fields.btn_skin_add then
		if core.pick_skin_file then
			core.pick_skin_file()
			this.data.pick_pending = true
		end
		return true
	end

	if this.data.pick_pending and core.is_file_picked then
		if core.is_file_picked() then
			local path = core.get_picked_skin_path()
			if path and path ~= "" then
				this.data.new_skin_name = path
				this.data.pick_pending = false
				local skins, dir = get_skins()
				this.data.skins = skins
				return true
			end
		end
	end

	if fields.btn_skin_select then
		local skin = this.data.skins[this.data.selected or 1]
		if skin then
			core.settings:set("ws47_skin", skin)
			core.settings:set("ws47_skin_fullpath",
				this.data.skin_dir .. DIR_DELIM .. skin)
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

function create_skin_selector_dlg()
	local dlg = dialog_create("skin_selector", get_formspec, handle_buttons)
	local skins, dir = get_skins()
	dlg.data.skins = skins
	dlg.data.skin_dir = dir
	dlg.data.selected = 1
	dlg.data.new_skin_name = ""
	dlg.data.pick_pending = false
	local current = core.settings:get("ws47_skin")
	if current then
		for i, n in ipairs(skins) do
			if n == current then
				dlg.data.selected = i
				break
			end
		end
	end
	return dlg
end
