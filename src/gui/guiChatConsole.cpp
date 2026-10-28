// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#include "guiChatConsole.h"
#include "chat.h"
#include "client/client.h"
#include "client/keycode.h"
#include "settings.h"
#include "porting.h"
#ifdef __ANDROID__
#include "porting_android.h"
#endif
#include "client/texturesource.h"
#include "client/fontengine.h"
#include "log.h"
#include "gettext.h"
#include "irrlicht_changes/CGUITTFont.h"
#include "util/string.h"
#include "guiScrollBar.h"
#include <IOSOperator.h>
#include <IVideoDriver.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <cstdlib>
#include <limits>
#include <string>

inline u32 clamp_u8(s32 value)
{
	return (u32) MYMIN(MYMAX(value, 0), 255);
}

inline bool isInCtrlKeys(const EKEY_CODE& kc)
{
	return kc == KEY_LCONTROL || kc == KEY_RCONTROL || kc == KEY_CONTROL;
}

inline u32 getScrollbarSize(IGUIEnvironment* env)
{
	return env->getSkin()->getSize(gui::EGDS_SCROLLBAR_SIZE);
}

GUIChatConsole::GUIChatConsole(
		gui::IGUIEnvironment* env,
		gui::IGUIElement* parent,
		s32 id,
		ChatBackend* backend,
		Client* client,
		IMenuManager* menumgr
):
	IGUIElement(gui::EGUIET_ELEMENT, env, parent, id,
			core::rect<s32>(0,0,100,100)),
	m_chat_backend(backend),
	m_client(client),
	m_menumgr(menumgr),
	m_animate_time_old(porting::getTimeMs())
{
	s_instance = this;
	m_modern = g_settings->getBool("chat_modern_ui");
#ifdef __ANDROID__
	if (m_modern && !porting::hasPhysicalKeyboardAndroid()) {
		m_soft_keyboard_mode = true;
		m_ime_active = false;
	}
#endif

	// load background settings
	s32 console_alpha = g_settings->getS32("console_alpha");
	m_background_color.setAlpha(clamp_u8(console_alpha));

	// load the background texture depending on settings
	ITextureSource *tsrc = client->getTextureSource();
	if (tsrc->isKnownSourceImage("background_chat.jpg")) {
		m_background = tsrc->getTexture("background_chat.jpg");
		m_background_color.setRed(255);
		m_background_color.setGreen(255);
		m_background_color.setBlue(255);
	} else {
		v3f console_color = g_settings->getV3F("console_color").value_or(v3f());
		m_background_color.setRed(clamp_u8(myround(console_color.X)));
		m_background_color.setGreen(clamp_u8(myround(console_color.Y)));
		m_background_color.setBlue(clamp_u8(myround(console_color.Z)));
	}

	const u16 chat_font_size = g_settings->getU16("chat_font_size");
	m_font.grab(g_fontengine->getFont(chat_font_size != 0 ?
		rangelim(chat_font_size, 5, 72) : FONT_SIZE_UNSPECIFIED, FM_Mono));

	if (!m_font) {
		errorstream << "GUIChatConsole: Unable to load mono font" << std::endl;
	} else {
		core::dimension2d<u32> dim = m_font->getDimension(L"M");
		m_fontsize = v2u32(dim.Width, dim.Height);
	}
	m_fontsize.X = MYMAX(m_fontsize.X, 1);
	m_fontsize.Y = MYMAX(m_fontsize.Y, 1);

	// set default cursor options
	setCursor(true, true, 2.0, 0.1);

	// track ctrl keys for mouse event
	m_is_ctrl_down = false;
	m_cache_clickable_chat_weblinks = g_settings->getBool("clickable_chat_weblinks");

	m_scrollbar.reset(new GUIScrollBar(env, this, -1, core::rect<s32>(0, 0, 30, m_height), false, tsrc));
	m_scrollbar->setSubElement(true);
	m_scrollbar->setLargeStep(1);
	m_scrollbar->setSmallStep(1);
}

void GUIChatConsole::openConsole(f32 scale)
{
	if (m_open)
		return;

	assert(scale > 0.0f && scale <= 1.0f);

	if (m_soft_keyboard_mode) {
		scale = 1.0f; // no keyboard yet
		m_ime_active = false;
	}

	m_open = true;

	m_desired_height_fraction = scale;
	m_desired_height = scale * m_screensize.Y;
	reformatConsole();
	m_animate_time_old = porting::getTimeMs();
	IGUIElement::setVisible(true);
	m_menumgr->createdMenu(this);
}

GUIChatConsole *GUIChatConsole::s_instance = nullptr;

void GUIChatConsole::setKeyboardActive(bool on)
{
	if (!m_soft_keyboard_mode)
		return;
	m_ime_active = on;
	m_desired_height_fraction = on ?
			rangelim(g_settings->getFloat("chat_keyboard_height"), 0.2f, 0.7f) : 1.0f;
	m_desired_height = m_desired_height_fraction * m_screensize.Y;
	m_height = m_desired_height;
	reformatConsole();
}

GUIChatConsole::~GUIChatConsole()
{
	if (s_instance == this)
		s_instance = nullptr;
}

bool GUIChatConsole::handleTouchEvent(const SEvent &event)
{
	GUIChatConsole *c = s_instance;
	if (!c || event.EventType != EET_TOUCH_INPUT_EVENT)
		return false;
	if (!c->m_open || !c->Environment->hasFocus(c, true))
		return false;

	const s32 x = event.TouchInput.X;
	const s32 y = event.TouchInput.Y;
	if (event.TouchInput.touchedCount != 1) // ignore multi-touch while busy
		return c->m_sel_active || c->m_press != Press::None;

	switch (event.TouchInput.Event) {
	case ETIE_PRESSED_DOWN:
		return c->pointerDown(x, y, true);
	case ETIE_MOVED:
		return c->pointerMove(x, y);
	case ETIE_LEFT_UP:
		return c->pointerUp(x, y);
	default:
		return false;
	}
}

bool GUIChatConsole::isOpen() const
{
	return m_open;
}

bool GUIChatConsole::isOpenInhibited() const
{
	return m_open_inhibited > 0;
}

void GUIChatConsole::closeConsole()
{
	m_open = false;
	m_menumgr->deletingMenu(this);
	m_scrollbar->setVisible(false);
}

void GUIChatConsole::closeConsoleAtOnce()
{
	closeConsole();
	m_height = 0;
	recalculateConsolePosition();
}

void GUIChatConsole::replaceAndAddToHistory(const std::wstring &line)
{
	ChatPrompt& prompt = m_chat_backend->getPrompt();
	prompt.addToHistory(prompt.getLine());
	prompt.replace(line);
}


void GUIChatConsole::setCursor(
	bool visible, bool blinking, f32 blink_speed, f32 relative_height)
{
	if (visible)
	{
		if (blinking)
		{
			// leave m_cursor_blink unchanged
			m_cursor_blink_speed = blink_speed;
		}
		else
		{
			m_cursor_blink = 0x8000;  // on
			m_cursor_blink_speed = 0.0;
		}
	}
	else
	{
		m_cursor_blink = 0;  // off
		m_cursor_blink_speed = 0.0;
	}
	m_cursor_height = relative_height;
}

