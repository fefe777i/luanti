#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_skin_v2.py - Повний патч: 3D preview + Android file picker + character.b3d"""

import os
import sys
import urllib.request

REPO_ROOT = os.getcwd()

def check_repo():
    if not os.path.isdir(os.path.join(REPO_ROOT, "builtin", "mainmenu")):
        print("ERROR: Запускай з кореня репозиторію luanti!")
        sys.exit(1)

def download_character_b3d():
    dst = os.path.join(REPO_ROOT, "textures", "base", "pack", "character.b3d")
    if os.path.exists(dst):
        print("[SKIP] character.b3d вже є")
        return True
    url = "https://raw.githubusercontent.com/luanti-org/minetest_game/master/mods/player_api/models/character.b3d"
    try:
        urllib.request.urlretrieve(url, dst)
        print("[OK] Завантажено character.b3d")
        return True
    except Exception as e:
        print(f"[WARN] Не вдалося завантажити: {e}")
        return False

def find_game_activity():
    for root, dirs, files in os.walk(os.path.join(REPO_ROOT, "android", "app", "src", "main", "java")):
        for f in files:
            if f == "GameActivity.java":
                return os.path.join(root, f)
    return None

def patch_game_activity(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if "pickFile" in content:
        print("[SKIP] GameActivity.java вже пропатчено")
        return
    if "import android.provider.DocumentsContract;" not in content:
        content = content.replace(
            "import android.content.res.Configuration;",
            "import android.content.res.Configuration;\nimport android.provider.DocumentsContract;\nimport android.database.Cursor;\nimport android.provider.OpenableColumns;"
        )
    vars_add = '\n    // Skin file picker\n    private String pickedFilePath = "";\n    private boolean filePicked = false;\n    private static final int PICK_SKIN_REQUEST = 1001;\n'
    marker = 'private int selectionReturnValue = 0;'
    if marker in content and "pickedFilePath" not in content:
        content = content.replace(marker, marker + vars_add)
    methods = '''
    public void pickFile() {
        runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("image/png");
            try {
                startActivityForResult(intent, PICK_SKIN_REQUEST);
            } catch (ActivityNotFoundException e) {
                Toast.makeText(this, "No file picker found", Toast.LENGTH_SHORT).show();
            }
        });
    }

    public String getPickedFilePath() {
        if (filePicked) {
            filePicked = false;
            return pickedFilePath;
        }
        return "";
    }

    public boolean isFilePicked() {
        return filePicked;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == PICK_SKIN_REQUEST && resultCode == RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri != null) {
                pickedFilePath = copyFileToSkins(uri);
                filePicked = true;
            }
        }
    }

    private String copyFileToSkins(Uri uri) {
        try {
            String name = "skin.png";
            Cursor cursor = getContentResolver().query(uri, null, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (idx >= 0) name = cursor.getString(idx);
                cursor.close();
            }
            java.io.File skinsDir = new java.io.File(getUserDataPath(), "textures/base/pack/skins");
            if (!skinsDir.exists()) skinsDir.mkdirs();
            java.io.File outFile = new java.io.File(skinsDir, name);
            java.io.InputStream in = getContentResolver().openInputStream(uri);
            java.io.FileOutputStream out = new java.io.FileOutputStream(outFile);
            byte[] buf = new byte[4096];
            int len;
            while ((len = in.read(buf)) > 0) out.write(buf, 0, len);
            in.close();
            out.close();
            runOnUiThread(() -> Toast.makeText(this, "Skin saved: " + name, Toast.LENGTH_SHORT).show());
            return name;
        } catch (Exception e) {
            Log.e("GameActivity", "Failed to copy skin: " + e.getMessage());
            return "";
        }
    }
'''
    last_brace = content.rfind("}")
    if last_brace != -1:
        content = content[:last_brace] + methods + "\n" + content[last_brace:]
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[OK] Пропатчено GameActivity.java")

def patch_porting_android_cpp():
    path = os.path.join(REPO_ROOT, "src", "porting_android.cpp")
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if "pickFileAndroid" in content:
        print("[SKIP] porting_android.cpp вже пропатчено")
        return
    func = "\nvoid pickFileAndroid()\n{\n\tjmethodID pickFile = jnienv->GetMethodID(activityClass, \"pickFile\", \"()V\");\n\tif (pickFile != nullptr) {\n\t\tjnienv->CallVoidMethod(activity, pickFile);\n\t}\n}\n\nstd::string getPickedFilePathAndroid()\n{\n\tjmethodID getPath = jnienv->GetMethodID(activityClass, \"getPickedFilePath\", \"()Ljava/lang/String;\");\n\tif (getPath == nullptr) return \"\";\n\tjobject result = jnienv->CallObjectMethod(activity, getPath);\n\tif (result == nullptr) return \"\";\n\treturn readJavaString((jstring) result);\n}\n\nbool isFilePickedAndroid()\n{\n\tjmethodID isPicked = jnienv->GetMethodID(activityClass, \"isFilePicked\", \"()Z\");\n\tif (isPicked == nullptr) return false;\n\treturn jnienv->CallBooleanMethod(activity, isPicked);\n}\n"
    marker = "} //namespace porting"
    if marker in content:
        content = content.replace(marker, func + marker)
    else:
        content = content.rstrip() + "\n" + func + "\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[OK] Пропатчено porting_android.cpp")

