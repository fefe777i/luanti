// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2014 sapier
// Copyright (C) 2018 srifqi, Muhammad Rifqi Priyo Susanto
// Copyright (C) 2024 grorp, Gregor Parzefall

#include "touchcontrols.h"
#include "touchscreenlayout.h"

#include "irr_v2d.h"
#include "log.h"
#include "porting.h"
#include "settings.h"
#include "client/guiscalingfilter.h"
#include "client/inputhandler.h"
#include "client/renderingengine.h"
#include "client/texturesource.h"
#include "util/enum_string.h"
#include "irr_gui_ptr.h"
#include "IGUIImage.h"
#include "IGUIStaticText.h"
#include <IrrlichtDevice.h>
#include <ISceneCollisionManager.h>
#include <IGUIElement.h>
#include <IGUIEnvironment.h>

#include <iostream>
#include <algorithm>

TouchControls *g_touchcontrols;

void TouchControls::emitGameKeyEvent(GameKeyType key, float value)
{
	SEvent e{};
	e.EventType           = EET_USER_EVENT;
	e.UserEvent.type      = EUET_GAME_KEY;
	e.UserEvent.UserData1 = static_cast<size_t>(key);
	e.UserEvent.UserData2 = InputHandler::analogToInt(value);
	m_receiver->OnEvent(e);
}

void TouchControls::loadButtonTexture(IGUIImage *gui_button, const std::string &path)
{
	auto rect = gui_button->getRelativePosition();
	video::ITexture *texture = guiScalingImageButton(m_device->getVideoDriver(),
			m_texturesource->getTexture(path), rect.getWidth(), rect.getHeight());
	gui_button->setImage(texture);
	gui_button->setScaleImage(true);
}

void TouchControls::buttonEmitAction(button_info &btn, bool action)
{
	if (!btn.game_key)
		return;

	emitGameKeyEvent(btn.game_key, action);

	if (action) {
		if (btn.toggleable == button_info::FIRST_TEXTURE) {
			btn.toggleable = button_info::SECOND_TEXTURE;
			loadButtonTexture(btn.gui_button.get(), btn.toggle_textures[1]);

		} else if (btn.toggleable == button_info::SECOND_TEXTURE) {
			btn.toggleable = button_info::FIRST_TEXTURE;
			loadButtonTexture(btn.gui_button.get(), btn.toggle_textures[0]);
		}
	}
}

bool TouchControls::buttonsHandlePress(std::vector<button_info> &buttons, size_t pointer_id, IGUIElement *element)
{
	if (!element)
		return false;

	for (button_info &btn : buttons) {
		if (btn.gui_button.get() == element) {
			// Allow moving the camera with the same finger that holds dig/place.
			bool absorb = btn.id != dig_id && btn.id != place_id;

			assert(std::find(btn.pointer_ids.begin(), btn.pointer_ids.end(), pointer_id) == btn.pointer_ids.end());
			btn.pointer_ids.push_back(pointer_id);

			if (btn.pointer_ids.size() > 1)
				return absorb;

			buttonEmitAction(btn, true);
			btn.repeat_counter = -BUTTON_REPEAT_DELAY;
			return absorb;
		}
	}

	return false;
}


bool TouchControls::buttonsHandleRelease(std::vector<button_info> &buttons, size_t pointer_id)
{
	for (button_info &btn : buttons) {
		auto it = std::find(btn.pointer_ids.begin(), btn.pointer_ids.end(), pointer_id);
		if (it != btn.pointer_ids.end()) {
			// Don't absorb since we didn't absorb the press event either.
			bool absorb = btn.id != dig_id && btn.id != place_id;

			btn.pointer_ids.erase(it);

			if (!btn.pointer_ids.empty())
				return absorb;

			buttonEmitAction(btn, false);
			return absorb;
		}
	}

	return false;
}

bool TouchControls::buttonsStep(std::vector<button_info> &buttons, float dtime)
{
	bool has_pointers = false;

	for (button_info &btn : buttons) {
		if (btn.id == dig_id || btn.id == place_id)
			continue; // key repeats would cause glitches here
		if (btn.pointer_ids.empty())
			continue;
		has_pointers = true;

		btn.repeat_counter += dtime;
		if (btn.repeat_counter < BUTTON_REPEAT_INTERVAL)
			continue;

		buttonEmitAction(btn, false);
		buttonEmitAction(btn, true);
		btn.repeat_counter = 0.0f;
	}

	return has_pointers;
}

static GameKeyType id_to_action(touch_gui_button_id id)
{
	std::string key = "";
	switch (id) {
		case exit_id:
			return KeyType::ESC;
		case dig_id:
			return KeyType::DIG;
		case place_id:
			return KeyType::PLACE;
		case jump_id:
			return KeyType::JUMP;
		case sneak_id:
			return KeyType::SNEAK;
		case zoom_id:
			return KeyType::ZOOM;
		case aux1_id:
			return KeyType::AUX1;
		case fly_id:
			return KeyType::FREEMOVE;
		case noclip_id:
			return KeyType::NOCLIP;
		case fast_id:
			return KeyType::FASTMOVE;
		case debug_id:
			return KeyType::TOGGLE_DEBUG;
		case camera_id:
			return KeyType::CAMERA_MODE;
		case range_id:
			return KeyType::RANGESELECT;
		case minimap_id:
			return KeyType::MINIMAP;
		case toggle_chat_id:
			return KeyType::TOGGLE_CHAT;
		case chat_id:
			return KeyType::CHAT;
		case inventory_id:
			return KeyType::INVENTORY;
		case drop_id:
			return KeyType::DROP;
		default:
			return KeyType::INTERNAL_ENUM_COUNT;
	}
}


