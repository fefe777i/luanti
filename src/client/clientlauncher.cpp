// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2010-2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#include "gui/mainmenumanager.h"
#include "clouds.h"
#include "gui/touchcontrols.h"
#include "filesys.h"
#include "gui/guiMainMenu.h"
#include "game.h"
#include "player.h"
#include "chat.h"
#include "gettext.h"
#include "inputhandler.h"
#include "profiler.h"
#include "exceptions.h"
#include "gui/guiEngine.h"
#include "fontengine.h"
#include "clientlauncher.h"
#include "version.h"
#include "renderingengine.h"
#include "settings.h"
#include "gettime.h"
#include "util/numeric.h"
#include "util/tracy_wrapper.h"
#include <IGUISpriteBank.h>
#include <ICameraSceneNode.h>
#include <unordered_map>

#if USE_SOUND
	#include "sound/sound_openal.h"
#endif

/* mainmenumanager.h
 */
gui::IGUIEnvironment *guienv = nullptr;
gui::IGUIStaticText *guiroot = nullptr;
MainMenuManager g_menumgr;

// Passed to menus to allow disconnecting and exiting
MainGameCallback *g_gamecallback = nullptr;

#if 0
// This can be helpful for the next code cleanup
static void dump_start_data(const GameStartData &data)
{
	std::cout <<
		"\ndedicated   " << (int)data.is_dedicated_server <<
		"\nport        " << data.socket_port <<
		"\nworld_path  " << data.world_spec.path <<
		"\nworld game  " << data.world_spec.gameid <<
		"\ngame path   " << data.game_spec.path <<
		"\nplayer name " << data.name <<
		"\naddress     " << data.address << std::endl;
}
#endif

ClientLauncher::~ClientLauncher()
{
	delete input;

	g_settings->deregisterAllChangedCallbacks(this);

	if (g_menucloudsmgr) {
		assert(g_menucloudsmgr->getReferenceCount() == 1);
		g_menucloudsmgr->drop();
		g_menucloudsmgr = nullptr;
	}

	if (g_menuclouds) {
		assert(g_menuclouds->getReferenceCount() == 1);
		g_menuclouds->drop();
		g_menuclouds = nullptr;
	}

	delete g_fontengine;
	g_fontengine = nullptr;
	delete g_gamecallback;
	g_gamecallback = nullptr;

	assert(g_menumgr.menuCount() == 0);

	delete m_rendering_engine;

	// CGUIEnvironment causes calls to `deletingMenu`, which needs `guienv != nullptr`.
	guiroot = nullptr;
	guienv = nullptr;

	// delete event receiver only after all Irrlicht stuff is gone
	delete receiver;

#if USE_SOUND
	g_sound_manager_singleton.reset();
#endif
}


bool ClientLauncher::run(const GameParams &game_params, const Settings &cmd_args)
{
	GameStartData start_data;
	static_cast<GameParams &>(start_data) = game_params;

	init_args(start_data, cmd_args);

	try {
		init_engine();
	} catch (BaseException &e) {
		errorstream << e.what() << std::endl;
		RenderingEngine::showErrorMessageBox(e.what());
		return false;
	}

	sanity_check(m_rendering_engine->get_video_driver() != nullptr);

	m_rendering_engine->setupTopLevelWindow();

	// Create game callback for menus
	g_gamecallback = new MainGameCallback();

	m_rendering_engine->setResizable(true);
