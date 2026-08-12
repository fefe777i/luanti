-- Workshop 47 main menu theme: purple / blue / pink neon style
-- Shared style_type prefix used by tab_local.lua and tab_online.lua

ws47_theme = {}

ws47_theme.COLOR_PURPLE = "#c43cff"
ws47_theme.COLOR_PINK   = "#ff3cd2"
ws47_theme.COLOR_BLUE   = "#5a6eff"
ws47_theme.COLOR_BG     = "#14092eE0"      -- dark violet, semi-transparent
ws47_theme.COLOR_BG_2   = "#1f0f3fE0"

ws47_theme.STYLE_PREFIX = table.concat({
	"style_type[button;bgcolor=#2a1250;bgcolor_hovered=#c43cff;" ..
		"bgcolor_pressed=#ff3cd2;textcolor=#e8d9ff;border=true]",
	"style_type[field,pwdfield;textcolor=#ffffff;border=true]",
	"style_type[label;textcolor=#e8d9ff]",
	"style_type[checkbox;textcolor=#e8d9ff]",
	"style_type[textarea;textcolor=#e8d9ff]",
})