static const char *setting_names[] = {
	"touch_interaction_style",
	"touchscreen_threshold", "touch_long_tap_delay",
	"fixed_virtual_joystick", "virtual_joystick_triggers_aux1",
	"touch_layout",
};

namespace {

// Translucent green rectangle drawn while the RTS selection box is dragged.
class RtsBoxElement : public gui::IGUIElement
{
public:
	RtsBoxElement(gui::IGUIEnvironment *env, gui::IGUIElement *parent) :
		gui::IGUIElement(gui::EGUIET_ELEMENT, env, parent, -1, recti(0, 0, 1, 1))
	{}

	void draw() override
	{
		if (!isVisible())
			return;
		video::IVideoDriver *driver = Environment->getVideoDriver();
		const recti r = AbsoluteRect;
		driver->draw2DRectangle(video::SColor(55, 70, 255, 70), r, &AbsoluteClippingRect);

		const video::SColor edge(255, 110, 255, 110);
		const s32 t = 3;
		driver->draw2DRectangle(edge, recti(r.UpperLeftCorner.X, r.UpperLeftCorner.Y,
				r.LowerRightCorner.X, r.UpperLeftCorner.Y + t), &AbsoluteClippingRect);
		driver->draw2DRectangle(edge, recti(r.UpperLeftCorner.X, r.LowerRightCorner.Y - t,
				r.LowerRightCorner.X, r.LowerRightCorner.Y), &AbsoluteClippingRect);
		driver->draw2DRectangle(edge, recti(r.UpperLeftCorner.X, r.UpperLeftCorner.Y,
				r.UpperLeftCorner.X + t, r.LowerRightCorner.Y), &AbsoluteClippingRect);
		driver->draw2DRectangle(edge, recti(r.LowerRightCorner.X - t, r.UpperLeftCorner.Y,
				r.LowerRightCorner.X, r.LowerRightCorner.Y), &AbsoluteClippingRect);
		gui::IGUIElement::draw();
	}
};

} // namespace

TouchControls::TouchControls(IrrlichtDevice *device, ISimpleTextureSource *tsrc):
		m_device(device),
		m_guienv(device->getGUIEnvironment()),
		m_receiver(device->getEventReceiver()),
		m_texturesource(tsrc)
{
	m_screensize = m_device->getVideoDriver()->getScreenSize();
	m_button_size = ButtonLayout::getButtonSize(m_screensize);

	{
		auto *box = new RtsBoxElement(m_guienv, m_guienv->getRootGUIElement());
		box->setVisible(false);
		box->drop(); // the root element keeps it alive now
		m_rts_box_gui = grab_gui_element<gui::IGUIElement>(box);
	}

	readSettings();
	for (auto name : setting_names)
		g_settings->registerChangedCallback(name, settingChangedCallback, this);
}

void TouchControls::settingChangedCallback(const std::string &name, void *data)
{
	static_cast<TouchControls *>(data)->readSettings();
}

void TouchControls::readSettings()
{
	const std::string &s = g_settings->get("touch_interaction_style");
	if (!string_to_enum(es_TouchInteractionStyle, m_interaction_style, s)) {
		m_interaction_style = TAP;
		warningstream << "Invalid touch_interaction_style value" << std::endl;
	}

	// Taps must work in the RTS camera whatever the user's style is
	if (m_rts_mode)
		m_interaction_style = TAP;

	m_touchscreen_threshold = g_settings->getU16("touchscreen_threshold");
	m_long_tap_delay = g_settings->getU16("touch_long_tap_delay");
	m_fixed_joystick = g_settings->getBool("fixed_virtual_joystick");
	m_joystick_triggers_aux1 = g_settings->getBool("virtual_joystick_triggers_aux1");

	// Note that other settings also affect the layout:
	// - ButtonLayout::loadFromSettings: "touch_interaction_style" and "virtual_joystick_triggers_aux1"
	// - applyLayout: "fixed_virtual_joystick"
	applyLayout(ButtonLayout::loadFromSettings());
}

