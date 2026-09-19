// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "irr_v3d.h"
#include "filesys.h"
#include <algorithm>
#include <string>
#include <unordered_map>
#include <vector>

static inline bool isSubWorldDir(const std::string &path)
{
	return fs::PathExists(path + DIR_DELIM + "world.mt");
}

struct SubWorldSpec {
	std::string name;
	std::string path;
};

static inline std::vector<SubWorldSpec> discoverSubWorlds(const std::string &worlds_root)
{
	std::vector<SubWorldSpec> result;

	if (!fs::IsDir(worlds_root))
		return result;

	for (const auto &entry : fs::GetDirListing(worlds_root)) {
		if (!entry.dir || entry.name.empty() || entry.name[0] == '.')
			continue;

		const std::string path = worlds_root + DIR_DELIM + entry.name;
		if (isSubWorldDir(path))
			result.push_back({entry.name, path});
	}

	std::sort(result.begin(), result.end(), [](const SubWorldSpec &a,
			const SubWorldSpec &b) {
		return a.name < b.name;
	});

	return result;
}

static inline bool isValidSubWorldName(const std::string &name)
{
	if (name.empty() || name == "." || name == "..")
		return false;

	for (const char c : name) {
		if (c == '/' || c == '\\' || c == ':' || c == '\0')
			return false;
	}

	return true;
}

struct WorldInstance {
	std::string name;
	std::string path;
	bool loaded = false;

	WorldInstance() = default;
	WorldInstance(std::string name_, std::string path_):
		name(std::move(name_)), path(std::move(path_)) {}
};

struct PlayerSubWorldState {
	std::string current_subworld = "overworld";
	std::unordered_map<std::string, v3f> positions;
};
