/*
   CGUITTFont FreeType class for Irrlicht
   Copyright (c) 2009-2010 John Norman
   with changes from Luanti contributors:
   Copyright (c) 2016 Nathanaëlle Courant
   Copyright (c) 2023 Caleb Butler

   This software is provided 'as-is', without any express or implied
   warranty. In no event will the authors be held liable for any
   damages arising from the use of this software.

   Permission is granted to anyone to use this software for any
   purpose, including commercial applications, and to alter it and
   redistribute it freely, subject to the following restrictions:

   1. The origin of this software must not be misrepresented; you
      must not claim that you wrote the original software. If you use
      this software in a product, an acknowledgment in the product
      documentation would be appreciated but is not required.

   2. Altered source versions must be plainly marked as such, and
      must not be misrepresented as being the original software.

   3. This notice may not be removed or altered from any source
      distribution.

   The original version of this class can be located at:
   http://irrlicht.suckerfreegames.com/

   John Norman
   john@suckerfreegames.com
*/

#include "CGUITTFont.h"

#include "log.h"
#include "debug.h"
#include "util/basic_macros.h"
#include "util/enriched_string.h"

#include "IGUIEnvironment.h"
#include "IImage.h"
#include "IVideoDriver.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cwchar>
#include <iostream>


namespace gui
{

namespace
{
	// Color bitmap fonts (emoji) are drawn slightly smaller than their nominal
	// size so that they fit into the line height of the text.
	constexpr float COLOR_BITMAP_SIZE_FACTOR = 0.9f;

	//! Characters that are part of emoji sequences but have no visual
	//! representation on their own (we do no text shaping):
	//! variation selectors, zero width (non-)joiners and tag characters.
	inline bool isZeroWidthEmojiControl(char32_t c)
	{
		return (c >= 0xFE00 && c <= 0xFE0F) || c == 0x200B || c == 0x200C ||
			c == 0x200D || c == 0x2060 || (c >= 0xE0020 && c <= 0xE007F);
	}

	//! Converts a single code point to a wide string (surrogate pairs if needed)
	core::stringw charToWideString(char32_t c)
	{
		core::stringw s;
		if (sizeof(wchar_t) == 2 && c > 0xFFFF) {
			c -= 0x10000;
			s += (wchar_t)(0xD800 + (c >> 10));
			s += (wchar_t)(0xDC00 + (c & 0x3FF));
		} else {
			s += (wchar_t)c;
		}
		return s;
	}
}

FT_Library SGUITTFace::freetype_library = nullptr;
size_t SGUITTFace::n_faces = 0;

FT_Library SGUITTFace::getFreeTypeLibrary()
{
	if (freetype_library)
		return freetype_library;
	FT_Library ft;
	if (FT_Init_FreeType(&ft))
		FATAL_ERROR("initializing freetype failed");
	freetype_library = ft;
	return freetype_library;
}

SGUITTFace::SGUITTFace(std::string &&buffer) : face_buffer(std::move(buffer))
{
	memset((void*)&face, 0, sizeof(FT_Face));
	n_faces++;
}

SGUITTFace::~SGUITTFace()
{
	FT_Done_Face(face);
	n_faces--;
	// If there are no more faces referenced by FreeType, clean up.
	if (n_faces == 0) {
		assert(freetype_library);
		FT_Done_FreeType(freetype_library);
		freetype_library = nullptr;
	}
}

SGUITTFace* SGUITTFace::createFace(std::string &&buffer)
{
	irr_ptr<SGUITTFace> face(new SGUITTFace(std::move(buffer)));
	auto ft = getFreeTypeLibrary();
	if (!ft)
		return nullptr;
	bool ok = FT_New_Memory_Face(ft,
			reinterpret_cast<const FT_Byte*>(face->face_buffer.data()),
			face->face_buffer.size(), 0, &face->face) == 0;
	return ok ? face.release() : nullptr;
}

SGUITTFace* SGUITTFace::loadFace(const io::path &filename)
{
	irr_ptr<SGUITTFace> face(new SGUITTFace(""));
	auto ft = getFreeTypeLibrary();
	if (!ft)
		return nullptr;
	// Prefer FT_New_Face because it doesn't require loading everything
	// to memory.
	bool ok = FT_New_Face(ft, filename.c_str(), 0, &face->face) == 0;
	return ok ? face.release() : nullptr;
}


//////////////////////

//! Wrapper struct for a preloaded glyph
struct SGUITTGlyphPending {
	SGUITTGlyphPending(const SGUITTGlyph *glyph, video::IImage *surface) noexcept :
		glyph(glyph), surface(surface)
	{}
	~SGUITTGlyphPending()
	{
		if (surface)
			surface->drop();
	}

	DISABLE_CLASS_COPY(SGUITTGlyphPending)

	SGUITTGlyphPending(SGUITTGlyphPending &&other) noexcept :
		glyph(other.glyph), surface(other.surface)
	{
		other.surface = nullptr;
	}

