#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
apply_patches.py
Застосовує .patch файли до репозиторію luanti.
Запускати з кореня репозиторію:
    cd ~/luanti-fork
    python3 apply_patches.py
"""

import os
import sys
import glob

REPO_ROOT = os.getcwd()

def main():
    if not os.path.isdir(os.path.join(REPO_ROOT, "builtin", "mainmenu")):
        print("ERROR: Запускай скрипт з кореня репозиторію luanti!")
        sys.exit(1)

    patches = glob.glob("*.patch")
    if not patches:
        print("Немає .patch файлів у поточній папці.")
        sys.exit(0)

    for patch in sorted(patches):
        print(f"\n>>> Застосовую: {patch}")
        ret = os.system(f'git apply --check "{patch}" 2>/dev/null')
        if ret != 0:
            print(f"    [WARN] git apply --check не пройшов, пробую --3way...")
            ret = os.system(f'git apply --3way "{patch}"')
        else:
            ret = os.system(f'git apply "{patch}"')

        if ret != 0:
            print(f"    [FAIL] Не вдалося застосувати {patch}")
        else:
            print(f"    [OK] {patch} застосовано")

    # Створюємо папку skins і копіюємо placeholder
    skins_dir = os.path.join(REPO_ROOT, "textures", "base", "pack", "skins")
    os.makedirs(skins_dir, exist_ok=True)

    src = os.path.join(REPO_ROOT, "textures", "base", "pack", "player.png")
    dst = os.path.join(skins_dir, "character.png")
    if os.path.exists(src) and not os.path.exists(dst):
        import shutil
        shutil.copy2(src, dst)
        print(f"[OK] Скопійовано player.png -> skins/character.png")

    # README
    readme = os.path.join(skins_dir, "README.txt")
    if not os.path.exists(readme):
        with open(readme, 'w') as f:
            f.write("Put your 64x32 or 64x64 PNG skins here.\n")
        print("[OK] Створено skins/README.txt")

    print("\n=== Git status ===")
    os.system("git status --short")

    print("\n=== Комітимо ===")
    os.system('git add -A')
    os.system('git commit -m "Apply skin menu and scroll patches"')

    print("\n=== Пушимо ===")
    os.system('git push origin $(git branch --show-current)')

    print("\n✅ Готово! Чекай GitHub Actions.")

if __name__ == "__main__":
    main()
