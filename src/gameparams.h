// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2010-2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include "irrlichttypes.h"
#include "content/subgames.h"
#include "log.h" // errorstream

// Information provided from "main"
// Start information for server or client
struct GameParams
{
	GameParams() = default;

	u16 socket_port;
	std::string world_path;
	SubgameSpec game_spec;
	bool is_dedicated_server;
};

enum class ELoginRegister {
	Any = 0,
	Login,
	Register
};

struct GameClientData
{
	bool isSinglePlayer() const { return mode == GM_SINGLEPLAYER; }
	bool isAnyServer() const
	{ return mode == GM_HOST_AND_JOIN || mode == GM_SINGLEPLAYER; }

	std::string name;
	std::string password;
	std::string address; //< non-empty when joining a server

	enum Mode {
		GM_SINGLEPLAYER,
		GM_HOST_AND_JOIN,
		GM_JOIN,
		GM_Undefined
	} mode = GM_Undefined;

	ELoginRegister allow_login_or_register = ELoginRegister::Any;
};

// Information provided by ClientLauncher
// Client-only data (joining or hosting server)
struct GameStartData : GameParams, GameClientData
{
	GameStartData() = default;

	// "world_path" must be kept in sync!
	WorldSpec world_spec;
};

/// Data provided to Lua for error reporting by the main menu
struct GameErrorData
{
	GameErrorData() = default;

	/// Raise and log an error
	/// @param msg Empty string means no error
	void setError(const std::string &msg, bool reconnect = false)
	{
		message = msg;
		reconnect_requested = reconnect;
		errorstream << msg << std::endl;
	}

	// Whether the server has requested a reconnect
	bool reconnect_requested = false;
	// Set by the game when the player travelled to another dimension:
	// the launcher then starts the same world again without the main menu
	bool dimension_switch_requested = false;
	// Set by the game when the server asked to continue on another server
	// of the same host (a dimension that runs as its own server)
	bool transfer_requested = false;
	std::string transfer_address;
	u16 transfer_port = 0;
	std::string message;
};