void GUIChatConsole::draw()
{
	if(!IsVisible)
		return;

	video::IVideoDriver* driver = Environment->getVideoDriver();

	// Check screen size
	v2u32 screensize = driver->getScreenSize();
	if (screensize != m_screensize)
	{
		// screen size has changed
		// scale current console height to new window size
		if (m_screensize.Y != 0)
			m_height = m_height * screensize.Y / m_screensize.Y;
		m_screensize = screensize;
		m_desired_height = m_desired_height_fraction * m_screensize.Y;
		reformatConsole();
	} else if (!m_scrollbar->getAbsolutePosition().isPointInside(core::vector2di(screensize.X, m_height))) {
		// the height of the chat window is no longer the height of the scrollbar
		// happens while opening/closing the window
		updateScrollbar(true);
	}

	// Animation
	u64 now = porting::getTimeMs();
	animate(now - m_animate_time_old);
	m_animate_time_old = now;

	// Draw console elements if visible
	if (m_height > 0)
	{
		drawBackground();
		drawText();
		drawPrompt();
	}

	gui::IGUIElement::draw();
}

void GUIChatConsole::reformatConsole()
{
	s32 cols, rows;
	if (m_modern) {
		const s32 fh = m_fontsize.Y, fw = m_fontsize.X;
		const s32 m = fh / 2, pad = fh / 2;
		// panel without header and footer, and without the column of times
		rows = ((s32)m_desired_height - 2 * m - 4 * fh) / fh;
		cols = ((s32)m_screensize.X - 2 * m - 3 * pad - 8 * fw) / fw;
	} else {
		cols = m_screensize.X / m_fontsize.X - 2; // make room for a margin (looks better)
		rows = m_desired_height / m_fontsize.Y - 1; // make room for the input prompt
	}
	if (cols <= 0 || rows <= 0)
		cols = rows = 0;

	updateScrollbar(true);

	recalculateConsolePosition();
	m_chat_backend->reformat(cols, rows);

	if (m_modern) {
		// The input field is narrower than the console
		Layout l = getLayout();
		s32 icols = (l.input.getWidth() - m_fontsize.Y) / (s32)m_fontsize.X;
		m_chat_backend->getPrompt().reformat(std::max<s32>(icols, 0) + 1);
	}
}

GUIChatConsole::Layout GUIChatConsole::getLayout() const
{
	Layout l;
	const s32 fw = m_fontsize.X, fh = m_fontsize.Y;
	const s32 W = m_screensize.X;
	const s32 rows = m_chat_backend->getConsoleBuffer().getRows();
	l.top = m_height - (s32)m_desired_height;

	if (!m_modern) {
		l.panel = core::recti(0, l.top, W, l.top + (s32)m_desired_height);
		l.text = core::recti(0, l.top, W, l.top + rows * fh);
		l.text_x = fw;
		l.ts_right = 0;
		l.footer = core::recti(0, l.text.LowerRightCorner.Y, W,
				l.text.LowerRightCorner.Y + fh);
		l.input = l.footer;
		return l;
	}

	const s32 m = fh / 2, pad = fh / 2, p2 = fh / 4;
	const s32 hdr = 2 * fh, ftr = 2 * fh;
	l.panel = core::recti(m, l.top + m, W - m, l.top + (s32)m_desired_height - m);
	const s32 left = l.panel.UpperLeftCorner.X, right = l.panel.LowerRightCorner.X;

	l.header = core::recti(left, l.panel.UpperLeftCorner.Y, right,
			l.panel.UpperLeftCorner.Y + hdr);
	const s32 bh = hdr - pad;
	const s32 by = l.header.UpperLeftCorner.Y + (hdr - bh) / 2;
	const s32 title_w = m_font ?
			(s32)m_font->getDimension(wstrgettext("Chat").c_str()).Width : 4 * fw;
	l.pill = core::recti(left + pad, by, left + pad + title_w + 2 * pad, by + bh);
	l.close_btn = core::recti(right - pad - bh, by, right - pad, by + bh);

	l.text = core::recti(left, l.header.LowerRightCorner.Y, right,
			l.header.LowerRightCorner.Y + rows * fh);
	l.text_x = left + pad;
	l.ts_right = right - pad;

	l.footer = core::recti(left, l.panel.LowerRightCorner.Y - ftr, right,
			l.panel.LowerRightCorner.Y);
	const s32 ih = ftr - pad;
	const s32 iy = l.footer.UpperLeftCorner.Y + (ftr - ih) / 2;
	l.slash_btn = core::recti(left + p2, iy, left + p2 + ih, iy + ih);
	l.send_btn = core::recti(right - p2 - ih, iy, right - p2, iy + ih);
	l.input = core::recti(l.slash_btn.LowerRightCorner.X + p2, iy,
			l.send_btn.UpperLeftCorner.X - p2, iy + ih);

	// "scroll to newest" while looking at older messages
	const ChatBuffer &buf = m_chat_backend->getConsoleBuffer();
	if (buf.getScrollPosition() < buf.getBottomScrollPos()) {
		const s32 w = 4 * fw + (m_unseen > 0 ?
				(s32)(std::to_string(m_unseen).size() + 1) * fw : 0);
		const s32 h = fh + fh / 2;
		const s32 cx = (left + right) / 2;
		const s32 bottom = l.text.LowerRightCorner.Y - pad;
		l.scroll_btn = core::recti(cx - w / 2 - pad, bottom - h,
				cx + w / 2 + pad, bottom);
	}
	return l;
}

void GUIChatConsole::drawRoundRect(const core::recti &r, s32 radius,
		video::SColor color) const
{
	if (r.getWidth() <= 0 || r.getHeight() <= 0)
		return;
	radius = std::min({radius, r.getWidth() / 2, r.getHeight() / 2});
	video::IVideoDriver *driver = Environment->getVideoDriver();
	const core::recti *clip = &AbsoluteClippingRect;

	driver->draw2DRectangle(color, core::recti(r.UpperLeftCorner.X,
			r.UpperLeftCorner.Y + radius, r.LowerRightCorner.X,
			r.LowerRightCorner.Y - radius), clip);
	for (s32 i = 0; i < radius; i++) {
		const f32 dy = radius - i - 0.5f;
		const s32 inset = radius - (s32)std::sqrt(std::max(0.0f,
				(f32)radius * radius - dy * dy));
		driver->draw2DRectangle(color, core::recti(r.UpperLeftCorner.X + inset,
				r.UpperLeftCorner.Y + i, r.LowerRightCorner.X - inset,
				r.UpperLeftCorner.Y + i + 1), clip);
		driver->draw2DRectangle(color, core::recti(r.UpperLeftCorner.X + inset,
				r.LowerRightCorner.Y - i - 1, r.LowerRightCorner.X - inset,
				r.LowerRightCorner.Y - i), clip);
	}
}

