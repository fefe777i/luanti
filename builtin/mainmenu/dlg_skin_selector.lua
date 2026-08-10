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

	local list_str = table.concat(skins, ",")

	return table.concat({
		"formspec_version[4]",
		"size[11,8]",
		ws47_theme.STYLE_PREFIX,
		"box[0,0;11,8;", ws47_theme.COLOR_BG, "]",
		"label[0.5,0.4;", fgettext("Character Skin"), "]",
		"label[0.5,0.8;", fgettext("Choose how you look on servers"), "]",
		"model[0.5,1.5;4.5,5.5;skin_preview;character.b3d;",
			core.formspec_escape(rel_tex), ";0,180;false;0,0;0;false]",
		"label[5.5,1.5;", fgettext("Available skins:"), "]",
		"textlist[5.5,1.9;5,4.2;skin_list;",
			core.formspec_escape(list_str), ";", sel, "]",
		"label[5.5,6.3;", fgettext("Selected: "), core.formspec_escape(skin_file), "]",
		"button[5.5,6.8;2.5,0.8;btn_skin_select;", fgettext("Wear Skin"), "]",
		"button[8,6.8;2.5,0.8;btn_skin_back;", fgettext("Back"), "]",
		"label[0.5,7.6;", core.colorize("#aaaaaa",
			fgettext("Tip: Put .png files into textures/base/pack/skins/")), "]",
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