def patch_porting_android_h():
    path = os.path.join(REPO_ROOT, "src", "porting_android.h")
    if not os.path.exists(path):
        print("[WARN] porting_android.h не знайдено")
        return
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if "pickFileAndroid" in content:
        print("[SKIP] porting_android.h вже пропатчено")
        return
    decl = "\nvoid pickFileAndroid();\nstd::string getPickedFilePathAndroid();\nbool isFilePickedAndroid();\n"
    content = content.rstrip() + decl + "\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[OK] Пропатчено porting_android.h")

def patch_script_api():
    path = os.path.join(REPO_ROOT, "src", "script", "lua_api", "l_mainmenu.cpp")
    if not os.path.exists(path):
        print("[WARN] l_mainmenu.cpp не знайдено")
        return
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if "pick_skin_file" in content:
        print("[SKIP] l_mainmenu.cpp вже пропатчено")
        return
    if '#include "porting_android.h"' not in content:
        content = content.replace('#include "l_mainmenu.h"', '#include "l_mainmenu.h"\n#ifdef __ANDROID__\n#include "porting_android.h"\n#endif')
    funcs = "\n// Workshop 47: skin file picker\nint ModApiMainMenu::l_pick_skin_file(lua_State *L)\n{\n#ifdef __ANDROID__\n\tporting::pickFileAndroid();\n#endif\n\treturn 0;\n}\n\nint ModApiMainMenu::l_get_picked_skin_path(lua_State *L)\n{\n#ifdef __ANDROID__\n\tstd::string path = porting::getPickedFilePathAndroid();\n\tlua_pushstring(L, path.c_str());\n#else\n\tlua_pushstring(L, \"\");\n#endif\n\treturn 1;\n}\n\nint ModApiMainMenu::l_is_file_picked(lua_State *L)\n{\n#ifdef __ANDROID__\n\tlua_pushboolean(L, porting::isFilePickedAndroid());\n#else\n\tlua_pushboolean(L, false);\n#endif\n\treturn 1;\n}\n"
    marker = "void ModApiMainMenu::mod_mainmenu(lua_State *L)"
    if marker in content:
        content = content.replace(marker, funcs + marker)
    reg_marker = '{"show_keys_menu", l_show_keys_menu},'
    if reg_marker in content and "pick_skin_file" not in content:
        new_reg = '\t{"show_keys_menu", l_show_keys_menu},\n\t// Workshop 47 skin picker\n\t{"pick_skin_file", l_pick_skin_file},\n\t{"get_picked_skin_path", l_get_picked_skin_path},\n\t{"is_file_picked", l_is_file_picked},'
        content = content.replace(reg_marker, new_reg)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[OK] Пропатчено l_mainmenu.cpp")

def patch_mainmenu_header():
    path = os.path.join(REPO_ROOT, "src", "script", "lua_api", "l_mainmenu.h")
    if not os.path.exists(path):
        print("[WARN] l_mainmenu.h не знайдено")
        return
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if "l_pick_skin_file" in content:
        print("[SKIP] l_mainmenu.h вже пропатчено")
        return
    decl = "\n\tstatic int l_pick_skin_file(lua_State *L);\n\tstatic int l_get_picked_skin_path(lua_State *L);\n\tstatic int l_is_file_picked(lua_State *L);\n"
    content = content.replace("static void mod_mainmenu", decl + "\tstatic void mod_mainmenu")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[OK] Пропатчено l_mainmenu.h")