void GUIChatConsole::drawModernHeader(const Layout &l)
{
	video::IVideoDriver *driver = Environment->getVideoDriver();
	const s32 fh = m_fontsize.Y;

	// Title
	drawRoundRect(l.pill, l.pill.getHeight() / 2, video::SColor(255, 70, 72, 84));
	m_font->draw(wstrgettext("Chat").c_str(), l.pill,
			video::SColor(255, 255, 255, 255), true, true, &AbsoluteClippingRect);

	// Close button: a cross
	const core::recti &b = l.close_btn;
	const s32 cx = (b.UpperLeftCorner.X + b.LowerRightCorner.X) / 2;
	const s32 cy = (b.UpperLeftCorner.Y + b.LowerRightCorner.Y) / 2;
	const s32 s = std::max(3, fh / 3);
	const video::SColor white(255, 235, 235, 240);
	for (s32 o = 0; o < 2; o++) {
		driver->draw2DLine(core::vector2di(cx - s + o, cy - s),
				core::vector2di(cx + s + o, cy + s), white);
		driver->draw2DLine(core::vector2di(cx - s + o, cy + s),
				core::vector2di(cx + s + o, cy - s), white);
	}
}

void GUIChatConsole::drawScrollButton(const Layout &l)
{
	if (l.scroll_btn.getWidth() <= 0)
		return;
	video::IVideoDriver *driver = Environment->getVideoDriver();
	const core::recti &b = l.scroll_btn;
	drawRoundRect(b, b.getHeight() / 2, video::SColor(235, 60, 100, 220));

	// Arrow pointing down, followed by the number of unseen messages
	const s32 fh = m_fontsize.Y;
	const s32 pad = fh / 2;
	const s32 ax = b.UpperLeftCorner.X + pad + fh / 3;
	const s32 ay = (b.UpperLeftCorner.Y + b.LowerRightCorner.Y) / 2;
	const s32 s = std::max(3, fh / 4);
	const video::SColor white(255, 255, 255, 255);
	for (s32 o = 0; o < 2; o++) {
		driver->draw2DLine(core::vector2di(ax - s, ay - s / 2 + o),
				core::vector2di(ax, ay + s / 2 + o), white);
		driver->draw2DLine(core::vector2di(ax + s, ay - s / 2 + o),
				core::vector2di(ax, ay + s / 2 + o), white);
	}
	if (m_unseen > 0) {
		const std::wstring n = utf8_to_wide(std::to_string(m_unseen));
		core::recti t(ax + s + fh / 3, b.UpperLeftCorner.Y, b.LowerRightCorner.X,
				b.LowerRightCorner.Y);
		m_font->draw(n.c_str(), t, white, false, true, &AbsoluteClippingRect);
	}
}

void GUIChatConsole::sendPrompt()
{
	ChatPrompt &prompt = m_chat_backend->getPrompt();
	prompt.addToHistory(prompt.getLine());
	std::wstring text = prompt.replace(L"");
	m_client->typeChatMessage(text);
	if (m_close_on_enter) {
		closeConsoleAtOnce();
		m_close_on_enter = false;
	}
}

bool GUIChatConsole::buttonClick(s32 x, s32 y)
{
	if (!m_modern)
		return false;
	const Layout l = getLayout();
	const core::vector2di p(x, y);

	if (l.close_btn.isPointInside(p)) {
		closeConsoleAtOnce();
		m_close_on_enter = false;
		// inhibit open so the_game doesn't reopen immediately
		m_open_inhibited = 1;
		return true;
	}
	if (l.send_btn.isPointInside(p)) {
		sendPrompt();
		return true;
	}
	if (l.slash_btn.isPointInside(p)) {
		m_chat_backend->getPrompt().input(L'/');
		setKeyboardActive(true);
		return true;
	}
	if (l.scroll_btn.getWidth() > 0 && l.scroll_btn.isPointInside(p)) {
		m_chat_backend->getConsoleBuffer().scrollBottom();
		m_unseen = 0;
		return true;
	}
	return false;
}

void GUIChatConsole::recalculateConsolePosition()
{
	core::rect<s32> rect(0, 0, m_screensize.X, m_height);
	DesiredRect = rect;
	recalculateAbsolutePosition(false);
}

void GUIChatConsole::animate(u32 msec)
{
	// animate the console height
	s32 goal = m_open ? m_desired_height : 0;

	// Set invisible if close animation finished (reset by openConsole)
	// This function (animate()) is never called once its visibility becomes false so do not
	//		actually set visible to false before the inhibited period is over
	if (!m_open && m_height == 0 && m_open_inhibited == 0)
		IGUIElement::setVisible(false);

	if (m_height != goal)
	{
		s32 max_change = msec * m_screensize.Y * (m_height_speed / 1000.0);
		if (max_change == 0)
			max_change = 1;

		if (m_height < goal)
		{
			// increase height
			if (m_height + max_change < goal)
				m_height += max_change;
			else
				m_height = goal;
		}
		else
		{
			// decrease height
			if (m_height > goal + max_change)
				m_height -= max_change;
			else
				m_height = goal;
		}

		recalculateConsolePosition();
	}

	// blink the cursor
	if (m_cursor_blink_speed != 0.0)
	{
		u32 blink_increase = 0x10000 * msec * (m_cursor_blink_speed / 1000.0);
		if (blink_increase == 0)
			blink_increase = 1;
		m_cursor_blink = ((m_cursor_blink + blink_increase) & 0xffff);
	}

	// decrease open inhibit counter
	if (m_open_inhibited > msec)
		m_open_inhibited -= msec;
	else
		m_open_inhibited = 0;
}

void GUIChatConsole::drawBackground()
{
	video::IVideoDriver* driver = Environment->getVideoDriver();
	if (m_modern) {
		const Layout l = getLayout();
		drawRoundRect(l.panel, m_fontsize.Y, m_background_color);
		return;
	}
	if (m_background != NULL)
	{
		core::rect<s32> sourcerect(0, -m_height, m_screensize.X, 0);
		driver->draw2DImage(
			m_background,
			v2s32(0, 0),
			sourcerect,
			&AbsoluteClippingRect,
			m_background_color,
			false);
	}
	else
	{
		driver->draw2DRectangle(
			m_background_color,
			core::rect<s32>(0, 0, m_screensize.X, m_height),
			&AbsoluteClippingRect);
	}
}

static std::wstring formatChatTime(std::time_t t)
{
	std::tm tmv{};
#ifdef _WIN32
	localtime_s(&tmv, &t);
#else
	localtime_r(&t, &tmv);
#endif
	char buf[16];
	snprintf(buf, sizeof(buf), "%02d:%02d:%02d", tmv.tm_hour, tmv.tm_min, tmv.tm_sec);
	return utf8_to_wide(buf);
}

