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

	-- Правильне екранування кожного елемента textlist
	local escaped_skins = {}
	for _, s in ipairs(skins) do
		table.insert(escaped_skins, core.formspec_escape(s))
	end
	local list_str = table.concat(escaped_skins, ",")

	return table.concat({
		"formspec_version[4]",
		"size[11,8]",
		ws47_theme.STYLE_PREFIX,
		"box[0,0;11,8;", ws47_theme.COLOR_BG, "]",

		"label[0.5,0.4;", fgettext("Character Skin"), "]",
		"label[0.5,0.8;", fgettext("Choose how you look on servers"), "]",

		-- 2D preview скіну (як у Bedrock) — надійніше ніж 3D model
		"box[0.5,1.4;4,4.2;#1a1a2e]",
		"image[1.0,1.7;3,3.6;", core.formspec_escape(rel_tex), "]",

		"label[5.5,1.4;", fgettext("Available skins:"), "]",
		"textlist[5.5,1.8;5,3.6;skin_list;", list_str, ";", sel, "]",

		"label[5.5,5.6;", fgettext("Selected: "), core.formspec_escape(skin_file), "]",

		"button[5.5,6.1;2.5,0.7;btn_skin_select;", fgettext("Wear Skin"), "]",
		"button[8,6.1;2.5,0.7;btn_skin_back;", fgettext("Back"), "]",

		-- Кнопка інструкції
		"button[0.5,5.8;4,0.7;btn_skin_help;", fgettext("How to add skins"), "]",

		-- Шлях до папки (показується при натисканні Help)
		data.show_help and ("label[0.5,6.7;" .. core.colorize("#00d4ff",
			core.formspec_escape(skin_dir)) .. "]") or "",
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

	if fields.btn_skin_help then
		this.data.show_help = not this.data.show_help
		return true
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
	dlg.data.show_help = false
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
