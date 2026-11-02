// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "irrlichttypes.h"
#include "content/subgames.h"
#include <condition_variable>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

class Server;

/*
	Runs one server per dimension of a hosted world ("Host game" button).

	All servers live in this process, open the same world folder (players,
	inventories and privileges are shared) and each one loads the map of its
	own dimension, so different players can be in different dimensions at the
	same time.

	Only the main dimension ("overworld") runs all the time, on the port chosen
	in the menu. Every other dimension gets a port reserved for it (the
	"dimension_servers" setting is kept up to date, so core.travel_to_dimension()
	knows it), but its server is only started when somebody wants to go there
	(wake()) and is stopped again, with the map saved, when nobody has been in
	it for "dimension_idle_timeout" seconds. An empty dimension therefore costs
	no CPU, no memory and no loaded map, like in Minecraft.

	The host's own client connects like any other client, so the servers
	outlive game restarts and the host can move between dimensions without
	stopping anybody else's server.
*/
class DimensionHost
{
public:
	DimensionHost(const std::string &world_path, const SubgameSpec &gamespec,
			u16 base_port);
	~DimensionHost();

	// Starts the main dimension and registers the others (not started).
	// Returns false (and sets `error`) when the main dimension failed to start.
	bool start(std::string &error);
	// Stops all servers (blocks until the worlds are saved)
	void stop();

	u16 getMainPort() const { return m_base_port; }
	// 0 when the dimension is unknown
	u16 getPort(const std::string &dimension) const;

	// Called every frame by the game: rethrows fatal server errors and stops
	// the servers of dimensions that have been empty for too long
	void step();
	bool isShutdownRequested() const;

	// Message of the servers' shutdown errors (empty if none)
	const std::string &getShutdownMessage() const { return m_shutdown_message; }

	// Makes sure the server of the dimension is running (starts it in the
	// background if needed). Returns "ready", "starting" or "failed:<message>".
	// May be called from any thread.
	std::string wake(const std::string &dimension);

private:
	enum class State { Stopped, Starting, Running, Stopping, Failed };

	struct Dim
	{
		State state = State::Stopped;
		u16 port = 0;
		std::unique_ptr<Server> server;
		u64 last_active = 0; // ms
		bool restart_after_stop = false;
		std::string error;
	};

	struct Task
	{
		bool start;
		std::string name;
	};

	bool startServer(const std::string &dimension, std::string &error);
	void stopServer(const std::string &dimension);
	void queueDimension(const std::string &dimension);
	void workerMain();
	// m_mutex must be held
	Dim *registerLocked(const std::string &dimension);
	u16 allocatePortLocked();
	std::string buildSettingLocked() const;
	void publishSetting();
	void copyMediaToClientCache(Server *server);

	std::string m_world_path;
	SubgameSpec m_gamespec;
	u16 m_base_port;
	u16 m_next_port;

	mutable std::mutex m_mutex;
	std::map<std::string, Dim> m_dims;
	std::deque<Task> m_tasks;
	std::condition_variable m_cond;
	std::thread m_worker;
	bool m_stopping = false;
	bool m_started = false;
	u64 m_last_idle_check = 0;

	bool m_setting_saved = false;
	bool m_had_old_setting = false;
	std::string m_old_setting;
	std::string m_shutdown_message;
};