void GUIChatConsole::drawText()
{
	if (!m_font)
		return;

	ChatBuffer& buf = m_chat_backend->getConsoleBuffer();

	// Count messages that arrive while the user looks at older ones
	{
		const u64 total = buf.getTotalAdded();
		if (buf.getScrollPosition() >= buf.getBottomScrollPos())
			m_unseen = 0;
		else if (total > m_prev_total_added)
			m_unseen += (u32)(total - m_prev_total_added);
		m_prev_total_added = total;
	}

	const Layout l = getLayout();
	if (m_modern)
		drawModernHeader(l);

	core::recti rect;
	if (m_modern)
		rect = l.text;
	else if (m_scrollbar->isVisible())
		rect = core::rect<s32> (0, 0, m_screensize.X - getScrollbarSize(Environment), m_height);
	else
		rect = AbsoluteClippingRect;

	updateLongPress();

	// Highlight of the selected messages
	if (m_sel_visible) {
		u32 first, last;
		if (!selectionRange(first, last) ||
				(!m_sel_active && selectionText(first, last) != m_sel_text)) {
			// Scrolled or reformatted, the selection no longer matches
			clearSelection();
		} else {
			video::IVideoDriver *driver = Environment->getVideoDriver();
			for (u32 row = first; row <= last; row++) {
				s32 y = l.text.UpperLeftCorner.Y + row * m_fontsize.Y;
				driver->draw2DRectangle(video::SColor(110, 70, 130, 255),
						core::recti(rect.UpperLeftCorner.X, y,
								rect.LowerRightCorner.X, y + m_fontsize.Y), &rect);
			}
		}
	}

	for (u32 row = 0; row < buf.getRows(); ++row)
	{
		const ChatFormattedLine& line = buf.getFormattedLine(row);
		if (line.fragments.empty())
			continue;

		s32 line_height = m_fontsize.Y;
		s32 y = l.text.UpperLeftCorner.Y + row * line_height;
		if (y + line_height < 0)
			continue;

		for (const ChatFormattedFragment &fragment : line.fragments) {
			s32 x = l.text_x + fragment.column * m_fontsize.X;
			core::rect<s32> destrect(
				x, y, x + m_fontsize.X * fragment.text.size(), y + m_fontsize.Y);

			if (m_font->getType() == gui::EGFT_CUSTOM) {
				// Draw colored text if possible
				auto *tmp = static_cast<gui::CGUITTFont*>(m_font.get());
				tmp->draw(
					fragment.text,
					destrect,
					false,
					false,
					&rect);
			} else {
				// Otherwise use standard text
				m_font->draw(
					fragment.text.c_str(),
					destrect,
					video::SColor(255, 255, 255, 255),
					false,
					false,
					&rect);
			}
		}

		// Time of the message, at the right edge
		if (m_modern && line.first && line.time != 0) {
			const std::wstring ts = formatChatTime(line.time);
			const s32 tw = m_font->getDimension(ts.c_str()).Width;
			core::recti tr(l.ts_right - tw, y, l.ts_right, y + line_height);
			m_font->draw(ts.c_str(), tr, video::SColor(255, 150, 152, 165),
					false, false, &rect);
		}
	}

	if (m_modern) {
		// Thin scroll indicator at the right edge
		const s32 top_pos = buf.getTopScrollPos();
		const s32 bot_pos = buf.getBottomScrollPos();
		if (bot_pos > top_pos && buf.getRows() > 0) {
			const s32 th = l.text.getHeight();
			const s32 total = (bot_pos - top_pos) + (s32)buf.getRows();
			const s32 thumb_h = std::max<s32>(m_fontsize.Y,
					th * (s32)buf.getRows() / total);
			const f32 frac = (f32)(buf.getScrollPosition() - top_pos) /
					(f32)(bot_pos - top_pos);
			const s32 ty = l.text.UpperLeftCorner.Y +
					(s32)((th - thumb_h) * std::min(1.0f, std::max(0.0f, frac)));
			drawRoundRect(core::recti(l.panel.LowerRightCorner.X - 6, ty,
					l.panel.LowerRightCorner.X - 2, ty + thumb_h), 2,
					video::SColor(170, 110, 150, 255));
		}
		drawScrollButton(l);
	}

	// Short confirmation after copying
	if (porting::getTimeMs() < m_copied_until) {
		const std::wstring label = L" " + wstrgettext("Copied") + L" ";
		core::dimension2d<u32> size = m_font->getDimension(label.c_str());
		s32 right = rect.LowerRightCorner.X - m_fontsize.X;
		s32 bottom = m_modern ? l.footer.UpperLeftCorner.Y - (s32)m_fontsize.Y / 2
				: m_height - (s32)m_fontsize.Y; // above the prompt
		core::recti box(right - (s32)size.Width, bottom - (s32)size.Height,
				right, bottom);
		video::IVideoDriver *driver = Environment->getVideoDriver();
		driver->draw2DRectangle(video::SColor(220, 40, 90, 200), box, &rect);
		m_font->draw(label.c_str(), box, video::SColor(255, 255, 255, 255),
				false, true, &rect);
	}

	updateScrollbar();
}

void GUIChatConsole::drawPrompt()
{
	if (!m_font)
		return;

	ChatPrompt& prompt = m_chat_backend->getPrompt();
	std::wstring prompt_text = prompt.getVisiblePortion();

	if (m_modern) {
		const Layout l = getLayout();
		video::IVideoDriver *driver = Environment->getVideoDriver();
		const s32 fh = m_fontsize.Y, pad = m_fontsize.Y / 2;
		const s32 bh = l.input.getHeight();
		const video::SColor white(255, 255, 255, 255);

		// "/" button, input field and send button
		drawRoundRect(l.slash_btn, bh / 2, video::SColor(255, 52, 54, 64));
		m_font->draw(L"/", l.slash_btn, white, true, true, &AbsoluteClippingRect);
		drawRoundRect(l.input, bh / 2, video::SColor(255, 30, 31, 38));
		drawRoundRect(l.send_btn, bh / 2, video::SColor(255, 60, 100, 220));

		// Send arrow: a filled triangle pointing right
		const s32 s = std::max(4, bh / 4);
		const s32 ax = (l.send_btn.UpperLeftCorner.X + l.send_btn.LowerRightCorner.X) / 2 - s / 2;
		const s32 ay = (l.send_btn.UpperLeftCorner.Y + l.send_btn.LowerRightCorner.Y) / 2;
		for (s32 i = 0; i <= 2 * s; i++) {
			const s32 hh = (s * (2 * s - i)) / (2 * s);
			driver->draw2DRectangle(white, core::recti(ax + i, ay - hh, ax + i + 1,
					ay + hh + 1), &AbsoluteClippingRect);
		}

		// The text of the input field (without the prompt character)
		std::wstring shown = prompt_text;
		if (!shown.empty())
			shown.erase(0, 1);
		const s32 tx = l.input.UpperLeftCorner.X + pad;
		const s32 ty = l.input.UpperLeftCorner.Y + (bh - fh) / 2;
		core::recti tr(tx, ty, l.input.LowerRightCorner.X - pad, ty + fh);
		if (shown.empty()) {
			m_font->draw(wstrgettext("Enter").c_str(), tr,
					video::SColor(255, 120, 122, 135), false, false, &tr);
		} else {
			m_font->draw(shown.c_str(), tr, white, false, false, &tr);
		}

		// Cursor
		if ((m_cursor_blink & 0x8000) != 0) {
			const s32 cursor_pos = prompt.getVisibleCursorPosition() - 1;
			if (cursor_pos >= 0 && cursor_pos <= (s32)shown.size()) {
				const s32 cx = tx + m_font->getDimension(
						shown.substr(0, cursor_pos).c_str()).Width;
				driver->draw2DRectangle(white,
						core::recti(cx, ty, cx + 2, ty + fh), &tr);
			}
		}

		drawCommandSuggestions(l.footer.UpperLeftCorner.Y, fh);
		return;
	}

	u32 font_width  = m_fontsize.X;
	u32 font_height = m_fontsize.Y;

	core::dimension2d<u32> size = m_font->getDimension(prompt_text.c_str());
	u32 text_width = size.Width;
	if (size.Height > font_height)
		font_height = size.Height;

	u32 row = m_chat_backend->getConsoleBuffer().getRows();
	s32 y = row * font_height + m_height - m_desired_height;

	core::rect<s32> destrect(
		font_width, y, font_width + text_width, y + font_height);
	m_font->draw(
		prompt_text.c_str(),
		destrect,
		video::SColor(255, 255, 255, 255),
		false,
		false,
		&AbsoluteClippingRect);

	// Draw the cursor during on periods
	if ((m_cursor_blink & 0x8000) != 0)
	{
		s32 cursor_pos = prompt.getVisibleCursorPosition();

		if (cursor_pos >= 0)
		{

			u32 text_to_cursor_pos_width = m_font->getDimension(prompt_text.substr(0, cursor_pos).c_str()).Width;

			s32 cursor_len = prompt.getCursorLength();
			video::IVideoDriver* driver = Environment->getVideoDriver();
			s32 x = font_width + text_to_cursor_pos_width;
			core::rect<s32> destrect(
				x,
				y + font_height * (1.0 - m_cursor_height),
				x + font_width * MYMAX(cursor_len, 1),
				y + font_height * (cursor_len ? m_cursor_height+1 : 1)
			);
			video::SColor cursor_color(255,255,255,255);
			driver->draw2DRectangle(
				cursor_color,
				destrect,
				&AbsoluteClippingRect);
		}
	}

	drawCommandSuggestions(y, font_height);
}

