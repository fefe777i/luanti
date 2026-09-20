// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "dimension.h"
#include "filesys.h"
#include "log.h"
#include "util/string.h"
#include <algorithm>
#include <random>

namespace dimension
{

static const char *const DIMENSIONS_DIR = "dimensions";
static const char *const STATE_FILE = "current_dimension.txt";

bool isValidName(const std::string &name)
{
	if (name.empty() || name.size() > 32)
		return false;
	for (unsigned char c : name) {
		const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				(c >= '0' && c <= '9') || c == '_' || c == '-';
		if (!ok)
			return false;
	}
	return true;
}

std::string getMapPath(const std::string &world_path, const std::string &name)
{
	if (name == DEFAULT_NAME)
		return world_path;
	return world_path + DIR_DELIM + DIMENSIONS_DIR + DIR_DELIM + name;
}

bool exists(const std::string &world_path, const std::string &name)
{
	if (name == DEFAULT_NAME)
		return true;
	return isValidName(name) && fs::IsDir(getMapPath(world_path, name));
}

std::string loadCurrent(const std::string &world_path)
{
	const std::string path = world_path + DIR_DELIM + STATE_FILE;
	auto is = open_ifstream(path.c_str(), false);
	if (!is.good())
		return DEFAULT_NAME;

	std::string line;
	std::getline(is, line);
	const std::string name(trim(line));

	if (!isValidName(name) || !exists(world_path, name)) {
		warningstream << "Dimension \"" << name << "\" from " << path
			<< " does not exist, using \"" << DEFAULT_NAME << "\"" << std::endl;
		return DEFAULT_NAME;
	}
	return name;
}

bool saveCurrent(const std::string &world_path, const std::string &name)
{
	if (!isValidName(name))
		return false;
	return fs::safeWriteToFile(world_path + DIR_DELIM + STATE_FILE, name + "\n");
}

std::vector<std::string> list(const std::string &world_path)
{
	std::vector<std::string> result{DEFAULT_NAME};

	const std::string dir = world_path + DIR_DELIM + DIMENSIONS_DIR;
	std::vector<std::string> others;
	for (const auto &node : fs::GetDirListing(dir)) {
		if (node.dir && node.name != DEFAULT_NAME && isValidName(node.name))
			others.push_back(node.name);
	}
	std::sort(others.begin(), others.end());
	result.insert(result.end(), others.begin(), others.end());
	return result;
}

static bool isValidSettingKey(const std::string &key)
{
	if (key.empty() || key.size() > 64)
		return false;
	for (unsigned char c : key) {
		if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '.'))
			return false;
	}
	return true;
}

bool create(const std::string &world_path, const std::string &name,
		const std::vector<std::pair<std::string, std::string>> &map_settings,
		std::string &error)
{
	if (!isValidName(name)) {
		error = "invalid name (use letters, digits, '_' and '-', at most 32 characters)";
		return false;
	}
	if (name == DEFAULT_NAME) {
		error = "\"" + DEFAULT_NAME + "\" is the main world and always exists";
		return false;
	}

	const std::string dir = getMapPath(world_path, name);
	if (fs::PathExists(dir)) {
		error = "this dimension already exists";
		return false;
	}

	// Check everything before touching the disk
	std::string meta;
	bool has_seed = false;
	for (const auto &kv : map_settings) {
		if (!isValidSettingKey(kv.first) ||
				kv.second.find_first_of("\r\n") != std::string::npos) {
			error = "invalid map setting \"" + kv.first + "\"";
			return false;
		}
		if (kv.first == "seed")
			has_seed = true;
		meta += kv.first + " = " + kv.second + "\n";
	}
	if (!has_seed) {
		// Every dimension gets its own terrain
		std::random_device rd;
		std::mt19937_64 gen(rd());
		meta += "seed = " + std::to_string(gen() >> 1) + "\n";
	}
	meta += "[end_of_params]\n";

	if (!fs::CreateAllDirs(dir)) {
		error = "could not create the directory " + dir;
		return false;
	}
	if (!fs::safeWriteToFile(dir + DIR_DELIM + "map_meta.txt", meta)) {
		error = "could not write map_meta.txt";
		return false;
	}
	actionstream << "Created dimension \"" << name << "\" in " << dir << std::endl;
	return true;
}

}
