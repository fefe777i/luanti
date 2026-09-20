// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2010-2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include <memory>
#include <string>
#include "client/shader.h" // IWritableShaderSource

class RenderingEngine;
class Settings;
class MyEventReceiver;
class InputHandler;
struct GameParams;
struct GameStartData;
struct MainMenuData;

class ClientLauncher
{
public:
	ClientLauncher() = default;

	~ClientLauncher();

	bool run(const GameParams &game_params, const Settings &cmd_args);

private:
	void init_args(GameStartData &start_data, const Settings &cmd_args);
	void init_engine();
	void init_input();

	static void setting_changed_callback(const std::string &name, void *data);
	void config_guienv();

	bool launch_game(GameErrorData &errordata,
		GameStartData &start_data, const Settings &cmd_args);

	void main_menu(MainMenuData *menudata);

	bool skip_main_menu = false;
	// The player travelled to another dimension: start the world again
	// right away (without the main menu)
	bool m_dimension_restart = false;
	bool random_input = false;
	// Shader source of the main menu (menu clouds); it must outlive them
	std::unique_ptr<IWritableShaderSource> ssrc;
	RenderingEngine *m_rendering_engine = nullptr;
	InputHandler *input = nullptr;
	MyEventReceiver *receiver = nullptr;
};
