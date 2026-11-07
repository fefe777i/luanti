#!/usr/bin/env python3
"""Переносить кнопки RTS-режиму в лівий нижній кут (як у класичних RTS):
кнопки стоять компактним блоком зліва, нижній ряд заповнюється першим,
залишок - рядом вище. По центру внизу лишається місце під панель юніта.

Запуск з кореня репозиторію:  python3 apply_rts_buttons.py
Налаштування (minetest.conf):
  rts_buttons_align = left | center | right   (за замовчуванням left)
  rts_buttons_max_width = 0.4                 (частка ширини екрана для блоку кнопок)
Можна запускати повторно: вже застосоване пропускається."""
import os, sys

ROOT = os.getcwd()
PATH = os.path.join("src", "gui", "touchcontrols.cpp")

OLD = '''	// Finger sized buttons in rows at the bottom centre. The size is the
	// normal touch button size, shrunk until at most two rows are needed.
	const s32 margin = std::max<s32>(8, m_button_size / 6);
	const s32 avail_w = (s32)m_screensize.X - 2 * margin;
	s32 size = std::max<s32>(32, (m_button_size * 4) / 5);
	s32 gap = std::max<s32>(4, size / 8);
	s32 per_row = 1;
	for (;;) {
		per_row = std::max<s32>(1, (avail_w + gap) / (size + gap));
		const s32 rows = ((s32)n + per_row - 1) / per_row;
		if (rows <= 2 || size <= 32)
			break;
		size -= 4;
		gap = std::max<s32>(4, size / 8);
	}
	const s32 rows = ((s32)n + per_row - 1) / per_row;

	for (size_t i = 0; i < n; i++) {
		const s32 row = (s32)i / per_row;      // 0 = top row
		const s32 col = (s32)i % per_row;
		const s32 in_row = std::min<s32>(per_row, (s32)n - row * per_row);
		const s32 row_w = in_row * size + (in_row - 1) * gap;
		const s32 x = ((s32)m_screensize.X - row_w) / 2 + col * (size + gap);
		const s32 y = (s32)m_screensize.Y - margin - (rows - row) * size
				- (rows - 1 - row) * gap;
'''

NEW = '''	// Finger sized buttons in a compact block in a bottom corner (default:
	// bottom left). The bottom row is filled first, the rest goes on rows
	// above it. The size is the normal touch button size, shrunk until at
	// most two rows are needed. rts_buttons_align = left | center | right.
	const s32 margin = std::max<s32>(8, m_button_size / 6);
	std::string align;
	if (!g_settings->getNoEx("rts_buttons_align", align))
		align = "left";
	if (align != "center" && align != "right")
		align = "left";
	float max_frac = 0.4f;
	{
		std::string mf;
		if (g_settings->getNoEx("rts_buttons_max_width", mf) && !mf.empty()) {
			const float v = (float)atof(mf.c_str());
			if (v > 0.1f && v <= 1.0f)
				max_frac = v;
		}
	}
	const s32 avail_w = std::min<s32>((s32)m_screensize.X - 2 * margin,
			(s32)((float)m_screensize.X * max_frac));
	s32 size = std::max<s32>(32, (m_button_size * 4) / 5);
	s32 gap = std::max<s32>(4, size / 8);
	s32 per_row = 1;
	for (;;) {
		per_row = std::max<s32>(1, (avail_w + gap) / (size + gap));
		const s32 rows = ((s32)n + per_row - 1) / per_row;
		if (rows <= 2 || size <= 32)
			break;
		size -= 4;
		gap = std::max<s32>(4, size / 8);
	}

	for (size_t i = 0; i < n; i++) {
		const s32 row = (s32)i / per_row;      // 0 = bottom row
		const s32 col = (s32)i % per_row;
		const s32 block_w = per_row * size + (per_row - 1) * gap;
		s32 x0;
		if (align == "right")
			x0 = (s32)m_screensize.X - margin - block_w;
		else if (align == "center")
			x0 = ((s32)m_screensize.X - block_w) / 2;
		else
			x0 = margin;
		const s32 x = x0 + col * (size + gap);
		const s32 y = (s32)m_screensize.Y - margin - (row + 1) * size
				- row * gap;
'''

def main():
    full = os.path.join(ROOT, PATH)
    if not os.path.isfile(full):
        sys.exit("Запускай з кореня репозиторію luanti (немає %s)" % PATH)
    with open(full, encoding="utf-8", newline="") as f:
        s = f.read()
    if "rts_buttons_align" in s:
        print("[SKIP] кнопки RTS вже перенесені")
        return
    crlf = "\r\n" in s
    old = OLD.replace("\n", "\r\n") if crlf else OLD
    new = NEW.replace("\n", "\r\n") if crlf else NEW
    if old not in s:
        sys.exit("ERROR: не знайшов блок buildRtsButtons() - код відрізняється від очікуваного")
    with open(full, "w", encoding="utf-8", newline="") as f:
        f.write(s.replace(old, new, 1))
    print("[OK] %s: кнопки RTS тепер у лівому нижньому куті" % PATH)


if __name__ == "__main__":
    main()
