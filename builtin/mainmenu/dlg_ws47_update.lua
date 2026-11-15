-- Workshop 47: update of the game from GitHub.
--
-- At start the menu downloads update.json (published by the GitHub workflow
-- next to the signed APK). If its "build" number is higher than the one of
-- the installed game, a dialog offers to download and install the new APK.

local APK_NAME = "ws47_update.apk"

local function installed_build()
	local ok, number = pcall(function()
		local f = io.open(core.get_builtin_path() .. "ws47_build.txt", "r")
		if not f then return 0 end
		local s = f:read("*a")
		f:close()
		return tonumber(s) or 0
	end)
	return ok and number or 0
end

local function apk_path()
	return core.get_user_path() .. DIR_DELIM .. APK_NAME
end

local function update_formspec(data)
	local fs = {
		"formspec_version[3]",
		"size[12.8,7]",
		"style_type[label;textcolor=#0E0]",
		"label[0.5,0.8;", core.formspec_escape("Доступна нова версія"), "]",
	}
	local text
	if data.state == "downloading" then
		text = "Завантаження оновлення…\nНе закривай гру."
	elseif data.state == "permission" then
		text = "Дозволь цьому застосунку встановлювати оновлення\n" ..
				"(відкрилися налаштування Android), потім повернись і натисни «Оновити» ще раз."
	elseif data.state == "failed" then
		text = "Не вдалося завантажити оновлення. Перевір інтернет і спробуй ще раз."
	else
		text = "Нова збірка: " .. tostring(data.build) ..
				"\nВстановлена: " .. tostring(installed_build())
		if data.notes and data.notes ~= "" then
			text = text .. "\n\n" .. data.notes
		end
		text = text .. "\n\nНатисни «Оновити», гра завантажить і встановить оновлення."
	end
	fs[#fs + 1] = "textarea[0.4,1.6;12,3.8;;;" .. core.formspec_escape(text) .. "]"
	fs[#fs + 1] = "container[0.4,5.8]"
	if data.state ~= "downloading" then
		fs[#fs + 1] = "button[0,0;4,0.8;ws47_update_go;" .. core.formspec_escape("Оновити") .. "]"
	end
	fs[#fs + 1] = "button[4.5,0;3.5,0.8;ws47_update_later;" ..
			core.formspec_escape("Пізніше") .. "]"
	fs[#fs + 1] = "container_end[]"
	return table.concat(fs, "")
end

local function start_download(this)
	local data = this.data
	data.state = "downloading"
	ui.update()
	local path = apk_path()
	core.handle_async(function(p)
		return core.download_file(p.url, p.path)
	end, { url = data.apk_url, path = path }, function(ok)
		if not ok then
			data.state = "failed"
			ui.update()
			return
		end
		if core.install_apk(path) then
			-- the system installer is open now
			data.state = nil
		else
			-- the permission screen was opened (or the file is broken)
			data.state = "permission"
		end
		ui.update()
	end)
end

local function update_buttonhandler(this, fields)
	if fields.ws47_update_later then
		this:delete()
		return true
	end
	if fields.ws47_update_go then
		if this.data.state ~= "downloading" then
			start_download(this)
		end
		return true
	end
	return false
end

local function update_eventhandler(event)
	if event == "DialogShow" then
		mm_game_theme.set_engine()
		return true
	end
	return false
end

local function on_update_info(json)
	local maintab = ui.find_by_name("maintab")
	if not maintab or maintab.hidden then
		return -- another dialog is open
	end
	local new_build = tonumber(json.build)
	if not new_build or type(json.apk_url) ~= "string" or json.apk_url == "" then
		core.log("error", "update.json: no build number or apk_url")
		return
	end
	if new_build <= installed_build() then
		return
	end

	maintab:hide()
	local dlg = dialog_create("ws47_update",
		update_formspec,
		update_buttonhandler,
		update_eventhandler)
	dlg.data.build = new_build
	dlg.data.apk_url = json.apk_url
	dlg.data.notes = type(json.notes) == "string" and json.notes or ""
	dlg:set_parent(maintab)
	dlg:show()
	ui.update()
end

function check_ws47_update()
	-- only on Android, where the APK can be installed
	if PLATFORM ~= "Android" or not core.get_http_api or not core.install_apk then
		return
	end
	local url = core.settings:get("ws47_update_url")
	if not url or url == "" then
		return
	end

	core.handle_async(function(params)
		local http = core.get_http_api()
		return http.fetch_sync(params)
	end, { url = url }, function(result)
		local json = result.succeeded and core.parse_json(result.data)
		if type(json) ~= "table" then
			core.log("warning", "Workshop 47 update check failed, status " ..
					tostring(result.code))
			return
		end
		on_update_info(json)
	end)
end