	const SGUITTGlyph *glyph;
	video::IImage *surface;
};


//////////////////////

//! Holds a sheet of glyphs.
class CGUITTGlyphPage
{
	public:
		CGUITTGlyphPage(video::IVideoDriver *Driver, const io::path &texture_name) :
			texture(0), available_slots(0), used_slots(0),
			driver(Driver), name(texture_name)
		{}
		~CGUITTGlyphPage()
		{
			if (texture)
				driver->removeTexture(texture);
		}

		//! Create the actual page texture,
		bool createPageTexture(u8 pixel_mode, core::dimension2du texture_size);

		//! Add the glyph to a list of glyphs to be paged.
		//! This collection will be cleared after updateTexture is called.
		void pushGlyphToBePaged(const SGUITTGlyph *glyph, video::IImage *surface)
		{
			if (!glyph || !surface)
				return;
			glyph_to_be_paged.emplace_back(glyph, surface);
		}

		inline bool isDirty() const
		{
			return !glyph_to_be_paged.empty();
		}

		//! Updates the texture atlas with new glyphs.
		void updateTexture();

		video::ITexture* texture;
		u32 available_slots;
		u32 used_slots;

		std::vector<core::vector2di> render_positions;
		std::vector<core::recti> render_source_rects;
		std::vector<video::SColor> render_colors;

