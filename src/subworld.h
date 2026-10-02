// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "dimension.h"
#include "irr_v3d.h"
#include <string>
#include <unordered_map>

// Per-player subworld state used by the custom multiworld logic.
struct PlayerSubWorldState {
	std::string current_subworld = "overworld";
	std::unordered_map<std::string, v3f> positions;
};
