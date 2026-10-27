// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include <string>

// One server chat command as announced to the client (TOCLIENT_CHAT_COMMANDS).
// Used by the chat console to suggest commands after the user types "/".
struct ChatCommandInfo
{
	std::string name;        // without the leading "/"
	std::string params;      // e.g. "<name> <message>"
	std::string description;
};