std::vector<const ChatCommandInfo *> GUIChatConsole::getCommandSuggestions(
		size_t limit) const
{
	std::vector<const ChatCommandInfo *> result;
	if (!m_client)
		return result;

	const std::wstring line = m_chat_backend->getPrompt().getLine();
	// Only while the command name itself is being typed
	if (line.empty() || line[0] != L'/' || line.find(L' ') != std::wstring::npos)
		return result;

	const std::string prefix = wide_to_utf8(line.substr(1));
	for (const ChatCommandInfo &cmd : m_client->getChatCommands()) {
		if (!str_starts_with(cmd.name, prefix))
			continue;
		result.push_back(&cmd);
		if (result.size() >= limit)
			break;
	}
	return result;
}

void GUIChatConsole::drawCommandSuggestions(s32 prompt_y, u32 font_height)
{
	m_suggestion_rects.clear();

	constexpr size_t MAX_SUGGESTIONS = 5;
	auto matches = getCommandSuggestions(MAX_SUGGESTIONS);
	if (matches.empty() || font_height == 0)
		return;

	// Only as many rows as fit above the prompt line
	size_t rows = std::min<size_t>(matches.size(),
			std::max<s32>(prompt_y, 0) / (s32)font_height);
	if (rows == 0)
		return;

	const s32 width = AbsoluteClippingRect.getWidth();
	const s32 pad = m_fontsize.X;
	const s32 top = prompt_y - (s32)(rows * font_height);

	video::IVideoDriver *driver = Environment->getVideoDriver();
	driver->draw2DRectangle(video::SColor(235, 24, 24, 28),
			core::recti(0, top, width, prompt_y), &AbsoluteClippingRect);

	for (size_t i = 0; i < rows; i++) {
		const ChatCommandInfo &cmd = *matches[i];
		core::recti row(0, top + (s32)(i * font_height), width,
				top + (s32)((i + 1) * font_height));
		m_suggestion_rects.push_back({row, cmd.name});

		const std::wstring name = utf8_to_wide("/" + cmd.name);
		const std::wstring params = utf8_to_wide(cmd.params);
		const std::wstring desc = utf8_to_wide(cmd.description);

		s32 x = pad;
		auto put = [&] (const std::wstring &text, video::SColor color) {
			if (text.empty())
				return;
			core::recti dest(x, row.UpperLeftCorner.Y, width, row.LowerRightCorner.Y);
			m_font->draw(text.c_str(), dest, color, false, false, &row);
			x += m_font->getDimension(text.c_str()).Width + pad;
		};
		put(name, video::SColor(255, 255, 255, 255));
		put(params, video::SColor(255, 150, 200, 255));
		put(desc, video::SColor(255, 160, 160, 160));
	}
}

bool GUIChatConsole::commandSuggestionClick(s32 x, s32 y)
{
	for (const SuggestionRect &s : m_suggestion_rects) {
		if (s.rect.isPointInside(core::vector2di(x, y))) {
			m_chat_backend->getPrompt().replace(utf8_to_wide("/" + s.name + " "));
			return true;
		}
	}
	return false;
}

bool GUIChatConsole::completeCommand()
{
	auto matches = getCommandSuggestions(std::numeric_limits<size_t>::max());
	if (matches.empty())
		return false;

	ChatPrompt &prompt = m_chat_backend->getPrompt();
	const std::string typed = wide_to_utf8(prompt.getLine().substr(1));

	if (matches.size() == 1) {
		prompt.replace(utf8_to_wide("/" + matches[0]->name + " "));
		return true;
	}

	// Complete up to the longest common prefix of all matches
	std::string common = matches[0]->name;
	for (const ChatCommandInfo *m : matches) {
		size_t n = 0;
		while (n < common.size() && n < m->name.size() && common[n] == m->name[n])
			n++;
		common.resize(n);
	}
	if (common.size() > typed.size())
		prompt.replace(utf8_to_wide("/" + common));
	return true;
}

bool GUIChatConsole::inTextArea(s32 x, s32 y) const
{
	if (m_fontsize.Y == 0)
		return false;
	// Same layout as in drawText()
	core::recti area = getLayout().text;
	if (!m_modern && m_scrollbar->isVisible())
		area.LowerRightCorner.X -= getScrollbarSize(Environment);
	return x >= area.UpperLeftCorner.X && x < area.LowerRightCorner.X &&
			y >= area.UpperLeftCorner.Y && y < area.LowerRightCorner.Y;
}

s32 GUIChatConsole::rowAt(s32 x, s32 y) const
{
	if (!inTextArea(x, y))
		return -1;
	const s32 top = getLayout().text.UpperLeftCorner.Y;
	const s32 row = (y - top) / (s32)m_fontsize.Y;
	const ChatBuffer &buf = m_chat_backend->getConsoleBuffer();
	if (row >= (s32)buf.getRows())
		return -1;
	if (buf.getFormattedLine(row).fragments.empty())
		return -1;
	return row;
}

