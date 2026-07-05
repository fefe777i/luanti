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
    "src/client/client.cpp",
    '#include "itemdef.h"\n#include "nodedef.h"\n',
    '#include "itemdef.h"\n#include "nodedef.h"\n#include "wieldmesh.h"\n'
)

print()
if ok:
    print("=== УСПІХ: include додано ===")
else:
    print("=== УВАГА: подивись помилку вище ===")