void TouchControls::applyLayout(const ButtonLayout &layout)
{
	m_layout = layout;

	m_buttons.clear();
	m_overflow_btn = nullptr;
	m_overflow_bg = nullptr;
	m_overflow_buttons.clear();
	m_overflow_button_titles.clear();
	m_overflow_button_rects.clear();

	// Initialize joystick display "button".
	// Joystick is placed on the bottom left of screen.
	if (m_fixed_joystick) {
		m_joystick_btn_off = grab_gui_element<IGUIImage>(makeButtonDirect(joystick_off_id,
				recti(m_button_size,
						m_screensize.Y - m_button_size * 4,
						m_button_size * 4,
						m_screensize.Y - m_button_size), true));
	} else {
		m_joystick_btn_off = grab_gui_element<IGUIImage>(makeButtonDirect(joystick_off_id,
				recti(m_button_size,
						m_screensize.Y - m_button_size * 3,
						m_button_size * 3,
						m_screensize.Y - m_button_size), true));
	}

	m_joystick_btn_bg = grab_gui_element<IGUIImage>(makeButtonDirect(joystick_bg_id,
			recti(m_button_size,
					m_screensize.Y - m_button_size * 4,
					m_button_size * 4,
					m_screensize.Y - m_button_size), false));

	m_joystick_btn_center = grab_gui_element<IGUIImage>(makeButtonDirect(joystick_center_id,
			recti(0, 0, m_button_size, m_button_size), false));

	for (const auto &[id, meta] : m_layout.layout) {
		if (!mayAddButton(id))
			continue;

		recti rect = m_layout.getRect(id, m_screensize, m_button_size, m_texturesource);
		if (id == toggle_chat_id)
			// Chat is shown by default, so chat_hide_btn.png is shown first.
			addToggleButton(m_buttons, id, "chat_hide_btn.png",
					"chat_show_btn.png", rect, true);
		else if (id == overflow_id)
			m_overflow_btn = grab_gui_element<IGUIImage>(
					makeButtonDirect(id, rect, true));
		else
			addButton(m_buttons, id, button_image_names[id], rect, true);
	}

	IGUIStaticText *background = m_guienv->addStaticText(L"",
			recti(v2s32(0, 0), dimension2du(m_screensize)));
	background->setBackgroundColor(video::SColor(140, 0, 0, 0));
	background->setVisible(false);
	m_overflow_bg = grab_gui_element<IGUIStaticText>(background);

	auto overflow_buttons = m_layout.getMissingButtons();
	overflow_buttons.erase(std::remove_if(
			overflow_buttons.begin(), overflow_buttons.end(),
			[&](touch_gui_button_id id) {
				// There would be no sense in adding the overflow button to the
				// overflow menu.
				return !mayAddButton(id) || id == overflow_id;
			}), overflow_buttons.end());

	layout_button_grid(m_screensize, m_texturesource, overflow_buttons,
			[&] (touch_gui_button_id id, v2s32 pos, recti rect) {
		if (id == toggle_chat_id)
			// Chat is shown by default, so chat_hide_btn.png is shown first.
			addToggleButton(m_overflow_buttons, id, "chat_hide_btn.png",
					"chat_show_btn.png", rect, false);
		else
			addButton(m_overflow_buttons, id, button_image_names[id], rect, false);

		IGUIStaticText *text = m_guienv->addStaticText(L"", recti());
		make_button_grid_title(text, id, pos, rect);
		text->setVisible(false);
		m_overflow_button_titles.push_back(grab_gui_element<IGUIStaticText>(text));

		rect.addInternalPoint(text->getRelativePosition().UpperLeftCorner);
		rect.addInternalPoint(text->getRelativePosition().LowerRightCorner);
		m_overflow_button_rects.push_back(rect);
	});

	m_status_text = grab_gui_element<IGUIStaticText>(
			m_guienv->addStaticText(L"", recti(), false, false));
	m_status_text->setVisible(false);

	// applyLayout can be called at any time, also e.g. while the overflow menu
	// is open, so this is necessary to restore correct visibility.
	updateVisibility();
}

TouchControls::~TouchControls()
{
	g_settings->deregisterAllChangedCallbacks(this);
	releaseAll();
}

bool TouchControls::mayAddButton(touch_gui_button_id id)
{
	assert(ButtonLayout::isButtonValid(id));
	assert(ButtonLayout::isButtonAllowed(id));
	// The overflow button doesn't need a keycode to be valid.
	return id == overflow_id || id_to_action(id) < KeyType::INTERNAL_ENUM_COUNT;
}

void TouchControls::addButton(std::vector<button_info> &buttons, touch_gui_button_id id,
		const std::string &image, const recti &rect, bool visible)
{
	IGUIImage *btn_gui_button = m_guienv->addImage(rect, nullptr, id);
	btn_gui_button->setVisible(visible);
	loadButtonTexture(btn_gui_button, image);

	button_info &btn = buttons.emplace_back();
	btn.id = id;
	btn.game_key = id_to_action(id);
	btn.gui_button = grab_gui_element<IGUIImage>(btn_gui_button);
}

void TouchControls::addToggleButton(std::vector<button_info> &buttons, touch_gui_button_id id,
		const std::string &image_1, const std::string &image_2, const recti &rect, bool visible)
{
	addButton(buttons, id, image_1, rect, visible);
	button_info &btn = buttons.back();
	btn.toggleable = button_info::FIRST_TEXTURE;
	btn.toggle_textures[0] = image_1;
	btn.toggle_textures[1] = image_2;
}