void GUIChatConsole::updateLongPress()
{
	constexpr u64 HOLD_MS = 400;
	if (m_press != Press::Pending || m_press_row < 0)
		return;
	if (porting::getTimeMs() - m_press_time < HOLD_MS)
		return;
	// Held still: start selecting the message under the finger
	m_press = Press::None;
	m_sel_active = true;
	m_sel_visible = true;
	m_sel_anchor_row = m_press_row;
	m_sel_row = m_press_row;
	m_sel_text.clear();
}

std::wstring GUIChatConsole::rowText(u32 row) const
{
	const ChatFormattedLine &line =
			m_chat_backend->getConsoleBuffer().getFormattedLine(row);
	std::wstring out;
	for (const ChatFormattedFragment &frag : line.fragments) {
		if (out.size() < frag.column)
			out.append(frag.column - out.size(), L' ');
		out += frag.text.getString();
	}
	return out;
}

bool GUIChatConsole::selectionRange(u32 &first, u32 &last) const
{
	const ChatBuffer &buf = m_chat_backend->getConsoleBuffer();
	const s32 rows = buf.getRows();
	if (m_sel_anchor_row < 0 || m_sel_row < 0 ||
			m_sel_anchor_row >= rows || m_sel_row >= rows)
		return false;

	s32 a = std::min(m_sel_anchor_row, m_sel_row);
	s32 b = std::max(m_sel_anchor_row, m_sel_row);
	// Extend to whole messages (a message may be wrapped into several rows)
	while (a > 0 && !buf.getFormattedLine(a).first &&
			!buf.getFormattedLine(a - 1).fragments.empty())
		a--;
	while (b + 1 < rows && !buf.getFormattedLine(b + 1).first &&
			!buf.getFormattedLine(b + 1).fragments.empty())
		b++;
	first = a;
	last = b;
	return true;
}

std::wstring GUIChatConsole::selectionText(u32 first, u32 last) const
{
	const ChatBuffer &buf = m_chat_backend->getConsoleBuffer();
	std::wstring text;
	for (u32 row = first; row <= last; row++) {
		const ChatFormattedLine &line = buf.getFormattedLine(row);
		if (line.fragments.empty())
			continue;
		std::wstring t = rowText(row);
		// Trim the padding, wrapped rows are joined with one space
		size_t b = t.find_first_not_of(L' ');
		if (b == std::wstring::npos)
			continue;
		size_t e = t.find_last_not_of(L' ');
		t = t.substr(b, e - b + 1);

		if (!text.empty())
			text += line.first ? L'\n' : L' ';
		text += t;
	}
	return text;
}

void GUIChatConsole::clearSelection()
{
	m_sel_active = false;
	m_sel_visible = false;
	m_sel_text.clear();
}

bool GUIChatConsole::pointerDown(s32 x, s32 y, bool touch)
{
	m_press = Press::None;
	clearSelection();

	// Buttons of the window (close, "/", send, scroll to newest)
	if (buttonClick(x, y))
		return true;

	// Tap on a command suggestion
	if (commandSuggestionClick(x, y))
		return true;

	// Tap on the input field: (re)start the keyboard when released
	if (m_soft_keyboard_mode && getLayout().input.isPointInside(core::vector2di(x, y))) {
		m_ime_active = false; // stop text input, so it can be started again
		m_input_pressed = true;
		return true;
	}

	if (!inTextArea(x, y))
		return false;

	if (touch) {
		// Not decided yet: moving scrolls, holding still selects
		m_press = Press::Pending;
		m_press_time = porting::getTimeMs();
		m_press_x = x;
		m_press_y = y;
		m_press_row = rowAt(x, y);
		m_scroll_y = y;
		return true;
	}

	s32 row = rowAt(x, y);
	if (row < 0)
		return false;
	m_sel_active = true;
	m_sel_visible = true;
	m_sel_anchor_row = row;
	m_sel_row = row;
	m_sel_text.clear();
	return true;
}

bool GUIChatConsole::pointerMove(s32 x, s32 y)
{
	if (m_press == Press::Pending) {
		const s32 threshold = std::max<s32>(8, m_fontsize.Y / 2);
		if (std::abs(y - m_press_y) < threshold && std::abs(x - m_press_x) < threshold)
			return true; // still a hold, the timer decides
		m_press = Press::Scrolling;
		m_scroll_y = m_press_y;
	}
	if (m_press == Press::Scrolling) {
		// The text follows the finger: moving down shows older lines
		// (scroll() with a negative number goes back in time)
		const s32 fh = std::max<s32>(1, m_fontsize.Y);
		const s32 rows = (m_scroll_y - y) / fh;
		if (rows != 0) {
			m_chat_backend->scroll(rows);
			m_scroll_y -= rows * fh;
		}
		return true;
	}
	if (!m_sel_active)
		return false;
	// Keep the nearest row when the pointer leaves the text
	const s32 top = getLayout().text.UpperLeftCorner.Y;
	const s32 rows = m_chat_backend->getConsoleBuffer().getRows();
	if (m_fontsize.Y == 0 || rows == 0)
		return true;
	s32 row = (y - top) / (s32)m_fontsize.Y;
	if (y < top)
		row = 0;
	row = std::max<s32>(0, std::min<s32>(row, rows - 1));
	if (!m_chat_backend->getConsoleBuffer().getFormattedLine(row).fragments.empty())
		m_sel_row = row;
	return true;
}

bool GUIChatConsole::pointerUp(s32 x, s32 y)
{
	if (m_input_pressed) {
		m_input_pressed = false;
		setKeyboardActive(true);
		return true;
	}
	if (m_press != Press::None) {
		// A tap on the messages hides the keyboard, scrolling does not
		const bool tap = m_press == Press::Pending;
		m_press = Press::None;
		if (tap && m_soft_keyboard_mode && m_ime_active)
			setKeyboardActive(false);
		return true;
	}
	if (!m_sel_active)
		return false;
	pointerMove(x, y);
	m_sel_active = false;

	u32 first, last;
	if (!selectionRange(first, last)) {
		clearSelection();
		return true;
	}
	m_sel_text = selectionText(first, last);
	if (m_sel_text.empty()) {
		clearSelection();
		return true;
	}
	Environment->getOSOperator()->copyToClipboard(wide_to_utf8(m_sel_text).c_str());
	m_copied_until = porting::getTimeMs() + 1500;
	return true;
}

