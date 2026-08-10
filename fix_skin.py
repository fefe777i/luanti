#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys

REPO_ROOT = os.getcwd()

def check_repo():
    if not os.path.isdir(os.path.join(REPO_ROOT, "builtin", "mainmenu")):
        print("ERROR: Запускай з кореня репозиторію luanti!")
        sys.exit(1)

def create_skin_selector():
    path = os.path.join(REPO_ROOT, "builtin", "mainmenu", "dlg_skin_selector.lua")
    code = '''-- Workshop 47 / Skin Selector Dialog

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
	local abs_path = skin_dir .. DIR_DELIM .. skin_file

	if not core.file_exists(abs_path) then
		rel_tex = "player.png"
	end

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
'''
    with open(path, 'w', encoding='utf-8') as f:
        f.write(code)
    print("[OK] Створено dlg_skin_selector.lua")

def patch_init_lua():
    path = os.path.join(REPO_ROOT, "builtin", "mainmenu", "init.lua")
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    marker = 'dofile(menupath .. DIR_DELIM .. "dlg_server_list_mods.lua")'
    new_line = 'dofile(menupath .. DIR_DELIM .. "dlg_skin_selector.lua")'
    if new_line in content:
        print("[SKIP] init.lua вже містить dlg_skin_selector")
        return
    if marker not in content:
        print("[ERROR] Маркер не знайдено в init.lua")
        sys.exit(1)
    content = content.replace(marker, marker + '\n' + new_line)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("[OK] Пропатчено init.lua")

def patch_tab_online():
    path = os.path.join(REPO_ROOT, "builtin", "mainmenu", "tab_online.lua")
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Заміна кнопки
    old = '"button[5.3,5.75;5,0.9;btn_ws47_connect;"\n\t\t\tfgettext("Зареєструватися або увійти"), "]"'
    new = '"button[5.3,5.75;3.2,0.9;btn_ws47_connect;"\n\t\t\tfgettext("Connect"), "]",\n\t\t"button[8.5,5.75;2,0.9;btn_ws47_skin;"\n\t\t\tfgettext("Skin"), "]"'
    
    if 'btn_ws47_skin' in content:
        print("[SKIP] tab_online.lua вже містить кнопку Skin")
        return
    
    if old in content:
        content = content.replace(old, new)
    else:
        # fallback
        content = content.replace(
            '"button[5.3,5.75;5,0.9;btn_ws47_connect;',
            '"button[5.3,5.75;3.2,0.9;btn_ws47_connect;'
        )
        content = content.replace(
            'fgettext("Зареєструватися або увійти"), "]"',
            'fgettext("Connect"), "]",\n\t\t"button[8.5,5.75;2,0.9;btn_ws47_skin;"\n\t\t\tfgettext("Skin"), "]"'
        )
    
    # Додавання обробника
    handler = '''\tif fields.btn_ws47_skin then
\t\tlocal dlg = create_skin_selector_dlg()
\t\tdlg:set_parent(tabview)
\t\ttabview:hide()
\t\tdlg:show()
\t\treturn true
\tend

'''
    marker = '\tif fields.key_enter_field == "te_pwd" or fields.btn_ws47_connect then'
    if marker in content and 'fields.btn_ws47_skin' not in content:
        content = content.replace(marker, handler + marker)
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("[OK] Пропатчено tab_online.lua")

def fix_c_content():
    # Відкатити конфліктний файл до HEAD
    path = os.path.join(REPO_ROOT, "src", "script", "common", "c_content.cpp")
    if os.path.exists(path + ".orig"):
        os.system(f'cd {REPO_ROOT} && git checkout -- src/script/common/c_content.cpp')
        print("[OK] Відкочено c_content.cpp до чистого стану")
    elif os.system(f'cd {REPO_ROOT} && git diff --name-only --diff-filter=U | grep -q c_content.cpp') == 0:
        os.system(f'cd {REPO_ROOT} && git checkout --ours src/script/common/c_content.cpp')
        print("[OK] Відкочено c_content.cpp (ours)")
    else:
        print("[SKIP] c_content.cpp не потребує відкату")

def setup_skins_dir():
    skins_dir = os.path.join(REPO_ROOT, "textures", "base", "pack", "skins")
    os.makedirs(skins_dir, exist_ok=True)
    
    src = os.path.join(REPO_ROOT, "textures", "base", "pack", "player.png")
    dst = os.path.join(skins_dir, "character.png")
    if os.path.exists(src) and not os.path.exists(dst):
        import shutil
        shutil.copy2(src, dst)
        print("[OK] Скопійовано player.png -> skins/character.png")
    
    readme = os.path.join(skins_dir, "README.txt")
    if not os.path.exists(readme):
        with open(readme, 'w') as f:
            f.write("Put your 64x32 or 64x64 PNG skins here.\n")
        print("[OK] Створено skins/README.txt")

def commit():
    os.system(f'cd {REPO_ROOT} && git add -A')
    os.system(f'cd {REPO_ROOT} && git commit -m "Add skin selector menu (direct files)"')
    print("[OK] Закомічено")

def main():
    check_repo()
    create_skin_selector()
    patch_init_lua()
    patch_tab_online()
    fix_c_content()
    setup_skins_dir()
    commit()
    print("\n✅ Готово! Тепер запусти:")
    print("   git push origin workshop47")
    print("\nЯкщо push не проходить — налаштуй токен:")
    print("   git remote set-url origin https://ТВІЙ_ТОКЕН@github.com/fefe777i/luanti.git")

if __name__ == "__main__":
    main()