IGUIImage *TouchControls::makeButtonDirect(touch_gui_button_id id,
		const recti &rect, bool visible)
{
	IGUIImage *btn_gui_button = m_guienv->addImage(rect, nullptr, id);
	btn_gui_button->setVisible(visible);
	loadButtonTexture(btn_gui_button, button_image_names[id]);

	return btn_gui_button;
}

bool TouchControls::isHotbarButton(const SEvent &event)
{
	const v2s32 touch_pos = v2s32(event.TouchInput.X, event.TouchInput.Y);
	// check if hotbar item is pressed
	for (auto &[index, rect] : m_hotbar_rects) {
		if (rect.isPointInside(touch_pos)) {
			// We can't just emit a keypress event because the number keys
			// range from 1 to 9, but there may be more hotbar items.
			m_hotbar_selection = index;
			return true;
		}
	}
	return false;
}

std::optional<u16> TouchControls::getHotbarSelection()
{
	auto selection = m_hotbar_selection;
	m_hotbar_selection = std::nullopt;
	return selection;
}

bool TouchControls::isTouchableHudButton(const SEvent &event)
{
	const v2s32 touch_pos = v2s32(event.TouchInput.X, event.TouchInput.Y);
	for (auto &[name, rect] : m_touchable_hud_rects) {
		if (rect.isPointInside(touch_pos)) {
			m_touched_hud_element = name;
			return true;
		}
	}
	return false;
}

std::optional<std::string> TouchControls::getTouchedHudElement()
{
	auto touched = m_touched_hud_element;
	m_touched_hud_element = std::nullopt;
	return touched;
}

void TouchControls::handleReleaseEvent(size_t pointer_id)
{
	// By the way: Android reuses pointer IDs, so m_pointer_pos[pointer_id]
	// will be overwritten soon anyway.
	m_pointer_downpos.erase(pointer_id);
	m_pointer_pos.erase(pointer_id);

	// RTS toolbar button released: this is the "click"
	auto rts_btn = m_rts_button_pointers.find(pointer_id);
	if (rts_btn != m_rts_button_pointers.end()) {
		const size_t idx = rts_btn->second;
		m_rts_button_pointers.erase(rts_btn);
		if (idx < m_rts_buttons.size()) {
			m_rts_button_result = m_rts_buttons[idx].def.name;
			if (!m_rts_buttons[idx].def.action)
				m_rts_active_button = m_rts_buttons[idx].def.name;
		}
		refreshRtsButtonColors();
		return;
	}

	// handle buttons
	if (buttonsHandleRelease(m_buttons, pointer_id))
		return;
	if (buttonsHandleRelease(m_overflow_buttons, pointer_id))
		return;

	if (m_has_move_id && pointer_id == m_move_id && m_rts_mode && m_has_rts_second) {
		// The first finger of a pinch was lifted: the second one carries on
		// panning, but it must never count as a tap.
		m_move_id = m_rts_second_id;
		m_has_rts_second = false;
		m_move_has_really_moved = true;
		m_move_prevent_short_tap = true;
		m_tap_state = TapState::None;
	}

	else if (m_has_rts_second && pointer_id == m_rts_second_id) {
		m_has_rts_second = false;
	}

	else if (m_has_move_id && pointer_id == m_move_id) {
		// handle the point used for moving view
		m_has_move_id = false;

		if (m_rts_box_active) {
			// end of a selection box drag
			rtsBoxFinish();
			m_tap_state = TapState::None;
			return;
		}

		// If m_tap_state is already set to TapState::ShortTap, we must keep
		// that value. Otherwise, many short taps will be ignored if you tap
		// very fast.
		if (m_interaction_style != BUTTONS_CROSSHAIR &&
				!m_move_has_really_moved && !m_move_prevent_short_tap &&
				m_tap_state != TapState::LongTap) {
			m_tap_state = TapState::ShortTap;
		} else {
			m_tap_state = TapState::None;
		}
	}

	// handle joystick
	else if (m_has_joystick_id && pointer_id == m_joystick_id) {
		m_has_joystick_id = false;

		// reset joystick
		emitGameKeyEvent(KeyType::FORWARD, 0);
		emitGameKeyEvent(KeyType::BACKWARD, 0);
		emitGameKeyEvent(KeyType::LEFT, 0);
		emitGameKeyEvent(KeyType::RIGHT, 0);
		m_joystick_status_aux1 = false;
		applyJoystickStatus();

		updateVisibility();
	} else {
		infostream << "TouchControls::translateEvent released unknown button: "
				<< pointer_id << std::endl;
	}
}

