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

ok &= apply(
    "builtin/mainmenu/init.lua",
    'local tabs = {\n\tcontent  = dofile(menupath .. DIR_DELIM .. "tab_content.lua"),\n\tabout = dofile(menupath .. DIR_DELIM .. "tab_about.lua"),\n\tlocal_game = dofile(menupath .. DIR_DELIM .. "tab_local.lua"),\n\tplay_online = dofile(menupath .. DIR_DELIM .. "tab_online.lua")\n}',
    'local tabs = {\n\tlocal_game = dofile(menupath .. DIR_DELIM .. "tab_local.lua"),\n\tplay_online = dofile(menupath .. DIR_DELIM .. "tab_online.lua")\n}'
)

ok &= apply(
    "builtin/mainmenu/init.lua",
    '\ttv_main:add(tabs.local_game)\n\ttv_main:add(tabs.play_online)\n\ttv_main:add(tabs.content)\n\ttv_main:add(tabs.about)',
    '\ttv_main:add(tabs.local_game)\n\ttv_main:add(tabs.play_online)'
)

print()
if ok:
    print("=== УСПІХ: вкладки Content і Докладніше видалено ===")
else:
    print("=== УВАГА: щось не застосувалось, дивись помилки вище ===")
