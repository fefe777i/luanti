// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "irr_v2d.h"
#include <IGUIElement.h>
#include <functional>
#include <map>
#include <vector>

/*
	pan_zoom_container: a clipped area whose content can be dragged in ANY
	direction with a finger (or the mouse) and zoomed with two fingers (or the
	mouse wheel). There are no scrollbars.

	While a gesture is going on the content is transformed locally (smooth,
	no network round trip). When the gesture ends the transformation is
	reported through the callback and sent to the server as the field value

		"PZ:<scale>,<ux>,<uy>"

	which means: a point (x, y) of the content, measured from the container's
	top-left corner in formspec units, is now at (scale*x + ux, scale*y + uy).
	The server then redraws the content with its new view.
*/
class GUIPanZoom : public gui::IGUIElement
{
public:
	GUIPanZoom(gui::IGUIEnvironment *env, gui::IGUIElement *parent, s32 id,
			const core::rect<s32> &rectangle, f32 unit_px, f32 zoom,
			f32 min_zoom, f32 max_zoom);

	// scale, ux, uy (in formspec units)
	using GestureEnd = std::function<void(f32, f32, f32)>;
	void setGestureEndCallback(GestureEnd cb) { m_on_end = std::move(cb); }

	// A tap (press and release without dragging) at (x, y) formspec units
	// from the container's top-left corner.
	using Tap = std::function<void(f32, f32)>;
	void setTapCallback(Tap cb) { m_on_tap = std::move(cb); }

	bool OnEvent(const SEvent &event) override;

	// Raw touch events (before they are turned into mouse events).
	// Returns true if the event was consumed (pinch gesture).
	bool handleTouch(const SEvent &event);

private:
	void beginGesture();
	void endGesture();
	void applyTransform();
	f32 clampScale(f32 total) const;
	v2s32 local(v2s32 p) const
	{
		return p - AbsoluteRect.UpperLeftCorner;
	}

	f32 m_unit_px;
	f32 m_zoom, m_min_zoom, m_max_zoom;
	GestureEnd m_on_end;
	Tap m_on_tap;

	// content transform of the current gesture: x' = m_scale * x + m_u
	bool m_gesture = false;
	f32 m_scale = 1.0f;
	v2f32 m_u;
	std::vector<core::rect<s32>> m_base; // children's rectangles at the start
	std::vector<size_t> m_anchor;

	// single pointer
	bool m_pressed = false;
	v2s32 m_press_pos, m_last_pos;

	// fingers currently touching the screen
	std::map<size_t, v2s32> m_touches;
	bool m_pinching = false;
	f32 m_pinch_dist0 = 1.0f;
	v2f32 m_pinch_c0;
	f32 m_pinch_scale0 = 1.0f;
	v2f32 m_pinch_u0;
};
