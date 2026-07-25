// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2020 DS

#include "guiScrollContainer.h"
#include <IGUIEnvironment.h>

GUIScrollContainer::GUIScrollContainer(gui::IGUIEnvironment *env,
		gui::IGUIElement *parent, s32 id, const core::rect<s32> &rectangle,
		const std::string &orientation, f32 scrollfactor) :
		gui::IGUIElement(gui::EGUIET_ELEMENT, env, parent, id, rectangle),
		m_scrollbar(nullptr), m_scrollfactor(scrollfactor)
{
	if (orientation == "vertical")
		m_orientation = VERTICAL;
	else if (orientation == "horizontal")
		m_orientation = HORIZONTAL;
	else
		m_orientation = UNDEFINED;
}

bool GUIScrollContainer::OnEvent(const SEvent &event)
{
	if (event.EventType == EET_MOUSE_INPUT_EVENT &&
			event.MouseInput.Event == EMIE_MOUSE_WHEEL &&
			!event.MouseInput.isLeftPressed() && m_scrollbar) {
		Environment->setFocus(m_scrollbar);
		bool retval = m_scrollbar->OnEvent(event);

		// a hacky fix for updating the hovering and co.
		IGUIElement *hovered_elem = getElementFromPoint(core::position2d<s32>(
				event.MouseInput.X, event.MouseInput.Y));
		SEvent mov_event = event;
		mov_event.MouseInput.Event = EMIE_MOUSE_MOVED;
		Environment->postEventFromUser(mov_event);
		if (hovered_elem)
			hovered_elem->OnEvent(mov_event);

		return retval;
	}

	// Drag-to-scroll: lets a finger (or mouse) drag the container's
	// content directly, instead of only being able to grab the thin
	// scrollbar handle. A small movement threshold distinguishes a
	// drag gesture from a simple tap/click meant for a child element.
	if (event.EventType == EET_MOUSE_INPUT_EVENT && m_scrollbar &&
			m_orientation != UNDEFINED) {
		const s32 DRAG_THRESHOLD_PX = 10;
		s32 axis_pos = (m_orientation == VERTICAL) ?
				event.MouseInput.Y : event.MouseInput.X;

		if (event.MouseInput.Event == EMIE_LMOUSE_PRESSED_DOWN) {
			m_drag_active = false;
			m_drag_start_pos = axis_pos;
			m_drag_start_scrollbar_pos = m_scrollbar->getPos();
		} else if (event.MouseInput.Event == EMIE_LMOUSE_LEFT_UP) {
			if (m_drag_active) {
				m_drag_active = false;
				return true; // swallow the release so it doesn't also click a child
			}
		} else if (event.MouseInput.Event == EMIE_MOUSE_MOVED &&
				event.MouseInput.isLeftPressed()) {
			s32 delta_px = axis_pos - m_drag_start_pos;
			s32 abs_delta = delta_px < 0 ? -delta_px : delta_px;
			if (!m_drag_active && abs_delta > DRAG_THRESHOLD_PX)
				m_drag_active = true;

			if (m_drag_active) {
				f32 factor = (m_scrollfactor != 0.0f) ? m_scrollfactor : 1.0f;
				s32 delta_scroll = (s32)(delta_px / factor);
				m_scrollbar->setPos(m_drag_start_scrollbar_pos - delta_scroll);
				updateScrolling();
				return true;
			}
		}
	}

	return IGUIElement::OnEvent(event);
}

void GUIScrollContainer::draw()
{
	if (isVisible()) {
		for (auto child : Children)
			if (child->isNotClipped() ||
					AbsoluteClippingRect.isRectCollided(
							child->getAbsolutePosition()))
				child->draw();
	}
}

void GUIScrollContainer::setScrollBar(GUIScrollBar *scrollbar)
{
	m_scrollbar = scrollbar;

	if (m_scrollbar && m_content_padding_px.has_value() && m_scrollfactor != 0.0f) {
		// Set the scrollbar max value based on the content size.

		// Get content size based on elements
		core::rect<s32> size;
		for (gui::IGUIElement *e : Children) {
			core::rect<s32> abs_rect = e->getAbsolutePosition();
			size.addInternalPoint(abs_rect.LowerRightCorner);
		}

		s32 visible_content_px = (
			m_orientation == VERTICAL
				? AbsoluteClippingRect.getHeight()
				: AbsoluteClippingRect.getWidth()
		);

		s32 total_content_px = *m_content_padding_px + (
			m_orientation == VERTICAL
				? (size.LowerRightCorner.Y - AbsoluteClippingRect.UpperLeftCorner.Y)
				: (size.LowerRightCorner.X - AbsoluteClippingRect.UpperLeftCorner.X)
		);

		s32 hidden_content_px = std::max<s32>(0, total_content_px - visible_content_px);
		m_scrollbar->setMin(0);
		m_scrollbar->setMax(std::ceil(hidden_content_px / std::fabs(m_scrollfactor)));

		// Note: generally, the scrollbar has the same size as the scroll container.
		// However, in case it isn't, proportional adjustments are needed.
		s32 scrollbar_px = (
			m_scrollbar->isHorizontal()
				? m_scrollbar->getRelativePosition().getWidth()
				: m_scrollbar->getRelativePosition().getHeight()
		);

		m_scrollbar->setPageSize((total_content_px * scrollbar_px) / visible_content_px);
	}
}

void GUIScrollContainer::updateScrolling()
{
	s32 pos = m_scrollbar->getPos();
	core::rect<s32> rect = getRelativePosition();

	if (m_orientation == VERTICAL)
		rect.UpperLeftCorner.Y = pos * m_scrollfactor;
	else if (m_orientation == HORIZONTAL)
		rect.UpperLeftCorner.X = pos * m_scrollfactor;

	setRelativePosition(rect);
}
