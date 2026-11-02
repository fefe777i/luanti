// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "guiPanZoom.h"
#include "guiBox.h"
#include <IGUIEnvironment.h>
#include <algorithm>
#include <cmath>

GUIPanZoom::GUIPanZoom(gui::IGUIEnvironment *env, gui::IGUIElement *parent, s32 id,
		const core::rect<s32> &rectangle, f32 unit_px, f32 zoom, f32 min_zoom,
		f32 max_zoom) :
	gui::IGUIElement(gui::EGUIET_ELEMENT, env, parent, id, rectangle),
	m_unit_px(unit_px > 0.0f ? unit_px : 1.0f),
	m_zoom(zoom > 0.0f ? zoom : 1.0f),
	m_min_zoom(min_zoom > 0.0f ? min_zoom : 0.1f),
	m_max_zoom(max_zoom >= m_min_zoom ? max_zoom : 10.0f)
{
}

f32 GUIPanZoom::clampScale(f32 total) const
{
	// the content is drawn at zoom m_zoom: keep m_zoom * total in range
	return std::clamp(total, m_min_zoom / m_zoom, m_max_zoom / m_zoom);
}

void GUIPanZoom::beginGesture()
{
	m_gesture = true;
	m_scale = 1.0f;
	m_u = v2f32(0.0f, 0.0f);
	m_base.clear();
	for (gui::IGUIElement *child : Children)
		m_base.push_back(child->getRelativePosition());
	// every non-box element is attached to the biggest non-box element
	// that contains its centre (its card); boxes are not attached
	const size_t cnt = m_base.size();
	std::vector<bool> is_box;
	for (gui::IGUIElement *child : Children)
		is_box.push_back(dynamic_cast<GUIBox *>(child) != nullptr);
	m_anchor.assign(cnt, 0);
	for (size_t a = 0; a < cnt; a++) {
		m_anchor[a] = a;
		if (is_box[a])
			continue;
		const core::rect<s32> &ra = m_base[a];
		v2s32 c((ra.UpperLeftCorner.X + ra.LowerRightCorner.X) / 2,
				(ra.UpperLeftCorner.Y + ra.LowerRightCorner.Y) / 2);
		s64 best = (s64)ra.getWidth() * ra.getHeight();
		for (size_t b = 0; b < cnt; b++) {
			if (b == a || is_box[b])
				continue;
			const core::rect<s32> &rb = m_base[b];
			s64 area = (s64)rb.getWidth() * rb.getHeight();
			if (area > best && rb.isPointInside(c)) {
				best = area;
				m_anchor[a] = b;
			}
		}
	}
}

void GUIPanZoom::applyTransform()
{
	size_t i = 0;
	for (gui::IGUIElement *child : Children) {
		if (i >= m_base.size())
			break;
		const size_t idx = i++;
		const core::rect<s32> &r = m_base[idx];
		core::rect<s32> n;
		if (dynamic_cast<GUIBox *>(child)) {
			// boxes (links between nodes) are scaled together with the content
			n = core::rect<s32>(
					(s32)std::lround(m_scale * r.UpperLeftCorner.X + m_u.X),
					(s32)std::lround(m_scale * r.UpperLeftCorner.Y + m_u.Y),
					(s32)std::lround(m_scale * r.LowerRightCorner.X + m_u.X),
					(s32)std::lround(m_scale * r.LowerRightCorner.Y + m_u.Y));
		} else {
			// Everything else keeps its size. Only the centre of its "card"
			// (the biggest element it lies in) moves, the element keeps its
			// offset from that centre, so a card never falls apart.
			const core::rect<s32> &ra = m_base[m_anchor[idx]];
			f32 acx = (ra.UpperLeftCorner.X + ra.LowerRightCorner.X) * 0.5f;
			f32 acy = (ra.UpperLeftCorner.Y + ra.LowerRightCorner.Y) * 0.5f;
			f32 ccx = (r.UpperLeftCorner.X + r.LowerRightCorner.X) * 0.5f;
			f32 ccy = (r.UpperLeftCorner.Y + r.LowerRightCorner.Y) * 0.5f;
			f32 cx = m_scale * acx + m_u.X + (ccx - acx);
			f32 cy = m_scale * acy + m_u.Y + (ccy - acy);
			s32 w = r.getWidth(), h = r.getHeight();
			s32 x0 = (s32)std::lround(cx - w * 0.5f);
			s32 y0 = (s32)std::lround(cy - h * 0.5f);
			n = core::rect<s32>(x0, y0, x0 + w, y0 + h);
		}
		child->setRelativePosition(n);
	}
}

