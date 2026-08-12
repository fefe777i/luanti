def apply(path, old, new, must_find=1):
    with open(path, 'r') as f:
        content = f.read()
    count = content.count(old)
    if count != must_find:
        print(f"ПОМИЛКА в {path}: очікував {must_find} збігів, знайшов {count}")
        print(f"--- шукав: ---\n{old}\n--- ---")
        return False
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print(f"OK: {path}")
    return True

ok = True

# Restore standard "no games" screen (with ContentDB game-install button),
# keep the purple theme wrapper
ok &= apply(
    "builtin/mainmenu/tab_local.lua",
    '''	-- Point the player to installing their own game when none is found
	if #pkgmgr.games == 0 then
		local W = tabview.width
		local H = tabview.height

		local hypertext = "<global valign=middle halign=center size=18>" ..
				fgettext_ne("No game is installed.") .. " " ..
				fgettext_ne("Install the Workshop 47 game to play.")

		local button_y = H * 2/3 - 0.6
		return table.concat({
			ws47_theme.STYLE_PREFIX,
			"box[0,0;", tostring(W), ",", tostring(H), ";", ws47_theme.COLOR_BG, "]",
			"hypertext[0.375,0;", W - 2*0.375, ",", button_y, ";ht;", core.formspec_escape(hypertext), "]"})
	end

	local retval = ws47_theme.STYLE_PREFIX ..
		"box[0,0;" .. tostring(tabview.width) .. "," .. tostring(tabview.height) .. ";" .. ws47_theme.COLOR_BG .. "]"''',
    '''	-- Point the player to ContentDB when no games are found
	if #pkgmgr.games == 0 then
		local W = tabview.width
		local H = tabview.height

		local hypertext = "<global valign=middle halign=center size=18>" ..
				fgettext_ne("Luanti is a game-creation platform that allows you to play many different games.") .. "\\n" ..
				fgettext_ne("Luanti doesn't come with a game by default.") .. " " ..
				fgettext_ne("You need to install a game before you can create a world.")

		local button_y = H * 2/3 - 0.6
		return table.concat({
			ws47_theme.STYLE_PREFIX,
			"box[0,0;", tostring(W), ",", tostring(H), ";", ws47_theme.COLOR_BG, "]",
			"hypertext[0.375,0;", W - 2*0.375, ",", button_y, ";ht;", core.formspec_escape(hypertext), "]",
			"button[5.25,", button_y, ";5,1.2;game_open_cdb;", fgettext("Install a game"), "]"})
	end

	local retval = ws47_theme.STYLE_PREFIX ..
		"box[0,0;" .. tostring(tabview.width) .. "," .. tostring(tabview.height) .. ";" .. ws47_theme.COLOR_BG .. "]"'''
)

# Restore standard gamebar (game selector strip + "install games" plus button)
ok &= apply(
    "builtin/mainmenu/tab_local.lua",
    '''function singleplayer_refresh_gamebar()
	-- Workshop 47: gamebar disabled, only one game is ever installed
	local old_bar = ui.find_by_name("game_button_bar")
	if old_bar ~= nil then
		old_bar:delete()
	end
	return false
end''',
    '''function singleplayer_refresh_gamebar()

	local old_bar = ui.find_by_name("game_button_bar")
	if old_bar ~= nil then
		old_bar:delete()
	end

	-- Hide gamebar if no games are installed
	if #pkgmgr.games == 0 then
		return false
	end

	local function game_buttonbar_button_handler(fields)
		for _, game in ipairs(pkgmgr.games) do
			if fields["game_btnbar_" .. game.id] then
				apply_game(game)
				return true
			end
		end
	end

	local TOUCH_GUI = core.settings:get_bool("touch_gui")

	local gamebar_pos_y = MAIN_TAB_H
		+ TABHEADER_H -- tabheader included in formspec size
		+ (TOUCH_GUI and GAMEBAR_OFFSET_TOUCH or GAMEBAR_OFFSET_DESKTOP)

	local btnbar = buttonbar_create(
			"game_button_bar",
			{x = 0, y = gamebar_pos_y},
			{x = MAIN_TAB_W, y = GAMEBAR_H},
			"#000000",
			game_buttonbar_button_handler)

	for _, game in ipairs(pkgmgr.games) do
		local btn_name = "game_btnbar_" .. game.id

		local image = nil
		local text = nil
		local tooltip = core.formspec_escape(game.title)

		if (game.menuicon_path or "") ~= "" then
			image = core.formspec_escape(game.menuicon_path)
		else
			local part1 = game.id:sub(1,5)
			local part2 = game.id:sub(6,10)
			local part3 = game.id:sub(11)

			text = part1 .. "\\n" .. part2
			if part3 ~= "" then
				text = text .. "\\n" .. part3
			end
		end
		btnbar:add_button(btn_name, text, image, tooltip)
	end

	local plus_image = core.formspec_escape(defaulttexturedir .. "plus.png")
	btnbar:add_button("game_open_cdb", "", plus_image, fgettext("Install games from ContentDB"))
	return true
end'''
)

print()
if ok:
    print("=== УСПІХ: стандартну поведінку відновлено, тема лишилась ===")
else:
    print("=== УВАГА: подивись помилки вище ===")