def update_skin_selector_lua():
    path = os.path.join(REPO_ROOT, "builtin", "mainmenu", "dlg_skin_selector.lua")
    code = '''-- Workshop 47 / Skin Selector Dialog

local function get_skins_dir()
\treturn core.get_texturepath_share() .. DIR_DELIM .. "base" ..
\t\tDIR_DELIM .. "pack" .. DIR_DELIM .. "skins"
end

local function get_skins()
\tlocal dir = get_skins_dir()
\tlocal list = core.get_dir_list(dir, false) or {}
\tlocal skins = {}
\tfor _, f in ipairs(list) do
\t\tif f:match("%.png$") then
\t\t\ttable.insert(skins, f)
\t\tend
\tend
\tif #skins == 0 then
\t\tskins = {"character.png"}
\tend
\treturn skins, dir
end

local function get_formspec(data)
\tlocal skins, skin_dir = data.skins, data.skin_dir
\tlocal sel = data.selected or 1
\tlocal skin_file = skins[sel] or "character.png"
\tlocal rel_tex = "skins/" .. skin_file

\tlocal escaped_skins = {}
\tfor _, s in ipairs(skins) do
\t\ttable.insert(escaped_skins, core.formspec_escape(s))
\tend
\tlocal list_str = table.concat(escaped_skins, ",")

\tlocal new_skin_msg = ""
\tif data.new_skin_name and data.new_skin_name ~= "" then
\t\tnew_skin_msg = "label[5.5,5.4;" .. core.colorize("#00ff00",
\t\t\t"Added: " .. core.formspec_escape(data.new_skin_name)) .. "]"
\tend

\treturn table.concat({
\t\t"formspec_version[4]",
\t\t"size[11,8]",
\t\tws47_theme.STYLE_PREFIX,
\t\t"box[0,0;11,8;", ws47_theme.COLOR_BG, "]",
\t\t"label[0.5,0.4;", fgettext("Character Skin"), "]",
\t\t"label[0.5,0.8;", fgettext("Choose how you look on servers"), "]",

\t\t"model[0.5,1.5;4.5,5.5;skin_preview;character.b3d;",
\t\t\tcore.formspec_escape(rel_tex), ";0,180;false;0,0;0;false]",

\t\t"label[5.5,1.4;", fgettext("Available skins:"), "]",
\t\t"textlist[5.5,1.8;5,3.2;skin_list;", list_str, ";", sel, "]",

\t\tnew_skin_msg,

\t\t"label[5.5,5.8;", fgettext("Selected: "), core.formspec_escape(skin_file), "]",

\t\t"button[5.5,6.3;2.3,0.7;btn_skin_select;", fgettext("Wear Skin"), "]",
\t\t"button[7.9,6.3;2.3,0.7;btn_skin_back;", fgettext("Back"), "]",

\t\t"button[5.5,7.1;2.3,0.7;btn_skin_add;", fgettext("+ Add Skin"), "]",
\t\t"button[7.9,7.1;2.3,0.7;btn_skin_refresh;", fgettext("Refresh"), "]",
\t})
end

local function handle_buttons(this, fields)
\tif fields.skin_list then
\t\tlocal evt = core.explode_textlist_event(fields.skin_list)
\t\tif evt.type == "CHG" or evt.type == "DCL" then
\t\t\tthis.data.selected = evt.row
\t\t\treturn true
\t\tend
\tend

\tif fields.btn_skin_refresh then
\t\tlocal skins, dir = get_skins()
\t\tthis.data.skins = skins
\t\tthis.data.skin_dir = dir
\t\treturn true
\tend

\tif fields.btn_skin_add then
\t\tif core.pick_skin_file then
\t\t\tcore.pick_skin_file()
\t\t\tthis.data.pick_pending = true
\t\tend
\t\treturn true
\tend

\tif this.data.pick_pending and core.is_file_picked then
\t\tif core.is_file_picked() then
\t\t\tlocal path = core.get_picked_skin_path()
\t\t\tif path and path ~= "" then
\t\t\t\tthis.data.new_skin_name = path
\t\t\t\tthis.data.pick_pending = false
\t\t\t\tlocal skins, dir = get_skins()
\t\t\t\tthis.data.skins = skins
\t\t\t\treturn true
\t\t\tend
\t\tend
\tend

\tif fields.btn_skin_select then
\t\tlocal skin = this.data.skins[this.data.selected or 1]
\t\tif skin then
\t\t\tcore.settings:set("ws47_skin", skin)
\t\t\tcore.settings:set("ws47_skin_fullpath",
\t\t\t\tthis.data.skin_dir .. DIR_DELIM .. skin)
\t\tend
\t\tthis:delete()
\t\treturn true
\tend

\tif fields.btn_skin_back then
\t\tthis:delete()
\t\treturn true
\tend

\treturn false
end

function create_skin_selector_dlg()
\tlocal dlg = dialog_create("skin_selector", get_formspec, handle_buttons)
\tlocal skins, dir = get_skins()
\tdlg.data.skins = skins
\tdlg.data.skin_dir = dir
\tdlg.data.selected = 1
\tdlg.data.new_skin_name = ""
\tdlg.data.pick_pending = false
\tlocal current = core.settings:get("ws47_skin")
\tif current then
\t\tfor i, n in ipairs(skins) do
\t\t\tif n == current then
\t\t\t\tdlg.data.selected = i
\t\t\t\tbreak
\t\t\tend
\t\tend
\tend
\treturn dlg
end
'''
    with open(path, "w", encoding="utf-8") as f:
        f.write(code)
    print("[OK] Оновлено dlg_skin_selector.lua")

def main():
    check_repo()
    print("=== 1. character.b3d ===")
    download_character_b3d()
    print("\n=== 2. GameActivity.java ===")
    ga = find_game_activity()
    if ga:
        patch_game_activity(ga)
    else:
        print("[ERROR] GameActivity.java не знайдено!")
    print("\n=== 3. C++ JNI ===")
    patch_porting_android_cpp()
    patch_porting_android_h()
    print("\n=== 4. Lua API ===")
    patch_script_api()
    patch_mainmenu_header()
    print("\n=== 5. Lua Menu ===")
    update_skin_selector_lua()
    print("\n=== 6. Git ===")
    os.system(f'cd {REPO_ROOT} && git add -A')
    os.system(f'cd {REPO_ROOT} && git commit -m "Add 3D skin preview + Android gallery picker"')
    os.system(f'cd {REPO_ROOT} && git push origin $(git branch --show-current)')
    print("\n✅ Готово! Чекай GitHub Actions.")

if __name__ == "__main__":
    main()
