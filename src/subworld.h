// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "irr_v3d.h"
#include <string>
#include <unordered_map>

struct PlayerSubWorldState {
	std::string current_subworld = "overworld";
	std::unordered_map<std::string, v3f> positions;
};
