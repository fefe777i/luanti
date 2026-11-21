-- Workshop 47 main menu theme: purple / blue / pink neon style
-- Shared style_type prefix used by tab_local.lua and tab_online.lua

ws47_theme = {}

ws47_theme.COLOR_PURPLE = "#c43cff"
ws47_theme.COLOR_PINK   = "#ff3cd2"
ws47_theme.COLOR_BLUE   = "#5a6eff"
ws47_theme.COLOR_BG     = "#14092eE0"      -- dark violet, semi-transparent
ws47_theme.COLOR_BG_2   = "#1f0f3fE0"

local function tex(name)
	return core.formspec_escape(defaulttexturedir .. name)
end

-- Buttons: lavender metal frame with cyan gems (same look as the eye frame)
ws47_theme.BUTTON_STYLE = "style_type[button,button_exit;" ..
	"bgimg=" .. tex("ws47_btn.png") ..
	";bgimg_hovered=" .. tex("ws47_btn_hover.png") ..
	";bgimg_pressed=" .. tex("ws47_btn_press.png") ..
	";bgimg_middle=9;bgcolor=#2a1250;bgcolor_hovered=#c43cff;" ..
	"bgcolor_pressed=#ff3cd2;textcolor=#f1e9ff;border=false]"

ws47_theme.STYLE_PREFIX = table.concat({
	ws47_theme.BUTTON_STYLE,
	"style_type[field,pwdfield;textcolor=#ffffff;border=true]",
	"style_type[label;textcolor=#e8d9ff]",
	"style_type[checkbox;textcolor=#e8d9ff]",
	"style_type[textarea;textcolor=#e8d9ff]",
})

-- Put the theme into a finished formspec right after its size[] element
-- (used for every dialog / tab, so all buttons share the style)
function ws47_theme.apply(formspec)
	if core.settings:get_bool("ws47_classic_menu") then
		return formspec
	end
	local _, stop = formspec:find("size%[[^%]]*%]")
	if not stop then
		return formspec
	end
	return formspec:sub(1, stop) .. ws47_theme.STYLE_PREFIX .. formspec:sub(stop + 1)
end


-- Path of the skin the player picked (falls back to the default skin).
function ws47_theme.get_skin_path()
	local full = core.settings:get("ws47_skin_fullpath")
	if full and full ~= "" then
		local f = io.open(full, "rb")
		if f then
			f:close()
			return full
		end
	end
	return defaulttexturedir .. "skins" .. DIR_DELIM .. "character.png"
end

-- model[] element with the player model wearing the given (or chosen) skin.
-- Drag with the mouse/finger to rotate it (unless no_mouse is set).
-- If the mesh file is missing, a visible message is shown instead, and the
-- paths are written to debug.txt to make problems easy to find.
function ws47_theme.player_model(x, y, w, h, skin_path, no_mouse)
	local mesh_path = defaulttexturedir .. "character.b3d"
	skin_path = skin_path or ws47_theme.get_skin_path()

	local f = io.open(mesh_path, "rb")
	if not f then
		core.log("error", "[ws47] player model mesh not found: " .. mesh_path)
		return table.concat({
			"textarea[", x + 0.1, ",", y + 0.1, ";", w - 0.2, ",", h - 0.2,
			";;;", core.formspec_escape("Model file not found:\n" .. mesh_path), "]",
		})
	end
	f:close()

	core.log("action", "[ws47] player model: mesh=" .. mesh_path ..
		" skin=" .. tostring(skin_path))

	return table.concat({
		"model[", x, ",", y, ";", w, ",", h, ";ws47_player;",
		core.formspec_escape(mesh_path), ";",
		core.formspec_escape(skin_path),
		";0,180;false;", no_mouse and "false" or "true", ";0,79;30]",
	})
end