void TouchControls::translateEvent(const SEvent &event)
{
	if (!m_visible) {
		infostream << "TouchControls::translateEvent got event but is not visible!"
				<< std::endl;
		return;
	}

	if (event.EventType != EET_TOUCH_INPUT_EVENT)
		return;

	const s32 half_button_size = m_button_size / 2.0f;
	const s32 fixed_joystick_range_sq = half_button_size * half_button_size * 3 * 3;
	const s32 X = event.TouchInput.X;
	const s32 Y = event.TouchInput.Y;
	const v2s32 touch_pos = v2s32(X, Y);
	const v2s32 fixed_joystick_center = v2s32(half_button_size * 5,
			m_screensize.Y - half_button_size * 5);
	const v2s32 dir_fixed = touch_pos - fixed_joystick_center;

	if (event.TouchInput.Event == ETIE_PRESSED_DOWN) {
		size_t pointer_id = event.TouchInput.ID;
		m_pointer_downpos[pointer_id] = touch_pos;
		m_pointer_pos[pointer_id] = touch_pos;

		bool prevent_short_tap = false;

		// RTS toolbar: big buttons at the bottom of the screen
		if (m_rts_mode) {
			for (size_t i = 0; i < m_rts_buttons.size(); i++) {
				if (m_rts_buttons[i].rect.isPointInside(touch_pos)) {
					m_rts_button_pointers[pointer_id] = i;
					refreshRtsButtonColors();
					return;
				}
			}
		}

		IGUIElement *element = m_guienv->getRootGUIElement()->getElementFromPoint(touch_pos);

		// handle overflow menu
		if (!m_overflow_open) {
			if (element == m_overflow_btn.get())  {
				toggleOverflowMenu();
				return;
			}
		} else {
			for (size_t i = 0; i < m_overflow_buttons.size(); i++) {
				if (m_overflow_button_rects[i].isPointInside(touch_pos)) {
					element = m_overflow_buttons[i].gui_button.get();
					break;
				}
			}

			if (buttonsHandlePress(m_overflow_buttons, pointer_id, element))
				return;

			toggleOverflowMenu();
			// refresh since visibility of buttons has changed
			element = m_guienv->getRootGUIElement()->getElementFromPoint(touch_pos);
			// continue processing, but avoid accidentally placing a node
			// when closing the overflow menu
			prevent_short_tap = true;
		}

		// handle buttons
		if (buttonsHandlePress(m_buttons, pointer_id, element))
			return;

		// handle hotbar
		if (isHotbarButton(event))
			// already handled in isHotbarButton()
			return;

		// handle mod-defined touchable HUD buttons
		if (isTouchableHudButton(event))
			// already handled in isTouchableHudButton()
			return;

		// Select joystick when joystick tapped (fixed joystick position) or
		// when left 1/3 of screen dragged (free joystick position)
		if (!m_rts_mode && ((m_fixed_joystick && dir_fixed.getLengthSQ() <= fixed_joystick_range_sq) ||
				(!m_fixed_joystick && X < m_screensize.X / 3.0f))) {
			// If we don't already have a starting point for joystick, make this the one.
			if (!m_has_joystick_id) {
				m_has_joystick_id           = true;
				m_joystick_id               = pointer_id;
				m_joystick_has_really_moved = false;

				updateVisibility();

				// If it's a fixed joystick, don't move the joystick "button".
				if (!m_fixed_joystick)
					m_joystick_btn_bg->setRelativePosition(
							touch_pos - half_button_size * 3);

				m_joystick_btn_center->setRelativePosition(
						touch_pos - half_button_size);
			}
		} else if (m_rts_mode && m_has_move_id && !m_has_rts_second) {
			// Second finger: pinch zoom. Cancel any tap of the first finger.
			rtsBoxCancel();
			m_has_rts_second = true;
			m_rts_second_id = pointer_id;
			m_move_has_really_moved = true;
			m_move_prevent_short_tap = true;
			m_tap_state = TapState::None;
		} else {
			// If we don't already have a moving point, make this the moving one.
			if (!m_has_move_id) {
				m_has_move_id              = true;
				m_move_id                  = pointer_id;
				m_move_has_really_moved    = false;
				m_move_downtime            = porting::getTimeMs();
				m_move_pos                 = touch_pos;
				m_had_move_id              = true;
				m_move_prevent_short_tap   = prevent_short_tap;

				// DON'T reset m_tap_state here, otherwise many short taps
				// will be ignored if you tap very fast.
			}
		}
	}
	else if (event.TouchInput.Event == ETIE_LEFT_UP) {
		verbosestream << "Up event for pointerid: " << event.TouchInput.ID << std::endl;
		handleReleaseEvent(event.TouchInput.ID);
	} else {
		assert(event.TouchInput.Event == ETIE_MOVED);

		if (!(m_has_joystick_id && m_fixed_joystick) &&
				m_pointer_pos[event.TouchInput.ID] == touch_pos)
			return;

		const v2s32 dir_free_original = touch_pos - m_pointer_downpos[event.TouchInput.ID];
		const v2s32 free_joystick_center = m_pointer_pos[event.TouchInput.ID];
		const v2s32 dir_free = touch_pos - free_joystick_center;

		const double touch_threshold_sq = m_touchscreen_threshold * m_touchscreen_threshold;

		if (m_has_move_id && event.TouchInput.ID == m_move_id) {
			m_move_pos = touch_pos;
			m_pointer_pos[event.TouchInput.ID] = touch_pos;

			if (dir_free_original.getLengthSQ() > touch_threshold_sq)
				m_move_has_really_moved = true;

			if (m_rts_mode) {
				// pan the RTS camera instead of turning the view
				rtsPointerMoved(event.TouchInput.ID, free_joystick_center, touch_pos);
			} else {
				// update camera_yaw and camera_pitch
				const double d = g_settings->getFloat("touchscreen_sensitivity", 0.001f, 10.0f)
						* 6.0f / RenderingEngine::getDisplayDensity();
				m_camera_yaw_change -= dir_free.X * d;
				m_camera_pitch_change += dir_free.Y * d;
			}
		}

		if (m_rts_mode && m_has_rts_second && event.TouchInput.ID == m_rts_second_id) {
			m_pointer_pos[event.TouchInput.ID] = touch_pos;
			rtsPointerMoved(event.TouchInput.ID, free_joystick_center, touch_pos);
		}

		if (m_has_joystick_id && event.TouchInput.ID == m_joystick_id) {
			v2s32 dir = dir_free;
			if (m_fixed_joystick)
				dir = dir_fixed;

			const bool inside_joystick = dir_fixed.getLengthSQ() <= fixed_joystick_range_sq;
			const double distance_sq = dir.getLengthSQ();

			if (m_joystick_has_really_moved || inside_joystick ||
					(!m_fixed_joystick && distance_sq > touch_threshold_sq)) {
				m_joystick_has_really_moved = true;

				const double distance = sqrt(distance_sq);
				m_joystick_status_aux1 = distance > (half_button_size * 3);
				float joystick_scale = 0.0f;
				if (distance > m_touchscreen_threshold) {
					joystick_scale = 1.0f / m_button_size;
				}

				float joystick_x = dir.X * joystick_scale;
				float joystick_y = dir.Y * joystick_scale;
				emitGameKeyEvent(KeyType::FORWARD, std::max(0.0f, -joystick_y));
				emitGameKeyEvent(KeyType::BACKWARD, std::max(0.0f, joystick_y));
				emitGameKeyEvent(KeyType::LEFT, std::max(0.0f, -joystick_x));
				emitGameKeyEvent(KeyType::RIGHT, std::max(0.0f, joystick_x));

				if (distance > m_button_size) {
					// move joystick "button"
					v2s32 new_offset = dir * m_button_size / distance - half_button_size;
					if (m_fixed_joystick)
						m_joystick_btn_center->setRelativePosition(
								fixed_joystick_center + new_offset);
					else
						m_joystick_btn_center->setRelativePosition(
								free_joystick_center + new_offset);
				} else {
					m_joystick_btn_center->setRelativePosition(
							touch_pos - half_button_size);
				}
			}
		}
	}
}

