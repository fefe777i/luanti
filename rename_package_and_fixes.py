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

# 1) Package name (applicationId) - net.minetest.minetest -> net.workshop47.game
ok &= apply(
    "android/app/build.gradle",
    "\t\tapplicationId 'net.minetest.minetest'\n",
    "\t\tapplicationId 'net.workshop47.game'\n"
)

# 2) App display name -> Workshop 47 (idempotent-ish: only touches this exact line)
with open("android/app/src/main/res/values/strings.xml") as f:
    _strings_content = f.read()
if '<string name="label">Luanti</string>' in _strings_content:
    apply(
        "android/app/src/main/res/values/strings.xml",
        '<string name="label">Luanti</string>',
        '<string name="label">Workshop 47</string>'
    )
    print("OK: android/app/src/main/res/values/strings.xml (label)")
elif '<string name="label">Workshop 47</string>' in _strings_content:
    print("OK: label вже 'Workshop 47', пропускаю")
else:
    print("ПОПЕРЕДЖЕННЯ: не знайшов рядок label у strings.xml, перевір вручну")

# 3) Explicit separate pwdfield transparency style in tab_online.lua
ok &= apply(
    "builtin/mainmenu/tab_online.lua",
    '\t\t-- Прозорі поля вводу (border=false ховає стандартний фон/рамку)\n'
    '\t\t"style_type[field,pwdfield;border=false;textcolor=#ffffff]",',

    '\t\t-- Прозорі поля вводу (border=false ховає стандартний фон/рамку)\n'
    '\t\t"style_type[field;border=false;textcolor=#ffffff]",\n'
    '\t\t"style_type[pwdfield;border=false;textcolor=#ffffff]",'
)

ok &= apply(
    "builtin/mainmenu/tab_online.lua",
    '\t\t"style_type[field,pwdfield;border=true]",',
    '\t\t"style_type[field;border=true]",\n'
    '\t\t"style_type[pwdfield;border=true]",'
)

print()
if ok:
    print("=== УСПІХ ===")
else:
    print("=== УВАГА: подивись помилки вище ===")
