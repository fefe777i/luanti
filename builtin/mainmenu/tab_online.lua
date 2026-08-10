-- Workshop 47 / Мастерская 47
-- Replaces the public server list with a single fixed server connect form.

-- >>> ВСТАВ СЮДИ IP/АДРЕСУ СВОГО СЕРВЕРА, КОЛИ БУДЕ ГОТОВО <<<
local SERVER_ADDRESS = ""      -- наприклад "123.45.67.89" або "my.server.com"
local SERVER_PORT    = 30000   -- стандартний порт Luanti/Minetest, зміни якщо треба

local LOGO = core.formspec_escape(defaulttexturedir .. "ws47_logo.png")

local function get_formspec(tabview, name, tabdata)
	local fs = {
		ws47_theme.STYLE_PREFIX,
		"box[0,0;15.5,7.1;", ws47_theme.COLOR_BG, "]",

		-- Лого по центру, вгорі
		"image[5.75,0.15;4,2.74;", LOGO, "]",

		"box[5.0,3.05;5.5,2.9;", ws47_theme.COLOR_BG_2, "]",

		-- Прозорі поля вводу (border=false ховає стандартний фон/рамку)
		"style_type[field;border=false;textcolor=#ffffff]",
		"style_type[pwdfield;border=false;textcolor=#ffffff]",

		"label[5.3,3.4;", fgettext("Ім'я:"), "]",
		"field[5.3,3.7;5,0.75;te_name;;",
			core.formspec_escape(core.settings:get("name")), "]",

		"label[5.3,4.6;", fgettext("Пароль:"), "]",
		"pwdfield[5.3,4.9;5,0.75;te_pwd;]",

		"style_type[field;border=true]",
		"style_type[pwdfield;border=true]",

		"button[5.3,5.75;3.2,0.9;btn_ws47_connect;",
			fgettext("Connect"), "]",
		"button[8.5,5.75;2,0.9;btn_ws47_skin;"
			fgettext("Skin"), "]",
	}

	if SERVER_ADDRESS == "" then
		fs[#fs + 1] = "style_type[label;textcolor=#ff6b6b]"
		fs[#fs + 1] = "label[5.3,6.8;" ..
			fgettext("(адреса сервера ще не налаштована)") .. "]"
	end

	return table.concat(fs)
end

local function main_button_handler(tabview, fields, name, tabdata)
	if fields.btn_ws47_skin then
		local dlg = create_skin_selector_dlg()
		dlg:set_parent(tabview)
		tabview:hide()
		dlg:show()
		return true
	end

	if fields.key_enter_field == "te_pwd" or fields.btn_ws47_connect then
		if fields.te_name == nil or fields.te_name == "" then
			gamedata.errormessage = fgettext("Введи ім'я гравця")
			return true
		end

		gamedata.playername = fields.te_name
		gamedata.password   = fields.te_pwd or ""
		gamedata.address     = SERVER_ADDRESS
		gamedata.port        = SERVER_PORT

		core.settings:set("name", fields.te_name)

		if SERVER_ADDRESS == "" then
			gamedata.errormessage = fgettext("Адреса сервера ще не налаштована")
			return true
		end

		core.start()
		return true
	end

	return false
end

local function on_change(type)
	if type == "ENTER" then
		mm_game_theme.set_engine()
		-- гарантовано ховаємо автоматичний header рушія - лого вже є у формі
		mm_game_theme.clear_single("header")
	end
end

return {
	name = "online",
	caption = fgettext("Мастерская 47"),
	cbf_formspec = get_formspec,
	cbf_button_handler = main_button_handler,
	on_change = on_change
}
