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
    "android/app/src/main/java/net/minetest/minetest/GameActivity.java",
    "\t\tCustomEditText editText = new CustomEditText(this, editType);\n"
    "\t\tcontainer.addView(editText);\n"
    "\t\teditText.setMaxLines(8);\n",

    "\t\tCustomEditText editText = new CustomEditText(this, editType);\n"
    "\t\tcontainer.addView(editText);\n"
    "\t\teditText.setBackground(null); // прибрати стандартний зелений/сірий фон Android\n"
    "\t\teditText.setTextColor(0xFFFFFFFF); // білий текст, щоб було видно на темному тлі\n"
    "\t\teditText.setHintTextColor(0x99FFFFFF);\n"
    "\t\teditText.setMaxLines(8);\n"
)

print()
if ok:
    print("=== УСПІХ: нативне поле вводу тепер прозоре ===")
else:
    print("=== УВАГА: подивись помилку вище ===")