void TouchControls::rtsPointerMoved(size_t id, const v2s32 &prev, const v2s32 &now)
{
	const v2f a_old((f32)prev.X, (f32)prev.Y);
	const v2f a_new((f32)now.X, (f32)now.Y);

	if (m_rts_box_active && !m_has_rts_second && id == m_move_id) {
		m_rts_box_cur = now;
		rtsBoxUpdateGui();
		return;
	}

	if (!m_has_rts_second) {
		// One finger: drag the map, but only once the finger has really moved,
		// so that jittery taps do not shake the camera.
		if (m_move_has_really_moved)
			m_rts_pan += a_new - a_old;
		return;
	}

	// Two fingers: pinch to zoom and drag with the midpoint.
	const size_t other_id = (id == m_move_id) ? m_rts_second_id : m_move_id;
	auto it = m_pointer_pos.find(other_id);
	if (it == m_pointer_pos.end())
		return;
	const v2f other((f32)it->second.X, (f32)it->second.Y);

	const f32 d_old = a_old.getDistanceFrom(other);
	const f32 d_new = a_new.getDistanceFrom(other);
	if (d_old > 8.0f && d_new > 8.0f)
		m_rts_zoom_mul *= d_old / d_new;

	m_rts_pan += (a_new - a_old) * 0.5f;
}

void TouchControls::setRtsButtons(const std::vector<RtsButton> &buttons,
		const std::string &active)
{
	const bool same_defs = buttons == m_rts_button_defs;
	m_rts_active_button = active;
	if (same_defs) {
		refreshRtsButtonColors();
		return;
	}
	m_rts_button_defs = buttons;
	m_rts_button_pointers.clear();
	buildRtsButtons();
}

void TouchControls::buildRtsButtons()
{
	m_rts_buttons.clear();
	const size_t n = m_rts_button_defs.size();
	if (n == 0)
		return;

	// Finger sized buttons in rows at the bottom centre. The size is the
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

		RtsButtonGui b;
		b.def = m_rts_button_defs[i];
		b.rect = recti(x, y, x + size, y + size);
		IGUIImage *img = m_guienv->addImage(b.rect, nullptr, -1);
		img->setUseAlphaChannel(true);
		img->setVisible(m_visible && m_rts_mode);
		loadButtonTexture(img, b.def.image);
		b.image = grab_gui_element<IGUIImage>(img);
		m_rts_buttons.push_back(std::move(b));
	}
	refreshRtsButtonColors();
}

