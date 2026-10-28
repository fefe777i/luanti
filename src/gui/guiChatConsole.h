// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include "modalMenu.h"
#include "chat.h"
#include "chatcommandinfo.h"
#include "irr_ptr.h"
#include <ctime>
#include <IGUIEnvironment.h>

class Client;
class GUIScrollBar;

class GUIChatConsole : public gui::IGUIElement
{
public:
	GUIChatConsole(gui::IGUIEnvironment* env,
			gui::IGUIElement* parent,
			s32 id,
			ChatBackend* backend,
			Client* client,
			IMenuManager* menumgr);
	~GUIChatConsole() override;

	// The console is not a modal menu, so touch events do not reach it through
	// the GUI environment. The input handler offers them here first.
	// Returns true if the event was used.
	static bool handleTouchEvent(const SEvent &event);

	// Open the console (height = desired fraction of screen size)
	// This doesn't open immediately but initiates an animation.
	// You should call isOpenInhibited() before this.
	void openConsole(f32 scale);

	bool isOpen() const;

	// Check if the console should not be opened at the moment
	// This is to avoid reopening the console immediately after closing
	bool isOpenInhibited() const;
	// Close the console, equivalent to openConsole(0).
	// This doesn't close immediately but initiates an animation.
	void closeConsole();
	// Close the console immediately, without animation.
	void closeConsoleAtOnce();
	// Set whether to close the console after the user presses enter.
	void setCloseOnEnter(bool close) { m_close_on_enter = close; }

	// Replace actual line when adding the actual to the history (if there is any)
	void replaceAndAddToHistory(const std::wstring &line);

	// Change how the cursor looks
	void setCursor(
		bool visible,
		bool blinking = false,
		f32 blink_speed = 1.0,
		f32 relative_height = 1.0);

	// Irrlicht draw method
	virtual void draw();

	virtual bool OnEvent(const SEvent& event);

	virtual void setVisible(bool visible);

	virtual bool acceptsIME() { return m_ime_active; }
	virtual bool acceptsScreenKeyboard() { return m_soft_keyboard_mode; }

private:
	void reformatConsole();
	void recalculateConsolePosition();

	// These methods are called by draw
	void animate(u32 msec);
	void drawBackground();
	void drawText();
	void drawPrompt();

	// If clicked fragment has a web url, send it to the system default web browser.
	// Returns true if, and only if a web url was pressed.
	// Layout of the console, in screen pixels. The modern window is a rounded
	// panel with a header (title, close button), the message rows with the
	// time of each message, and a footer (command button, input, send button).
	// The classic console only fills text and footer.
	struct Layout
	{
		s32 top = 0;          // top edge (negative while sliding in)
		core::recti panel;
		core::recti header;
		core::recti pill;     // title
		core::recti close_btn;
		core::recti text;     // message rows
		s32 text_x = 0;       // left edge of the message text
		s32 ts_right = 0;     // right edge of the times
		core::recti footer;
		core::recti slash_btn;
		core::recti input;
		core::recti send_btn;
		core::recti scroll_btn; // "scroll to newest", empty if not shown
	};
	Layout getLayout() const;
	void drawRoundRect(const core::recti &r, s32 radius, video::SColor color) const;
	void drawModernHeader(const Layout &l);
	void drawScrollButton(const Layout &l);
	// Buttons of the modern window, returns true if one was hit
	bool buttonClick(s32 x, s32 y);
	void sendPrompt();

	bool m_modern = true;
	// Touch devices without keyboard: the chat window fills the screen and
	// shrinks to make room for the keyboard while the input field is used.
	bool m_soft_keyboard_mode = false;
	bool m_ime_active = true;   // text input (and keyboard) is on
	bool m_input_pressed = false;
	void setKeyboardActive(bool on);
	u64 m_prev_total_added = 0;
	u32 m_unseen = 0; // messages that arrived while scrolled up