void GUIPanZoom::endGesture()
{
	if (!m_gesture)
		return;
	m_gesture = false;
	m_pinching = false;
	m_pressed = false;
	if (m_scale == 1.0f && m_u.X == 0.0f && m_u.Y == 0.0f)
		return;
	if (m_on_end)
		m_on_end(m_scale, m_u.X / m_unit_px, m_u.Y / m_unit_px);
}

bool GUIPanZoom::OnEvent(const SEvent &event)
{
	if (event.EventType != EET_MOUSE_INPUT_EVENT)
		return IGUIElement::OnEvent(event);

	const auto &m = event.MouseInput;
	const v2s32 p(m.X, m.Y);
	const s32 DRAG_THRESHOLD_PX = 10;

	switch (m.Event) {
	case EMIE_LMOUSE_PRESSED_DOWN:
		m_pressed = true;
		m_press_pos = m_last_pos = p;
		break;

	case EMIE_MOUSE_MOVED: {
		if (!m.isLeftPressed() || m_pinching)
			break;
		if (!m_pressed) {
			// the press went to a previous version of this formspec
			m_pressed = true;
			m_press_pos = m_last_pos = p;
		}
		if (!m_gesture) {
			s32 dx = p.X - m_press_pos.X, dy = p.Y - m_press_pos.Y;
			if (std::abs(dx) <= DRAG_THRESHOLD_PX && std::abs(dy) <= DRAG_THRESHOLD_PX)
				break;
			beginGesture();
			m_last_pos = m_press_pos; // include the distance covered so far
		}
		m_u.X += p.X - m_last_pos.X;
		m_u.Y += p.Y - m_last_pos.Y;
		m_last_pos = p;
		applyTransform();
		return true;
	}

	case EMIE_LMOUSE_LEFT_UP:
		if (m_gesture) {
			endGesture();
			return true; // do not also click the element under the finger
		}
		if (m_pressed && m_on_tap && AbsoluteClippingRect.isPointInside(p)) {
			m_pressed = false;
			v2s32 lp = local(p);
			m_on_tap(lp.X / m_unit_px, lp.Y / m_unit_px);
			return true;
		}
		m_pressed = false;
		break;

	case EMIE_MOUSE_WHEEL: {
		if (!AbsoluteClippingRect.isPointInside(p))
			break;
		if (m_gesture)
			endGesture();
		beginGesture();
		f32 s = std::pow(1.15f, m.Wheel);
		f32 ns = clampScale(s) ;
		v2f32 pivot((f32)local(p).X, (f32)local(p).Y);
		m_scale = ns;
		m_u = pivot - pivot * ns;   // zoom around the cursor
		applyTransform();
		endGesture();
		return true;
	}

	default:
		break;
	}
	return IGUIElement::OnEvent(event);
}

bool GUIPanZoom::handleTouch(const SEvent &event)
{
	const auto &t = event.TouchInput;
	const v2s32 p(t.X, t.Y);

	switch (t.Event) {
	case ETIE_PRESSED_DOWN:
		m_touches[t.ID] = p;
		if (m_touches.size() == 2 && m_pressed && !m_pinching) {
			// a second finger while the first one is on us: pinch
			if (!m_gesture)
				beginGesture();
			auto it = m_touches.begin();
			v2s32 a = local(it->second);
			++it;
			v2s32 b = local(it->second);
			m_pinch_dist0 = std::max(1.0f, (f32)(a - b).getLength());
			m_pinch_c0 = v2f32((a.X + b.X) * 0.5f, (a.Y + b.Y) * 0.5f);
			m_pinch_scale0 = m_scale;
			m_pinch_u0 = m_u;
			m_pinching = true;
			return true;
		}
		return false;

	case ETIE_MOVED:
		m_touches[t.ID] = p;
		if (m_pinching && m_touches.size() >= 2) {
			auto it = m_touches.begin();
			v2s32 a = local(it->second);
			++it;
			v2s32 b = local(it->second);
			f32 dist = std::max(1.0f, (f32)(a - b).getLength());
			v2f32 c1((a.X + b.X) * 0.5f, (a.Y + b.Y) * 0.5f);
			f32 total = clampScale(m_pinch_scale0 * dist / m_pinch_dist0);
			f32 s = total / m_pinch_scale0;
			m_scale = total;
			m_u = c1 + (m_pinch_u0 - m_pinch_c0) * s;
			applyTransform();
			return true;
		}
		return false;

	case ETIE_LEFT_UP:
		m_touches.erase(t.ID);
		if (m_pinching) {
			m_pinching = false;
			if (m_touches.empty()) {
				endGesture();
			} else {
				// the remaining finger keeps dragging
				m_last_pos = m_touches.begin()->second;
				m_press_pos = m_last_pos;
			}
			return true;
		}
		return false;

	default:
		return false;
	}
}