void TouchControls::refreshRtsButtonColors()
{
	std::vector<bool> pressed(m_rts_buttons.size(), false);
	for (const auto &[pointer, idx] : m_rts_button_pointers) {
		if (idx < pressed.size())
			pressed[idx] = true;
	}
	for (size_t i = 0; i < m_rts_buttons.size(); i++) {
		video::SColor c(235, 255, 255, 255);
		if (m_rts_buttons[i].def.name == m_rts_active_button)
			c = video::SColor(255, 150, 255, 150); // selected tool
		if (pressed[i])
			c = video::SColor(255, 170, 170, 170);  // finger down
		m_rts_buttons[i].image->setColor(c);
	}
}

void TouchControls::rtsBoxStart()
{
	m_rts_box_active = true;
	m_rts_box_start = m_move_pos;
	m_rts_box_cur = m_move_pos;
	rtsBoxUpdateGui();
	m_rts_box_gui->setVisible(true);
}

void TouchControls::rtsBoxUpdateGui()
{
	m_rts_box_gui->setRelativePosition(recti(
			std::min(m_rts_box_start.X, m_rts_box_cur.X),
			std::min(m_rts_box_start.Y, m_rts_box_cur.Y),
			std::max(m_rts_box_start.X, m_rts_box_cur.X) + 1,
			std::max(m_rts_box_start.Y, m_rts_box_cur.Y) + 1));
}

void TouchControls::rtsBoxCancel()
{
	m_rts_box_active = false;
	m_rts_box_gui->setVisible(false);
}

void TouchControls::rtsBoxFinish()
{
	const v2s32 start = m_rts_box_start;
	const v2s32 end = m_rts_box_cur;
	rtsBoxCancel();

	const v2s32 d = end - start;
	if (d.getLength() > m_touchscreen_threshold * 1.5) {
		m_rts_box_result = std::make_pair(start, end);
		return;
	}

	// Held, but barely moved: this was an ordinary long tap after all
	const u64 now = porting::getTimeMs();
	if (m_last_mode == LONG_DIG_SHORT_PLACE)
		m_dig_pressed_until = now + SIMULATED_CLICK_DURATION_MS;
	else
		m_place_pressed_until = now + SIMULATED_CLICK_DURATION_MS;
}

void TouchControls::setRtsMode(bool enabled)
{
	if (m_rts_mode == enabled)
		return;

	releaseAll();
	m_rts_button_pointers.clear();
	rtsBoxCancel();
	m_rts_box_result.reset();
	m_rts_mode = enabled;
	m_has_rts_second = false;
	m_rts_pan = v2f(0.0f, 0.0f);
	m_rts_zoom_mul = 1.0f;
	m_overflow_open = false;
	m_has_move_id = false;
	m_tap_state = TapState::None;

	if (enabled)
		m_interaction_style = TAP;
	else
		readSettings(); // restores the user's interaction style (and the layout)

	updateVisibility();
}

void TouchControls::applyJoystickStatus()
{
	if (m_joystick_triggers_aux1) {
		auto key = id_to_action(aux1_id);
		emitGameKeyEvent(key, false);
		if (m_joystick_status_aux1)
			emitGameKeyEvent(key, true);
	}
}

void TouchControls::step(float dtime)
{
	v2u32 screensize = m_device->getVideoDriver()->getScreenSize();
	s32 button_size = ButtonLayout::getButtonSize(screensize);

	if (m_screensize != screensize || m_button_size != button_size) {
		m_screensize = screensize;
		m_button_size = button_size;
		applyLayout(m_layout);
		buildRtsButtons();
	}

	// simulate keyboard repeats
	buttonsStep(m_buttons, dtime);
	buttonsStep(m_overflow_buttons, dtime);

	// joystick
	applyJoystickStatus();

	// if a new placed pointer isn't moved for some time start digging
	if (m_interaction_style != BUTTONS_CROSSHAIR &&
			m_has_move_id && !m_move_has_really_moved &&
			!m_rts_box_active &&
			m_tap_state == TapState::None) {
		u64 delta = porting::getDeltaMs(m_move_downtime, porting::getTimeMs());

		if (delta > m_long_tap_delay) {
			if (m_rts_mode && !m_has_rts_second)
				rtsBoxStart(); // long press + drag = selection box
			else
				m_tap_state = TapState::LongTap;
		}
	}

	// Update the shootline.
	// Since not only the pointer position, but also the player position and
	// thus the camera position can change, it doesn't suffice to update the
	// shootline when a touch event occurs.
	// Only updating when m_has_move_id means that the shootline will stay at
	// its last in-world position when the player doesn't need it.
	if (m_interaction_style == TAP && (m_has_move_id || m_had_move_id)) {
		m_shootline = m_device
				->getSceneManager()
				->getSceneCollisionManager()
				->getRayFromScreenCoordinates(m_move_pos);
	}
	m_had_move_id = false;
}

void TouchControls::resetHotbarRects()
{
	m_hotbar_rects.clear();
}

void TouchControls::registerHotbarRect(u16 index, const recti &rect)
{
	m_hotbar_rects[index] = rect;
}

void TouchControls::resetTouchableHudRects()
{
	m_touchable_hud_rects.clear();
}