	// Chat command suggestions (shown above the prompt after typing "/")
	std::vector<const ChatCommandInfo *> getCommandSuggestions(size_t limit) const;
	void drawCommandSuggestions(s32 prompt_y, u32 font_height);
	bool commandSuggestionClick(s32 x, s32 y);
	// Tab completion of the command name. Returns false if not applicable.
	bool completeCommand();

	struct SuggestionRect
	{
		core::recti rect;
		std::string name;
	};
	std::vector<SuggestionRect> m_suggestion_rects;

	// Selecting chat messages: tap a message or drag over several of them,
	// the selected messages are copied to the clipboard on release.
	// Pointer (mouse or single touch) handling, returns true if consumed.
	// Touch: one finger drag scrolls, holding the finger still selects.
	// Mouse: dragging selects right away (the wheel scrolls).
	bool pointerDown(s32 x, s32 y, bool touch);
	bool pointerMove(s32 x, s32 y);
	bool pointerUp(s32 x, s32 y);
	// Row of the console buffer at a screen position, -1 if none
	s32 rowAt(s32 x, s32 y) const;
	bool inTextArea(s32 x, s32 y) const;
	// Starts selecting after the finger was held still long enough
	void updateLongPress();
	std::wstring rowText(u32 row) const;
	// Selected rows, extended to whole messages
	bool selectionRange(u32 &first, u32 &last) const;
	std::wstring selectionText(u32 first, u32 last) const;
	void clearSelection();

	static GUIChatConsole *s_instance;
	enum class Press { None, Pending, Scrolling };
	Press m_press = Press::None; // touch is down, not decided yet / scrolling
	u64 m_press_time = 0;
	s32 m_press_x = 0, m_press_y = 0;
	s32 m_press_row = -1;
	s32 m_scroll_y = 0;
	bool m_sel_active = false;  // pointer is down and selecting
	bool m_sel_visible = false; // highlight is shown
	s32 m_sel_anchor_row = 0;
	s32 m_sel_row = 0;
	std::wstring m_sel_text;    // what was copied, to detect scrolling
	u64 m_copied_until = 0;     // "Copied" label is shown until this time

	bool weblinkClick(s32 col, s32 row);

	// If the selected text changed, we need to update the (X11) primary selection.
	void updatePrimarySelection();

	void updateScrollbar(bool update_size = false);

private:
	ChatBackend* m_chat_backend;
	Client* m_client;
	IMenuManager* m_menumgr;
	irr_ptr<GUIScrollBar> m_scrollbar;

	// current screen size
	v2u32 m_screensize;

	// used to compute how much time passed since last animate()
	u64 m_animate_time_old;

	// should the console be opened or closed?
	bool m_open = false;
	// should it close after you press enter?
	bool m_close_on_enter = false;
	// current console height [pixels]
	s32 m_height = 0;
	// desired height [pixels]
	f32 m_desired_height = 0.0f;
	// desired height [screen height fraction]
	f32 m_desired_height_fraction = 0.0f;
	// console open/close animation speed [screen height fraction / second]
	f32 m_height_speed = 5.0f;
	// if nonzero, opening the console is inhibited [milliseconds]
	u32 m_open_inhibited = 0;

	// cursor blink frame (16-bit value)
	// cursor is off during [0,32767] and on during [32768,65535]
	u32 m_cursor_blink = 0;
	// cursor blink speed [on/off toggles / second]
	f32 m_cursor_blink_speed = 0.0f;
	// cursor height [line height]
	f32 m_cursor_height = 0.0f;

	// background texture
	video::ITexture *m_background = nullptr;
	// background color (including alpha)
	video::SColor m_background_color = video::SColor(255, 0, 0, 0);

	// font
	irr_ptr<gui::IGUIFont> m_font;
	v2u32 m_fontsize;

	// Enable clickable chat weblinks
	bool m_cache_clickable_chat_weblinks;
	// Track if a ctrl key is currently held down
	bool m_is_ctrl_down;
};
