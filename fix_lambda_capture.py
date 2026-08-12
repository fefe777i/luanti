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

ok = apply(
    "android/app/src/main/java/net/minetest/minetest/GameActivity.java",
    '            runOnUiThread(() -> Toast.makeText(this, "Skin saved: " + name, Toast.LENGTH_SHORT).show());\n',
    '            final String finalName = name;\n'
    '            runOnUiThread(() -> Toast.makeText(this, "Skin saved: " + finalName, Toast.LENGTH_SHORT).show());\n'
)

print()
if ok:
    print("=== УСПІХ: лямбда тепер захоплює final-копію ===")
else:
    print("=== УВАГА: подивись помилку вище ===")