void TouchControls::registerTouchableHudRect(const std::string &name, const recti &rect)
{
	m_touchable_hud_rects[name] = rect;
}

void TouchControls::setVisible(bool visible)
{
	if (m_visible == visible)
		return;

	m_visible = visible;
	if (!visible) {
		releaseAll();
		m_overflow_open = false;
	}
	updateVisibility();
}

void TouchControls::toggleOverflowMenu()
{
	// no releaseAll here so that you can e.g. continue holding the joystick
	// while the overflow menu is open
	m_overflow_open = !m_overflow_open;
	updateVisibility();
}

void TouchControls::updateVisibility()
{
	bool regular_visible = m_visible && !m_overflow_open && !m_rts_mode;
	for (auto &button : m_buttons)
		button.gui_button->setVisible(regular_visible);
	m_overflow_btn->setVisible(regular_visible);

	m_joystick_btn_off->setVisible(regular_visible && !m_has_joystick_id);
	m_joystick_btn_bg->setVisible(regular_visible && m_has_joystick_id);
	m_joystick_btn_center->setVisible(regular_visible && m_has_joystick_id);

	bool overflow_visible = m_visible && m_overflow_open && !m_rts_mode;
	m_overflow_bg->setVisible(overflow_visible);
	for (auto &button : m_overflow_buttons)
		button.gui_button->setVisible(overflow_visible);
	for (auto &text : m_overflow_button_titles)
		text->setVisible(overflow_visible);

	for (auto &b : m_rts_buttons)
		b.image->setVisible(m_visible && m_rts_mode);
}

void TouchControls::releaseAll()
{
	m_rts_button_pointers.clear(); // no clicks when everything is force-released
	while (!m_pointer_pos.empty())
		handleReleaseEvent(m_pointer_pos.begin()->first);

	// Release those manually too since the change initiated by
	// handleReleaseEvent will only be applied later by applyContextControls.
	if (m_dig_pressed) {
		emitGameKeyEvent(id_to_action(dig_id), false);
		m_dig_pressed = false;
	}
	if (m_place_pressed) {
		emitGameKeyEvent(id_to_action(place_id), false);
		m_place_pressed = false;
	}
}

void TouchControls::hide()
{
	setVisible(false);
}

void TouchControls::show()
{
	setVisible(true);
}

void TouchControls::applyContextControls(const TouchInteractionMode &mode)
{
	if (m_interaction_style == BUTTONS_CROSSHAIR)
		return;

	// Since the pointed thing has already been determined when this function
	// is called, we cannot use this function to update the shootline.

	sanity_check(mode != TouchInteractionMode_USER);
	u64 now = porting::getTimeMs();
	bool target_dig_pressed = false;
	bool target_place_pressed = false;

	// If the meanings of short and long taps have been swapped, abort any ongoing
	// short taps because they would do something else than the player expected.
	// Long taps don't need this, they're adjusted to the swapped meanings instead.
	if (mode != m_last_mode) {
		m_dig_pressed_until = 0;
		m_place_pressed_until = 0;
	}
	m_last_mode = mode;

	switch (m_tap_state) {
	case TapState::ShortTap:
		if (mode == SHORT_DIG_LONG_PLACE) {
			if (!m_dig_pressed) {
				// The button isn't currently pressed, we can press it.
				m_dig_pressed_until = now + SIMULATED_CLICK_DURATION_MS;
				// We're done with this short tap.
				m_tap_state = TapState::None;
			}  else {
				// The button is already pressed, perhaps due to another short tap.
				// Release it now, press it again during the next client step.
				// We can't release and press during the same client step because
				// the digging code simply ignores that.
				m_dig_pressed_until = 0;
			}
		} else {
			if (!m_place_pressed) {
				// The button isn't currently pressed, we can press it.
				m_place_pressed_until = now + SIMULATED_CLICK_DURATION_MS;
				// We're done with this short tap.
				m_tap_state = TapState::None;
			}  else {
				// The button is already pressed, perhaps due to another short tap.
				// Release it now, press it again during the next client step.
				// We can't release and press during the same client step because
				// the digging code simply ignores that.
				m_place_pressed_until = 0;
			}
		}
		break;

	case TapState::LongTap:
		if (mode == SHORT_DIG_LONG_PLACE)
			target_place_pressed = true;
		else
			target_dig_pressed = true;
		break;

	case TapState::None:
		break;
	}

	// Apply short taps.
	target_dig_pressed |= now < m_dig_pressed_until;
	target_place_pressed |= now < m_place_pressed_until;

	if (target_dig_pressed && !m_dig_pressed) {
		emitGameKeyEvent(id_to_action(dig_id), true);
		m_dig_pressed = true;

	} else if (!target_dig_pressed && m_dig_pressed) {
		emitGameKeyEvent(id_to_action(dig_id), false);
		m_dig_pressed = false;
	}

	if (target_place_pressed && !m_place_pressed) {
		emitGameKeyEvent(id_to_action(place_id), true);
		m_place_pressed = true;

	} else if (!target_place_pressed && m_place_pressed) {
		emitGameKeyEvent(id_to_action(place_id), false);
		m_place_pressed = false;
	}
}
