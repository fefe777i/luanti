// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include <string>
#include <utility>
#include <vector>

/*
	Dimensions: several completely separate worlds (own map, own seed,
	own mapgen) inside one world folder, like the Overworld/Nether/End
	in Minecraft.

	Layout inside a world folder:

		<world>/                      "overworld" (the main world, always exists)
		<world>/dimensions/<name>/    every other dimension (map.sqlite, map_meta.txt)
		<world>/current_dimension.txt the dimension the world is loaded into

	Players, inventories, privileges, mod storage and the game time are
	shared between all dimensions of a world (they live in <world>/).
	Only the map is separate.
*/
namespace dimension
{

// Name of the main world. It is the world folder itself.
inline const std::string DEFAULT_NAME = "overworld";

// Letters, digits, '_' and '-', 1..32 characters.
bool isValidName(const std::string &name);

// Directory that holds the map of a dimension.
std::string getMapPath(const std::string &world_path, const std::string &name);

// "overworld" always exists, others exist when their directory exists.
bool exists(const std::string &world_path, const std::string &name);

// Dimension the world should be loaded into (falls back to "overworld").
std::string loadCurrent(const std::string &world_path);
bool saveCurrent(const std::string &world_path, const std::string &name);

// All dimensions, "overworld" first.
std::vector<std::string> list(const std::string &world_path);

// Creates a new dimension. `map_settings` are written to its map_meta.txt
// (for example {"mg_name", "flat"}). A random seed is used unless "seed" is given.
bool create(const std::string &world_path, const std::string &name,
		const std::vector<std::pair<std::string, std::string>> &map_settings,
		std::string &error);

}
