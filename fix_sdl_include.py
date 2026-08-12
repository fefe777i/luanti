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
    "src/porting_android.cpp",
    "#include <SDL3/SDL.h>",
    "#include <SDL.h>"
)

print()
if ok:
    print("=== УСПІХ: SDL3 -> SDL.h виправлено ===")
else:
    print("=== УВАГА: подивись помилку вище ===")