	private:
		std::vector<SGUITTGlyphPending> glyph_to_be_paged;
		video::IVideoDriver* driver;
		io::path name;
};


bool CGUITTGlyphPage::createPageTexture(const u8 pixel_mode,
	const core::dimension2du texture_size)
{
	if (texture)
		return false;

	bool flgmip = driver->getTextureCreationFlag(video::ETCF_CREATE_MIP_MAPS);
	driver->setTextureCreationFlag(video::ETCF_CREATE_MIP_MAPS, false);
	bool flgcpy = driver->getTextureCreationFlag(video::ETCF_ALLOW_MEMORY_COPY);
	driver->setTextureCreationFlag(video::ETCF_ALLOW_MEMORY_COPY, true);

	// Create texture
	switch (pixel_mode) {
		case FT_PIXEL_MODE_MONO:
			texture = driver->addTexture(texture_size, name, video::ECF_A1R5G5B5);
			break;
		case FT_PIXEL_MODE_GRAY:
		default:
			texture = driver->addTexture(texture_size, name, video::ECF_A8R8G8B8);
			break;
	}

	// Restore texture creation flags
	driver->setTextureCreationFlag(video::ETCF_CREATE_MIP_MAPS, flgmip);
	driver->setTextureCreationFlag(video::ETCF_ALLOW_MEMORY_COPY, flgcpy);

	return texture ? true : false;
}

//! Updates the texture atlas with new glyphs.
void CGUITTGlyphPage::updateTexture()
{
	if (!isDirty())
		return;

	void *ptr = texture->lock();
	if (!ptr)
		return;

	video::ECOLOR_FORMAT format = texture->getColorFormat();
	core::dimension2du size = texture->getOriginalSize();
	video::IImage* pageholder = driver->createImageFromData(format, size, ptr, true, false);

	for (auto &it : glyph_to_be_paged)
		it.surface->copyTo(pageholder, it.glyph->source_rect.UpperLeftCorner);

	pageholder->drop();
	texture->unlock();
	glyph_to_be_paged.clear();
}


//////////////////////

video::IImage* SGUITTGlyph::createGlyphImage(const FT_Bitmap& bits, video::IVideoDriver* driver) const
{
	// Make sure our casts to s32 in the loops below will not cause problems
	if (bits.rows > INT32_MAX || bits.width > INT32_MAX)
		FATAL_ERROR("Insane font glyph size");

	// Determine what our texture size should be.
	// Add 1 because textures are inclusive-exclusive.
	core::dimension2du d(bits.width + 1, bits.rows + 1);
	core::dimension2du texture_size;

	// Turn bitmap into an image
	video::IImage *image = nullptr;
	switch (bits.pixel_mode)
	{
		case FT_PIXEL_MODE_MONO:
		{
			// Create a blank image and fill it with transparent pixels.
			texture_size = d.getOptimalSize(true, true);
			image = driver->createImage(video::ECF_A1R5G5B5, texture_size);
			image->fill(video::SColor(0, 255, 255, 255));

			// Load the monochrome data in.
			const u32 image_pitch = image->getPitch() / sizeof(u16);
			u16* image_data = (u16*)image->getData();
			u8* glyph_data = bits.buffer;

			for (s32 y = 0; y < (s32)bits.rows; ++y)
			{
				u16* row = image_data;
				for (s32 x = 0; x < (s32)bits.width; ++x)
				{
					// Monochrome bitmaps store 8 pixels per byte.  The left-most pixel is the bit 0x80.
					// So, we go through the data each bit at a time.
					if ((glyph_data[y * bits.pitch + (x / 8)] & (0x80 >> (x % 8))) != 0)
						*row = 0xFFFF;
					++row;
				}
				image_data += image_pitch;
			}
			break;
		}

		case FT_PIXEL_MODE_GRAY:
		{
			// Create our blank image.
			texture_size = d.getOptimalSize(!driver->queryFeature(video::EVDF_TEXTURE_NPOT), !driver->queryFeature(video::EVDF_TEXTURE_NSQUARE), true, 0);
			image = driver->createImage(video::ECF_A8R8G8B8, texture_size);
			image->fill(video::SColor(0, 255, 255, 255));

			// Load the grayscale data in.
			const float gray_count = static_cast<float>(bits.num_grays);
			const u32 image_pitch = image->getPitch() / sizeof(u32);
			u32* image_data = (u32*)image->getData();
			u8* glyph_data = bits.buffer;
			for (s32 y = 0; y < (s32)bits.rows; ++y)
			{
				u8* row = glyph_data;
				for (s32 x = 0; x < (s32)bits.width; ++x)
				{
					image_data[y * image_pitch + x] |= static_cast<u32>(255.0f * (static_cast<float>(*row++) / gray_count)) << 24;
				}
				glyph_data += bits.pitch;
			}
			break;
		}
		case FT_PIXEL_MODE_BGRA:
		{
			// Color bitmap (premultiplied alpha, BGRA byte order).
			// It is scaled down to the rectangle reserved in preload() with a box filter.
			const u32 dst_w = source_rect.getWidth();
			const u32 dst_h = source_rect.getHeight();
			if (dst_w == 0 || dst_h == 0 || bits.width == 0 || bits.rows == 0)
				return nullptr;

			core::dimension2du dd(dst_w + 1, dst_h + 1);
			texture_size = dd.getOptimalSize(!driver->queryFeature(video::EVDF_TEXTURE_NPOT), !driver->queryFeature(video::EVDF_TEXTURE_NSQUARE), true, 0);
			image = driver->createImage(video::ECF_A8R8G8B8, texture_size);
			image->fill(video::SColor(0, 255, 255, 255));

			const u32 image_pitch = image->getPitch() / sizeof(u32);
			u32 *image_data = (u32*)image->getData();
			const u8 *src = bits.buffer;
			const s32 src_pitch = bits.pitch;
			const float sx = (float)bits.width / dst_w;
			const float sy = (float)bits.rows / dst_h;

			for (u32 y = 0; y < dst_h; ++y) {
				const float y0 = y * sy, y1 = (y + 1) * sy;
				const u32 iy0 = (u32)y0;
				const u32 iy1 = std::min<u32>((u32)std::ceil(y1), bits.rows);
				for (u32 x = 0; x < dst_w; ++x) {
					const float x0 = x * sx, x1 = (x + 1) * sx;
					const u32 ix0 = (u32)x0;
					const u32 ix1 = std::min<u32>((u32)std::ceil(x1), bits.width);

					float sum_b = 0, sum_g = 0, sum_r = 0, sum_a = 0, sum_w = 0;
					for (u32 iy = iy0; iy < iy1; ++iy) {
						const float wy = std::min<float>(y1, iy + 1) - std::max<float>(y0, iy);
						const u8 *row = src + (s32)iy * src_pitch;
						for (u32 ix = ix0; ix < ix1; ++ix) {
							const float wx = std::min<float>(x1, ix + 1) - std::max<float>(x0, ix);
							const float w = wx * wy;
							const u8 *px = row + ix * 4;
							sum_b += w * px[0];
							sum_g += w * px[1];
							sum_r += w * px[2];
							sum_a += w * px[3];
							sum_w += w;
						}
					}
					if (sum_w <= 0 || sum_a <= 0)
						continue;

					// Average in premultiplied space, then convert to straight alpha
					// as expected by the blending of the video driver.
					const float a = sum_a / sum_w;
					const float inv = 255.0f / sum_a;
					const u32 r = core::clamp<s32>(core::round32(sum_r * inv), 0, 255);
					const u32 g = core::clamp<s32>(core::round32(sum_g * inv), 0, 255);
					const u32 b = core::clamp<s32>(core::round32(sum_b * inv), 0, 255);
					const u32 a8 = core::clamp<s32>(core::round32(a), 0, 255);
					image_data[y * image_pitch + x] = video::SColor(a8, r, g, b).color;
				}
			}
			break;
		}
		default:
			errorstream << "CGUITTFont: unknown pixel mode " << (int)bits.pixel_mode << std::endl;
			return 0;
	}
	return image;
}

bool SGUITTGlyph::preload(u32 char_index, FT_Face face, CGUITTFont *parent, u32 slot_size, const FT_Int32 loadFlags)
{
	// Set the size of the glyph.
	parent->applyFaceSize();

	// Attempt to load the glyph.
	auto err = FT_Load_Glyph(face, char_index, loadFlags);
	if (err != FT_Err_Ok) {
		warningstream << "SGUITTGlyph: failed to load glyph " << char_index
			<< " with error: " << (int)err << std::endl;
		return false;
	}

	FT_GlyphSlot glyph = face->glyph;
	const FT_Bitmap &bits = glyph->bitmap;

	// Setup the glyph information here:
	u32 width = bits.width, height = bits.rows;
	is_color = bits.pixel_mode == FT_PIXEL_MODE_BGRA;
	if (is_color) {
		// Color bitmaps have a fixed size and are scaled down by us.
		const float scale = parent->getColorBitmapScale();
		// round the advance up to whole pixels so neighbouring glyphs don't overlap
		advance = core::vector2di((std::lround(glyph->advance.x * scale) + 63) & ~63L,
				std::lround(glyph->advance.y * scale));
		offset = core::vector2di(std::lround(glyph->bitmap_left * scale),
				std::lround(glyph->bitmap_top * scale));
		if (width > 0)
			width = std::max<u32>(1, std::lround(width * scale));
		if (height > 0)
			height = std::max<u32>(1, std::lround(height * scale));
		// must fit into a slot (including the extra pixel of the glyph image)
		width = std::min<u32>(width, slot_size - 1);
		height = std::min<u32>(height, slot_size - 1);
	} else {
		advance = core::vector2di(glyph->advance.x, glyph->advance.y);
		offset = core::vector2di(glyph->bitmap_left, glyph->bitmap_top);
	}

	// Try to get the last page with available slots.
	CGUITTGlyphPage* page = parent->getLastGlyphPage();

	// If we need to make a new page, do that now.
	if (!page)
	{
		page = parent->createGlyphPage(bits.pixel_mode);
		if (!page)
			return false;
	}

	// Allocate slot from page
	glyph_page = parent->getLastGlyphPageIndex();
	u32 texture_side_length = page->texture->getOriginalSize().Width;
	core::vector2di page_position(
		(page->used_slots % (texture_side_length / slot_size)) * slot_size,
		(page->used_slots / (texture_side_length / slot_size)) * slot_size
	);
	source_rect.UpperLeftCorner = page_position;
	source_rect.LowerRightCorner = core::vector2di(page_position.X + width, page_position.Y + height);

	++page->used_slots;
	--page->available_slots;

	// createGlyphImage can now be called, the next preload() call will however
	// invalidate the data in `bits`.
	return true;
}

void SGUITTGlyph::unload()
{
	// reset isLoaded to false
	source_rect = core::recti();
	is_color = false;
	load_failed = false;
}


//////////////////////

CGUITTFont *CGUITTFont::createTTFont(IGUIEnvironment *env,
		SGUITTFace *face, u32 size, bool antialias,
		bool preload, u32 shadow, u32 shadow_alpha)
{
	CGUITTFont *font = new CGUITTFont(env);
	bool ret = font->load(face, size, antialias, true, preload);
	if (!ret) {
		font->drop();
		return 0;
	}

	font->shadow_offset = shadow;
	font->shadow_alpha = shadow_alpha;

	return font;
}

//////////////////////

//! Constructor.
CGUITTFont::CGUITTFont(IGUIEnvironment *env) :
	use_monochrome(false), use_hinting(true), use_auto_hinting(true),
	batch_load_size(1)
{

	if (env) {
		// don't grab environment, to avoid circular references
		Driver = env->getVideoDriver();
	}

	if (Driver)
		Driver->grab();

	setInvisibleCharacters(L" ");
}

bool CGUITTFont::load(SGUITTFace *face, const u32 size, const bool antialias,
	const bool transparency, const bool preload)
{
	if (!Driver || size == 0 || !face)
		return false;

	this->size = size;

	// Update the font loading flags when the font is first loaded
	this->use_monochrome = !antialias;
	update_load_flags();

	// Store our face.
	m_face.grab(face);
	tt_face = face->face;
	slot_size = size;

	// Fixed-size color bitmap fonts (e.g. Noto Color Emoji) can't be scaled by
	// FreeType: pick the best matching strike and scale the bitmaps ourselves.
	color_bitmap_face = false;
	if (FT_HAS_COLOR(tt_face) && !FT_IS_SCALABLE(tt_face) &&
			FT_HAS_FIXED_SIZES(tt_face) && tt_face->num_fixed_sizes > 0) {
		FT_Int best = -1;
		for (FT_Int i = 0; i < tt_face->num_fixed_sizes; ++i) {
			const float ppem = tt_face->available_sizes[i].y_ppem / 64.0f;
			if (ppem <= 0)
				continue;
			if (best < 0) {
				best = i;
				continue;
			}
			const float best_ppem = tt_face->available_sizes[best].y_ppem / 64.0f;
			// smallest strike that is not smaller than needed, else the largest
			if ((best_ppem < size && ppem > best_ppem) ||
					(ppem >= size && ppem < best_ppem))
				best = i;
		}
		if (best >= 0) {
			const FT_Bitmap_Size &bs = tt_face->available_sizes[best];
			const float ppem = bs.y_ppem / 64.0f;
			color_bitmap_face = true;
			color_strike_index = best;
			color_bitmap_scale = COLOR_BITMAP_SIZE_FACTOR * size / ppem;
			slot_size = (u32)std::ceil(std::max<int>(bs.width, bs.height) *
					color_bitmap_scale) + 2;
			update_load_flags();
		}
	}

	// Store font metrics.
	if (color_bitmap_face) {
		FT_Select_Size(tt_face, color_strike_index);
		font_metrics = tt_face->size->metrics;
		// There are no usable outline metrics, so derive them from the size
		// (similar to the ones of regular text fonts).
		const FT_Pos asc = (FT_Pos)(size * 0.905f * 64);
		const FT_Pos desc = (FT_Pos)(size * 0.212f * 64);
		font_metrics.ascender = (asc + 63) & ~(FT_Pos)63;
		font_metrics.descender = -((desc + 63) & ~(FT_Pos)63);
		font_metrics.height = font_metrics.ascender - font_metrics.descender;
	} else {
		FT_Set_Pixel_Sizes(tt_face, size, 0);
		font_metrics = tt_face->size->metrics;
	}

	verbosestream << tt_face->num_glyphs << " glyphs, ascender=" << font_metrics.ascender
		<< " height=" << font_metrics.height << std::endl;

	// Allocate our glyphs.
	Glyphs.clear();
	Glyphs.set_used(tt_face->num_glyphs);

	// Cache the first 127 ASCII characters
	if (preload) {
		u32 old_size = batch_load_size;
		batch_load_size = 127;
		getGlyphIndexByChar(U' '); // char needs to exist, so pick space
		batch_load_size = old_size;
	}

	return true;
}

CGUITTFont::~CGUITTFont()
{
	// Delete the glyphs and glyph pages.
	reset_images();
	Glyphs.clear();

	// Drop our driver now.
	if (Driver)
		Driver->drop();
}

void CGUITTFont::reset_images()
{
	// Delete the glyphs.
	for (u32 i = 0; i != Glyphs.size(); ++i)
		Glyphs[i].unload();

	// Unload the glyph pages from video memory.
	for (u32 i = 0; i != Glyph_Pages.size(); ++i)
		delete Glyph_Pages[i];
	Glyph_Pages.clear();

	// Always update the internal FreeType loading flags after resetting.
	update_load_flags();
}

void CGUITTFont::update_glyph_pages() const
{
	for (u32 i = 0; i != Glyph_Pages.size(); ++i)
	{
		if (Glyph_Pages[i]->isDirty())
			Glyph_Pages[i]->updateTexture();
	}
}

CGUITTGlyphPage* CGUITTFont::getLastGlyphPage() const
{
	if (Glyph_Pages.empty())
		return nullptr;
	CGUITTGlyphPage *page = Glyph_Pages[getLastGlyphPageIndex()];
	if (page->available_slots == 0)
		return nullptr;
	return page;
}

CGUITTGlyphPage* CGUITTFont::createGlyphPage(const u8 pixel_mode)
{
	CGUITTGlyphPage *page = nullptr;

	// Name of our page.
	io::path name("glyph_");
	name += tt_face->family_name;
	name += ".";
	name += tt_face->style_name;
	name += ".";
	name += size;
	name += "_";
	name += Glyph_Pages.size(); // The newly created page will be at the end of the collection.

	// Create the new page.
	page = new CGUITTGlyphPage(Driver, name);

	// Determine our maximum texture size.
	core::dimension2du max_texture_size = Driver->getMaxTextureSize();

	// We want to try to put at least 180 glyphs on a single texture.
	// magic number = floor(texture_size / sqrt(180))
	core::dimension2du page_texture_size;
	if (slot_size <= 19) page_texture_size = core::dimension2du(256, 256);
	else if (slot_size <= 38) page_texture_size = core::dimension2du(512, 512);
	else if (slot_size <= 76) page_texture_size = core::dimension2du(1024, 1024);
	else if (slot_size <= 152) page_texture_size = core::dimension2du(2048, 2048);
	else page_texture_size = core::dimension2du(4096, 4096);

	if (page_texture_size.Width > max_texture_size.Width || page_texture_size.Height > max_texture_size.Height)
		page_texture_size = max_texture_size;

	if (!page->createPageTexture(pixel_mode, page_texture_size)) {
		errorstream << "CGUITTGlyphPage: failed to create texture ("
			<< page_texture_size.Width << "x" << page_texture_size.Height << ")" << std::endl;
		delete page;
		return 0;
	}

	// Determine the number of glyph slots on the page and add it to the list of pages
	page->available_slots = (page_texture_size.Width / slot_size) * (page_texture_size.Height / slot_size);
	Glyph_Pages.push_back(page);
	return page;
}

void CGUITTFont::applyFaceSize() const
{
	// Faces are cached and shared, so the size may have been changed by someone else.
	if (color_bitmap_face)
		FT_Select_Size(tt_face, color_strike_index);
	else
		FT_Set_Pixel_Sizes(tt_face, 0, size);
}

void CGUITTFont::setFallback(gui::IGUIFont *font)
{
	sanity_check(font != this);
	fallback.grab(font);
}

void CGUITTFont::setMonochrome(const bool flag)
{
	use_monochrome = flag;
	reset_images();
}

void CGUITTFont::setFontHinting(const bool enable, const bool enable_auto_hinting)
{
	use_hinting = enable;
	use_auto_hinting = enable_auto_hinting;
	reset_images();
}

void CGUITTFont::draw(const core::stringw& text, const core::rect<s32>& position, video::SColor color, bool hcenter, bool vcenter, const core::rect<s32>* clip)
{
	// Allow colors to work for strings that have passed through irrlicht by catching
	// them here and converting them to enriched just before drawing.
	EnrichedString s(text.c_str(), color);
	draw(s, position, hcenter, vcenter, clip);
}

void CGUITTFont::draw(const EnrichedString &text, const core::rect<s32>& position, bool hcenter, bool vcenter, const core::rect<s32>* clip)
{
	const auto &colors = text.getColors();
	constexpr video::SColor fallback_color(255, 255, 255, 255); // if colors is too short

	if (!Driver)
		return;

	// Clear the glyph pages of their render information.
	for (u32 i = 0; i < Glyph_Pages.size(); ++i)
	{
		Glyph_Pages[i]->render_positions.clear();
		Glyph_Pages[i]->render_source_rects.clear();
		Glyph_Pages[i]->render_colors.clear();
	}

	// Set up some variables.
	core::dimension2d<s32> textDimension;
	core::position2d<s32> offset = position.UpperLeftCorner;

	// Determine offset positions.
	if (hcenter || vcenter)
	{
		textDimension = getDimension(text.c_str());

		if (hcenter)
			offset.X = ((position.getWidth() - textDimension.Width) / 2) + offset.X;

		if (vcenter)
			offset.Y = ((position.getHeight() - textDimension.Height) / 2) + offset.Y;
	}

	// Convert to a unicode string.
	const std::u32string utext = convertWCharToU32String(text.c_str());
	const u32 lineHeight = getLineHeight();

	// Start parsing characters.
	// The same logic is applied to `CGUITTFont::getDimension`
	char32_t previousChar = 0;
	for (size_t i = 0; i < utext.size(); ++i)
	{
		char32_t currentChar = utext[i];
		bool lineBreak = false;
		if (currentChar == U'\r') // Mac or Windows breaks
		{
			lineBreak = true;
			// `std::u32string` is '\0'-terminated, thus this check is OK
			if (utext[i + 1] == U'\n') // Windows line breaks.
				currentChar = utext[++i];
		}
		else if (currentChar == U'\n') // Unix breaks
		{
			lineBreak = true;
		}

		if (lineBreak)
		{
			previousChar = 0;
			offset.Y += lineHeight;
			offset.X = position.UpperLeftCorner.X;

			if (hcenter)
				offset.X += (position.getWidth() - textDimension.Width) / 2;
			continue;
		}

		// Draw visible text

		SGUITTGlyph *glyph = nullptr;
		const u32 width = getWidthFromCharacter(currentChar);

		// Skip whitespace characters
		if (InvisibleChars.find(currentChar) != std::u32string::npos ||
				isZeroWidthEmojiControl(currentChar))
			goto skip_invisible;

		if (clip) {
			// Skip fully clipped characters.
			const core::recti rect(
				offset,
				offset + core::vector2di(width, lineHeight)
			);
			if (!clip->isRectCollided(rect))
				goto skip_invisible;
		}

		{
			// Retrieve the glyph
			const u32 n = getGlyphIndexByChar(currentChar);
			if (n > 0)
				glyph = &Glyphs[n - 1];
		}

		if (glyph)
		{
			// Calculate the glyph offset.
			const s32 offx = glyph->offset.X;
			const s32 offy = (font_metrics.ascender / 64) - glyph->offset.Y;

			// Apply kerning.
			offset += getKerning(currentChar, previousChar);

			// Determine rendering information.
			CGUITTGlyphPage *const page = Glyph_Pages[glyph->glyph_page];
			page->render_positions.emplace_back(offset.X + offx, offset.Y + offy);
			page->render_source_rects.push_back(glyph->source_rect);
			video::SColor glyph_color = i < colors.size() ? colors[i] : fallback_color;
			if (glyph->is_color) {
				// color glyphs (emoji) are not tinted, but keep the transparency
				glyph_color = video::SColor(glyph_color.getAlpha(), 255, 255, 255);
			}
			page->render_colors.push_back(glyph_color);
		}
		else if (fallback)
		{
			// Let the fallback font draw it, this isn't super efficient but hopefully that doesn't matter
			const core::stringw l1 = charToWideString(currentChar);

			// Apply kerning.
			if (currentChar <= WCHAR_MAX && previousChar <= WCHAR_MAX)
				offset += fallback->getKerning((wchar_t) currentChar, (wchar_t) previousChar);

			fallback->draw(l1,
				core::rect<s32>({offset.X-1, offset.Y-1}, position.LowerRightCorner), // ???
				i < colors.size() ? colors[i] : fallback_color,
				false, false, clip);
		}

skip_invisible:
		offset.X += width;
		previousChar = currentChar;
	}

	// Draw now.
	update_glyph_pages();
	core::array<core::vector2di> tmp_positions;
	core::array<core::recti> tmp_source_rects;
	for (u32 page_i = 0; page_i < Glyph_Pages.size(); ++page_i) {
		CGUITTGlyphPage *page = Glyph_Pages[page_i];

		if (page->render_positions.empty())
			continue;

		assert(page->render_positions.size() == page->render_colors.size());
		assert(page->render_positions.size() == page->render_source_rects.size());

		// render runs of matching color in batch
		video::SColor colprev;
		for (size_t i = 0; i < page->render_positions.size(); ++i) {
			const size_t ibegin = i;
			colprev = page->render_colors[i];
			do
				++i;
			while (i < page->render_positions.size() && page->render_colors[i] == colprev);
			tmp_positions.set_data(&page->render_positions[ibegin], i - ibegin);
			tmp_source_rects.set_data(&page->render_source_rects[ibegin], i - ibegin);
			--i;

			if (shadow_offset) {
				for (size_t i = 0; i < tmp_positions.size(); ++i)
					tmp_positions[i] += core::vector2di(shadow_offset, shadow_offset);

				u32 new_shadow_alpha = core::clamp(core::round32(shadow_alpha * colprev.getAlpha() / 255.0f), 0, 255);
				video::SColor shadow_color = video::SColor(new_shadow_alpha, 0, 0, 0);
				Driver->draw2DImageBatch(page->texture, tmp_positions, tmp_source_rects, clip, shadow_color, true);

				for (size_t i = 0; i < tmp_positions.size(); ++i)
					tmp_positions[i] -= core::vector2di(shadow_offset, shadow_offset);
			}

			Driver->draw2DImageBatch(page->texture, tmp_positions, tmp_source_rects, clip, colprev, true);
		}
	}
}

core::dimension2d<u32> CGUITTFont::getDimension(const wchar_t* text) const
{
	return getDimension(convertWCharToU32String(text));
}

core::dimension2d<u32> CGUITTFont::getDimension(const std::u32string& utext) const
{
	// Get the maximum font height.  Unfortunately, we have to do this hack as
	// Irrlicht will draw things wrong.  In FreeType, the font size is the
	// maximum size for a single glyph, but that glyph may hang "under" the
	// draw line, increasing the total font height to beyond the set size.
	// Irrlicht does not understand this concept when drawing fonts.  Also, I
	// add +1 to give it a 1 pixel blank border.  This makes things like
	// tooltips look nicer.
	const u32 lineHeight = getLineHeight();

	core::dimension2d<u32> text_dimension(0, lineHeight);
	core::dimension2d<u32> line(0, lineHeight);

	// The same logic is applied to `CGUITTFont::draw`
	char32_t previousChar = 0;
	for (size_t i = 0; i < utext.size(); ++i)
	{
		char32_t currentChar = utext[i];
		bool lineBreak = false;
		if (currentChar == U'\r') // Mac or Windows breaks
		{
			lineBreak = true;
			// `std::u32string` is '\0'-terminated, thus this check is OK
			if (utext[i + 1] == U'\n') // Windows line breaks.
				currentChar = utext[++i];
		}
		else if (currentChar == U'\n') // Unix breaks
		{
			lineBreak = true;
		}

		// Check for linebreak.
		if (lineBreak)
		{
			previousChar = 0;
			text_dimension.Height += line.Height;
			if (text_dimension.Width < line.Width)
				text_dimension.Width = line.Width;
			line.Width = 0;
			line.Height = lineHeight;
			continue;
		}

		// Kerning.
		line.Width += getKerning(currentChar, previousChar).X;

		previousChar = currentChar;
		line.Width += getWidthFromCharacter(currentChar);
	}
	if (text_dimension.Width < line.Width)
		text_dimension.Width = line.Width;

	return text_dimension;
}

inline u32 CGUITTFont::getWidthFromCharacter(char32_t c) const
{
	if (isZeroWidthEmojiControl(c))
		return 0;

	u32 n = getGlyphIndexByChar(c);
	if (n > 0)
	{
		int w = Glyphs[n-1].advance.X / 64;
		return w;
	}
	if (fallback)
	{
		return fallback->getDimension(charToWideString(c).c_str()).Width;
	}

	if (c >= 0x2000)
		return (font_metrics.ascender / 64);
	else return (font_metrics.ascender / 64) / 2;
}

inline u32 CGUITTFont::getHeightFromCharacter(char32_t c) const
{
	if (isZeroWidthEmojiControl(c))
		return 0;

	u32 n = getGlyphIndexByChar(c);
	if (n > 0)
	{
		// Grab the true height of the character, taking into account underhanging glyphs.
		s32 height = (font_metrics.ascender / 64) - Glyphs[n-1].offset.Y + Glyphs[n-1].source_rect.getHeight();
		return height;
	}
	if (fallback)
	{
		return fallback->getDimension(charToWideString(c).c_str()).Height;
	}

	if (c >= 0x2000)
		return (font_metrics.ascender / 64);
	else return (font_metrics.ascender / 64) / 2;
}

u32 CGUITTFont::getGlyphIndexByChar(char32_t c) const
{
	// Get the glyph.
	u32 glyph = FT_Get_Char_Index(tt_face, c);

	// Check for a valid glyph.
	if (glyph == 0)
		return 0;

	// If loading failed before, don't try again (let the fallback handle it).
	if (Glyphs[glyph - 1].load_failed)
		return 0;

	// If our glyph is already loaded, don't bother doing any batch loading code.
	if (Glyphs[glyph - 1].isLoaded())
		return glyph;

	// Determine our batch loading positions.
	u32 half_size = (batch_load_size / 2);
	u32 start_pos = 0;
	if (c > half_size)
		start_pos = c - half_size;
	u32 end_pos = start_pos + batch_load_size;

	// Load all our characters.
	do
	{
		// Get the character we are going to load.
		u32 char_index = FT_Get_Char_Index(tt_face, start_pos);

		// If the glyph hasn't been loaded yet, do it now.
		if (char_index)
		{
			SGUITTGlyph& glyph = Glyphs[char_index - 1];
			if (!glyph.isLoaded())
			{
				auto *this2 = const_cast<CGUITTFont*>(this); // oh well
				if (!glyph.preload(char_index, tt_face, this2, slot_size, load_flags)) {
					glyph.load_failed = true;
					continue;
				}
				auto *surface = glyph.createGlyphImage(tt_face->glyph->bitmap, Driver);
				Glyph_Pages[glyph.glyph_page]->pushGlyphToBePaged(&glyph, surface);
			}
		}
	}
	while (++start_pos < end_pos);

	// Return our original character.
	if (Glyphs[glyph - 1].load_failed)
		return 0;
	return glyph;
}

s32 CGUITTFont::getCharacterFromPos(const wchar_t* text, s32 pixel_x) const
{
	return getCharacterFromPos(convertWCharToU32String(text), pixel_x);
}

s32 CGUITTFont::getCharacterFromPos(const std::u32string& text, s32 pixel_x) const
{
	s32 x = 0;

	u32 character = 0;
	char32_t previousChar = 0;
	auto iter = text.begin();
	while (iter != text.end())
	{
		char32_t c = *iter;
		x += getWidthFromCharacter(c);

		// Kerning.
		core::vector2di k = getKerning(c, previousChar);
		x += k.X;

		if (x >= pixel_x)
			return character;

		previousChar = c;
		++iter;
		++character;
	}

	return -1;
}

void CGUITTFont::setKerningWidth(s32 kerning)
{
	GlobalKerningWidth = kerning;
}

void CGUITTFont::setKerningHeight(s32 kerning)
{
	GlobalKerningHeight = kerning;
}

core::vector2di CGUITTFont::getKerning(const wchar_t thisLetter, const wchar_t previousLetter) const
{
	return getKerning((char32_t)thisLetter, (char32_t)previousLetter);
}

core::vector2di CGUITTFont::getKerning(const char32_t thisLetter, const char32_t previousLetter) const
{
	if (tt_face == 0 || thisLetter == 0 || previousLetter == 0)
		return core::vector2di();

	// Set the size of the face.
	// This is because we cache faces and the face may have been set to a different size.
	applyFaceSize();

	core::vector2di ret(GlobalKerningWidth, GlobalKerningHeight);

	u32 n = getGlyphIndexByChar(thisLetter);

	// If we don't have this glyph, ask fallback font
	if (n == 0)
	{
		if (fallback && thisLetter <= WCHAR_MAX && previousLetter <= WCHAR_MAX)
			ret = fallback->getKerning((wchar_t) thisLetter, (wchar_t) previousLetter);
		return ret;
	}

	// If we don't have kerning, no point in continuing.
	if (!FT_HAS_KERNING(tt_face))
		return ret;

	// Get the kerning information.
	FT_Vector v;
	FT_Get_Kerning(tt_face, getGlyphIndexByChar(previousLetter), n, FT_KERNING_DEFAULT, &v);

	// If we have a scalable font, the return value will be in font points.
	if (FT_IS_SCALABLE(tt_face))
	{
		// Font points, so divide by 64.
		ret.X += (v.x / 64);
		ret.Y += (v.y / 64);
	}
	else
	{
		// Pixel units.
		ret.X += v.x;
		ret.Y += v.y;
	}
	return ret;
}

void CGUITTFont::setInvisibleCharacters(const wchar_t *s)
{
	InvisibleChars = convertWCharToU32String(s);
}

std::u32string CGUITTFont::convertWCharToU32String(const wchar_t* const charArray) const
{
	static_assert(sizeof(wchar_t) == 2 || sizeof(wchar_t) == 4, "unexpected wchar size");

	if (sizeof(wchar_t) == 4) // wchar_t is UTF-32
		return std::u32string(reinterpret_cast<const char32_t*>(charArray));

	// wchar_t is UTF-16 and we need to convert.
	// std::codecvt could do this for us but aside from being deprecated,
	// it turns out that it's laughably slow on MSVC. Thanks Microsoft.

	std::u32string ret;
	ret.reserve(wcslen(charArray));
	const wchar_t *p = charArray;
	while (*p) {
		char32_t c = *p;
		if (c >= 0xD800 && c < 0xDC00) {
			p++;
			char32_t c2 = *p;
			if (!c2)
				break;
			else if (c2 < 0xDC00 || c2 > 0xDFFF)
				continue; // can't find low surrogate, skip
			c = 0x10000 + ( ((c & 0x3ff) << 10) | (c2 & 0x3ff) );
		}
		ret.push_back(c);
		p++;
	}
	return ret;
}


} // end namespace gui
