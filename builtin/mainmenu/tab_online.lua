-- Workshop 47 / Мастерская 47
-- Replaces the public server list with a single fixed server connect form.

-- >>> ВСТАВ СЮДИ IP/АДРЕСУ СВОГО СЕРВЕРА, КОЛИ БУДЕ ГОТОВО <<<
local SERVER_ADDRESS = ""      -- наприклад "123.45.67.89" або "my.server.com"
local SERVER_PORT    = 30000   -- стандартний порт Luanti/Minetest, зміни якщо треба

local function get_formspec(tabview, name, tabdata)
	local fs = {
		ws47_theme.STYLE_PREFIX,
		"box[0,0;15.5,7.1;", ws47_theme.COLOR_BG, "]",

		"style_type[label;font=bold;font_size=28]",
		"label[5.1,1.0;", core.formspec_escape("МАСТЕРСКАЯ 47 СЕРВЕР"), "]",
		"style_type[label;font=normal;font_size=16]",

		"box[5.0,2.0;5.5,2.6;", ws47_theme.COLOR_BG_2, "]",

		"label[5.3,2.35;", fgettext("Ім'я:"), "]",
		"field[5.3,2.65;5,0.75;te_name;;",
			core.formspec_escape(core.settings:get("name")), "]",

		"label[5.3,3.55;", fgettext("Пароль:"), "]",
		"pwdfield[5.3,3.85;5,0.75;te_pwd;]",

		"button[5.3,4.9;5,0.9;btn_ws47_connect;",
			fgettext("Зареєструватися або увійти"), "]",
	}

	if SERVER_ADDRESS == "" then
		fs[#fs + 1] = "style_type[label;textcolor=#ff6b6b]"
		fs[#fs + 1] = "label[5.3,6.0;" ..
			fgettext("(адреса сервера ще не налаштована)") .. "]"
	end

	return table.concat(fs)
end

local function main_button_handler(tabview, fields, name, tabdata)
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
	end
end

return {
	name = "online",
	caption = fgettext("Мастерская 47"),
	cbf_formspec = get_formspec,
	cbf_button_handler = main_button_handler,
	on_change = on_change
}