bool GUIChatConsole::OnEvent(const SEvent& event)
{

	ChatPrompt &prompt = m_chat_backend->getPrompt();

	if (event.EventType == EET_KEY_INPUT_EVENT && !event.KeyInput.PressedDown)
	{
		// CTRL up
		if (isInCtrlKeys(event.KeyInput.Key))
		{
			m_is_ctrl_down = false;
		}
	}
	else if(event.EventType == EET_KEY_INPUT_EVENT && event.KeyInput.PressedDown)
	{
		// CTRL down
		if (isInCtrlKeys(event.KeyInput.Key)) {
			m_is_ctrl_down = true;
		}

		// Key input
		if (keySettingHasMatch("keymap_console", event.KeyInput)) {
			closeConsole();

			// inhibit open so the_game doesn't reopen immediately
			m_open_inhibited = 50;
			m_close_on_enter = false;
			return true;
		}

		// Mac OS sends private use characters along with some keys.
		bool has_char = event.KeyInput.Char && !event.KeyInput.Control &&
				!iswcntrl(event.KeyInput.Char) && !IS_PRIVATE_USE_CHAR(event.KeyInput.Char);

		if (event.KeyInput.Key == KEY_ESCAPE) {
			closeConsoleAtOnce();
			m_close_on_enter = false;
			// inhibit open so the_game doesn't reopen immediately
			m_open_inhibited = 1; // so the ESCAPE button doesn't open the "pause menu"
			return true;
		}
		else if(event.KeyInput.Key == KEY_PRIOR)
		{
			if (!has_char) { // no num lock
				m_chat_backend->scrollPageUp();
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_NEXT)
		{
			if (!has_char) { // no num lock
				m_chat_backend->scrollPageDown();
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_RETURN)
		{
			prompt.addToHistory(prompt.getLine());
			std::wstring text = prompt.replace(L"");
			m_client->typeChatMessage(text);
			if (m_close_on_enter) {
				closeConsoleAtOnce();
				m_close_on_enter = false;
			}
			return true;
		}
		else if(event.KeyInput.Key == KEY_UP)
		{
			if (!has_char) { // no num lock
				// Up pressed
				// Move back in history
				prompt.historyPrev();
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_DOWN)
		{
			if (!has_char) { // no num lock
				// Down pressed
				// Move forward in history
				prompt.historyNext();
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_LEFT || event.KeyInput.Key == KEY_RIGHT)
		{
			if (!has_char) { // no num lock
				// Left/right pressed
				// Move/select character/word to the left depending on control and shift keys
				ChatPrompt::CursorOp op = event.KeyInput.Shift ?
					ChatPrompt::CURSOROP_SELECT :
					ChatPrompt::CURSOROP_MOVE;
				ChatPrompt::CursorOpDir dir = event.KeyInput.Key == KEY_LEFT ?
					ChatPrompt::CURSOROP_DIR_LEFT :
					ChatPrompt::CURSOROP_DIR_RIGHT;
				ChatPrompt::CursorOpScope scope = event.KeyInput.Control ?
					ChatPrompt::CURSOROP_SCOPE_WORD :
					ChatPrompt::CURSOROP_SCOPE_CHARACTER;
				prompt.cursorOperation(op, dir, scope);

				if (op == ChatPrompt::CURSOROP_SELECT)
					updatePrimarySelection();
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_HOME)
		{
			if (!has_char) { // no num lock
				// Home pressed
				// move to beginning of line
				prompt.cursorOperation(
					ChatPrompt::CURSOROP_MOVE,
					ChatPrompt::CURSOROP_DIR_LEFT,
					ChatPrompt::CURSOROP_SCOPE_LINE);
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_END)
		{
			if (!has_char) { // no num lock
				// End pressed
				// move to end of line
				prompt.cursorOperation(
					ChatPrompt::CURSOROP_MOVE,
					ChatPrompt::CURSOROP_DIR_RIGHT,
					ChatPrompt::CURSOROP_SCOPE_LINE);
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_BACK)
		{
			// Backspace or Ctrl-Backspace pressed
			// delete character / word to the left
			ChatPrompt::CursorOpScope scope =
				event.KeyInput.Control ?
				ChatPrompt::CURSOROP_SCOPE_WORD :
				ChatPrompt::CURSOROP_SCOPE_CHARACTER;
			prompt.cursorOperation(
				ChatPrompt::CURSOROP_DELETE,
				ChatPrompt::CURSOROP_DIR_LEFT,
				scope);
			return true;
		}
		else if(event.KeyInput.Key == KEY_DELETE)
		{
			if (!has_char) { // no num lock
				// Delete or Ctrl-Delete pressed
				// delete character / word to the right
				ChatPrompt::CursorOpScope scope =
					event.KeyInput.Control ?
					ChatPrompt::CURSOROP_SCOPE_WORD :
					ChatPrompt::CURSOROP_SCOPE_CHARACTER;
				prompt.cursorOperation(
					ChatPrompt::CURSOROP_DELETE,
					ChatPrompt::CURSOROP_DIR_RIGHT,
					scope);
				return true;
			}
		}
		else if(event.KeyInput.Key == KEY_KEY_A && event.KeyInput.Control)
		{
			// Ctrl-A pressed
			// Select all text
			prompt.cursorOperation(
				ChatPrompt::CURSOROP_SELECT,
				ChatPrompt::CURSOROP_DIR_LEFT, // Ignored
				ChatPrompt::CURSOROP_SCOPE_LINE);

			updatePrimarySelection();
			return true;
		}
		else if(event.KeyInput.Key == KEY_KEY_C && event.KeyInput.Control)
		{
			// Ctrl-C pressed
			// Copy text to clipboard
			if (prompt.getCursorLength() <= 0)
				return true;
			std::wstring wselected = prompt.getSelection();
			std::string selected = wide_to_utf8(wselected);
			Environment->getOSOperator()->copyToClipboard(selected.c_str());
			return true;
		}
		else if(event.KeyInput.Key == KEY_KEY_V && event.KeyInput.Control)
		{
			// Ctrl-V pressed
			// paste text from clipboard
			if (prompt.getCursorLength() > 0) {
				// Delete selected section of text
				prompt.cursorOperation(
					ChatPrompt::CURSOROP_DELETE,
					ChatPrompt::CURSOROP_DIR_LEFT, // Ignored
					ChatPrompt::CURSOROP_SCOPE_SELECTION);
			}
			IOSOperator *os_operator = Environment->getOSOperator();
			const c8 *text = os_operator->getTextFromClipboard();
			if (!text)
				return true;
			prompt.input(utf8_to_wide(text));
			return true;
		}
		else if(event.KeyInput.Key == KEY_KEY_X && event.KeyInput.Control)
		{
			// Ctrl-X pressed
			// Cut text to clipboard
			if (prompt.getCursorLength() <= 0)
				return true;
			std::wstring wselected = prompt.getSelection();
			std::string selected = wide_to_utf8(wselected);
			Environment->getOSOperator()->copyToClipboard(selected.c_str());
			prompt.cursorOperation(
				ChatPrompt::CURSOROP_DELETE,
				ChatPrompt::CURSOROP_DIR_LEFT, // Ignored
				ChatPrompt::CURSOROP_SCOPE_SELECTION);
			return true;
		}
		else if(event.KeyInput.Key == KEY_KEY_U && event.KeyInput.Control)
		{
			// Ctrl-U pressed
			// kill line to left end
			prompt.cursorOperation(
				ChatPrompt::CURSOROP_DELETE,
				ChatPrompt::CURSOROP_DIR_LEFT,
				ChatPrompt::CURSOROP_SCOPE_LINE);
			return true;
		}
		else if(event.KeyInput.Key == KEY_KEY_K && event.KeyInput.Control)
		{
			// Ctrl-K pressed
			// kill line to right end
			prompt.cursorOperation(
				ChatPrompt::CURSOROP_DELETE,
				ChatPrompt::CURSOROP_DIR_RIGHT,
				ChatPrompt::CURSOROP_SCOPE_LINE);
			return true;
		}
		else if(event.KeyInput.Key == KEY_TAB)
		{
			// Tab or Shift-Tab pressed
			// Command name completion after "/"
			if (completeCommand())
				return true;
			// Nick completion
			auto names = m_client->getConnectedPlayerNames();
			bool backwards = event.KeyInput.Shift;
			prompt.nickCompletion(names, backwards);
			return true;
		}

		if (has_char) {
			prompt.input(event.KeyInput.Char);
			return true;
		}
	}
	else if(event.EventType == EET_MOUSE_INPUT_EVENT)
	{
		if (event.MouseInput.Event == EMIE_MOUSE_WHEEL)
		{
			s32 rows = myround(-3.0 * event.MouseInput.Wheel);
			m_chat_backend->scroll(rows);
		}
		// Select messages / tap on a command suggestion
		else if (event.MouseInput.Event == EMIE_LMOUSE_PRESSED_DOWN &&
				!m_is_ctrl_down &&
				pointerDown(event.MouseInput.X, event.MouseInput.Y, false))
		{
			return true;
		}
		else if (event.MouseInput.Event == EMIE_MOUSE_MOVED &&
				pointerMove(event.MouseInput.X, event.MouseInput.Y))
		{
			return true;
		}
		else if (event.MouseInput.Event == EMIE_LMOUSE_LEFT_UP &&
				pointerUp(event.MouseInput.X, event.MouseInput.Y))
		{
			return true;
		}
		// Middle click or ctrl-click opens weblink, if enabled in config
		// Otherwise, middle click pastes primary selection
		else if (event.MouseInput.Event == EMIE_MMOUSE_PRESSED_DOWN ||
				(event.MouseInput.Event == EMIE_LMOUSE_PRESSED_DOWN && m_is_ctrl_down))
		{
			// If clicked within console output region
			const Layout lay = getLayout();
			if (m_modern ? inTextArea(event.MouseInput.X, event.MouseInput.Y) :
					event.MouseInput.Y / m_fontsize.Y < (m_height / m_fontsize.Y) - 1 )
			{
				// Translate pixel position to font position
				const s32 wl_col = (event.MouseInput.X - lay.text_x) / (s32)m_fontsize.X + 1;
				const s32 wl_row = (event.MouseInput.Y - lay.text.UpperLeftCorner.Y) /
						(s32)m_fontsize.Y;
				bool was_url_pressed = m_cache_clickable_chat_weblinks &&
						weblinkClick(wl_col, wl_row);

				if (!was_url_pressed
						&& event.MouseInput.Event == EMIE_MMOUSE_PRESSED_DOWN) {
					// Paste primary selection at cursor pos
					const c8 *text = Environment->getOSOperator()
							->getTextFromPrimarySelection();
					if (text)
						prompt.input(utf8_to_wide(text));
				}
			}
		}
	}
	else if(event.EventType == EET_STRING_INPUT_EVENT)
	{
		prompt.input(std::wstring(event.StringInput.Str->c_str()));
		return true;
	}
	else if (event.EventType == EET_GUI_EVENT && event.GUIEvent.EventType == EGET_SCROLL_BAR_CHANGED &&
			(void*) event.GUIEvent.Caller == (void*) m_scrollbar.get())
	{
		m_chat_backend->getConsoleBuffer().scrollAbsolute(m_scrollbar->getPos());
	}

	return Parent ? Parent->OnEvent(event) : false;
}

void GUIChatConsole::setVisible(bool visible)
{
	m_open = visible;
	IGUIElement::setVisible(visible);
	if (!visible) {
		m_height = 0;
		recalculateConsolePosition();
	}
	m_scrollbar->setVisible(visible);
}

bool GUIChatConsole::weblinkClick(s32 col, s32 row)
{
	// Prevent accidental rapid clicking
	static u64 s_oldtime = 0;
	u64 newtime = porting::getTimeMs();

	// 0.6 seconds should suffice
	if (newtime - s_oldtime < 600)
		return false;
	s_oldtime = newtime;

	const std::vector<ChatFormattedFragment> &
			frags = m_chat_backend->getConsoleBuffer().getFormattedLine(row).fragments;
	std::string weblink = ""; // from frag meta

	// Identify targeted fragment, if exists
	int indx = frags.size() - 1;
	if (indx < 0) {
		// Invalid row, frags is empty
		return false;
	}
	// Scan from right to left, offset by 1 font space because left margin
	while (indx > -1 && (u32)col < frags[indx].column + 1) {
		--indx;
	}
	if (indx > -1) {
		weblink = frags[indx].weblink;
		// Note if(indx < 0) then a frag somehow had a corrupt column field
	}

	/*
	// Debug help. Please keep this in case adjustments are made later.
	std::string ws;
	ws = "Middleclick: (" + std::to_string(col) + ',' + std::to_string(row) + ')' + " frags:";
	// show all frags <position>(<length>) for the clicked row
	for (u32 i=0;i<frags.size();++i) {
		if (indx == int(i))
			// tag the actual clicked frag
			ws += '*';
		ws += std::to_string(frags.at(i).column) + '('
			+ std::to_string(frags.at(i).text.size()) + "),";
	}
	actionstream << ws << std::endl;
	*/

	// User notification
	if (weblink.size() != 0) {
		std::ostringstream msg;
		msg << " * ";
		if (porting::open_url(weblink)) {
			msg << gettext("Opening webpage");
		}
		else {
			msg << gettext("Failed to open webpage");
		}
		msg << " '" << weblink << "'";
		m_chat_backend->addUnparsedMessage(utf8_to_wide(msg.str()));
		return true;
	}

	return false;
}

void GUIChatConsole::updatePrimarySelection()
{
	std::wstring wselected = m_chat_backend->getPrompt().getSelection();
	std::string selected = wide_to_utf8(wselected);
	Environment->getOSOperator()->copyToPrimarySelection(selected.c_str());
}

void GUIChatConsole::updateScrollbar(bool update_size)
{
	ChatBuffer &buf = m_chat_backend->getConsoleBuffer();
	m_scrollbar->setMin(buf.getTopScrollPos());
	m_scrollbar->setMax(buf.getBottomScrollPos());
	m_scrollbar->setPos(buf.getScrollPosition());
	m_scrollbar->setPageSize(m_fontsize.Y * buf.getLineCount());
	m_scrollbar->setVisible(!m_modern && m_scrollbar->getMin() != m_scrollbar->getMax());

	if (update_size) {
		const core::rect<s32> rect (m_screensize.X - getScrollbarSize(Environment), 0, m_screensize.X, m_height);
		m_scrollbar->setRelativePosition(rect);
	}
}
