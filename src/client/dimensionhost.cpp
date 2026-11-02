// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "dimensionhost.h"
#include "clientmedia.h"
#include "dimension.h"
#include "exceptions.h"
#include "log.h"
#include "network/address.h"
#include "network/networkexceptions.h"
#include "network/socket.h"
#include "porting.h"
#include "server.h"
#include "settings.h"
#include "util/string.h"
#include <algorithm>
#include <vector>

namespace {

Address makeBindAddress(u16 port)
{
	Address addr(0, 0, 0, 0, port);
	if (g_settings->getBool("ipv6_server"))
		addr.setAddress(static_cast<IPv6AddressBytes *>(nullptr));
	const std::string bind_str = g_settings->get("bind_address");
	try {
		addr.Resolve(bind_str.c_str());
	} catch (const ResolveError &e) {
		warningstream << "Resolving bind address \"" << bind_str
			<< "\" failed: " << e.what()
			<< " -- Listening on all addresses." << std::endl;
	}
	return addr;
}

bool isPortFree(u16 port)
{
	try {
		Address addr = makeBindAddress(port);
		UDPSocket socket(addr.isIPv6());
		socket.Bind(addr);
		return true;
	} catch (const std::exception &) {
		return false;
	}
}

// Seconds an empty dimension keeps running (0 = never stop)
float idleTimeout()
{
	float t = 60.0f;
	g_settings->getFloatNoEx("dimension_idle_timeout", t);
	return t;
}

// Length of a server tick of the servers of this host. The default of
// standalone servers (0.09 s) is plenty, ticking faster only multiplies the
// work of every mod once per dimension.
float serverStep(bool is_main)
{
	float step = 0.09f;
	g_settings->getFloatNoEx("dimension_server_step", step);
	step = std::max(step, 0.01f);
	// The server of the host's own world stays a bit more responsive
	return is_main ? std::min(step, 0.05f) : step;
}

}

DimensionHost::DimensionHost(const std::string &world_path,
		const SubgameSpec &gamespec, u16 base_port) :
	m_world_path(world_path),
	m_gamespec(gamespec),
	m_base_port(base_port),
	m_next_port(base_port + 1)
{
}

DimensionHost::~DimensionHost()
{
	stop();
}

u16 DimensionHost::getPort(const std::string &dimension) const
{
	std::lock_guard<std::mutex> lock(m_mutex);
	auto it = m_dims.find(dimension);
	return it == m_dims.end() ? 0 : it->second.port;
}

u16 DimensionHost::allocatePortLocked()
{
	for (int i = 0; i < 200; i++) {
		u16 port = m_next_port++;
		if (m_next_port == 0)
			m_next_port = 1024;
		bool used = false;
		for (const auto &it : m_dims)
			used |= (it.second.port == port);
		if (!used && isPortFree(port))
			return port;
	}
	return 0;
}

DimensionHost::Dim *DimensionHost::registerLocked(const std::string &dimension)
{
	u16 port = allocatePortLocked();
	if (port == 0) {
		errorstream << "DimensionHost: no free port for the dimension \""
			<< dimension << "\"" << std::endl;
		return nullptr;
	}
	Dim &d = m_dims[dimension];
	d.port = port;
	d.state = State::Stopped;
	return &d;
}

std::string DimensionHost::buildSettingLocked() const
{
	// "dimension_servers = overworld=30000, nether=30001" (read by
	// core.travel_to_dimension)
	std::string value;
	for (const auto &it : m_dims) {
		if (it.second.port == 0)
			continue;
		if (!value.empty())
			value += ", ";
		value += it.first + "=" + std::to_string(it.second.port);
	}
	return value;
}

void DimensionHost::publishSetting()
{
	std::string value;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		value = buildSettingLocked();
	}
	g_settings->set("dimension_servers", value);
}

bool DimensionHost::startServer(const std::string &dimension, std::string &error)
{
	const bool is_main = (dimension == dimension::DEFAULT_NAME);
	u16 port;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		auto it = m_dims.find(dimension);
		if (it == m_dims.end() || it->second.port == 0) {
			error = "dimension \"" + dimension + "\" has no port";
			return false;
		}
		port = it->second.port;
	}

	std::unique_ptr<Server> server;
	try {
		server = std::make_unique<Server>(m_world_path, m_gamespec, false,
				makeBindAddress(port), false, nullptr, &m_shutdown_message,
				dimension);
		// Only one server announces the world to the server list
		server->setMasterAnnounce(is_main);
		server->setDimensionCreatedCallback(
				[this](const std::string &name) { queueDimension(name); });
		server->setDimensionWakeCallback(
				[this](const std::string &name) { return wake(name); });
		server->setStepSettings(Server::StepSettings{serverStep(is_main), false});
		server->start();
	} catch (const std::exception &e) {
		error = std::string("dimension \"") + dimension + "\": " + e.what();
		errorstream << "DimensionHost: " << error << std::endl;
		return false;
	}

	if (is_main)
		copyMediaToClientCache(server.get());

	{
		std::lock_guard<std::mutex> lock(m_mutex);
		Dim &d = m_dims[dimension];
		d.server = std::move(server);
		d.state = State::Running;
		// Grace period: the player who woke the dimension is still on the way
		d.last_active = porting::getTimeMs();
	}
	actionstream << "DimensionHost: dimension \"" << dimension
		<< "\" listens on port " << port << std::endl;
	return true;
}

void DimensionHost::stopServer(const std::string &dimension)
{
	std::unique_ptr<Server> server;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		auto it = m_dims.find(dimension);
		if (it == m_dims.end())
			return;
		server = std::move(it->second.server);
	}

	// Saves the map and stops all threads of the dimension (slow, so it is
	// done without holding the lock)
	if (server) {
		actionstream << "DimensionHost: dimension \"" << dimension
			<< "\" is empty, stopping its server" << std::endl;
		server.reset();
	}

	std::lock_guard<std::mutex> lock(m_mutex);
	Dim &d = m_dims[dimension];
	d.state = State::Stopped;
	if (d.restart_after_stop && !m_stopping) {
		// Somebody wanted to enter the dimension while it was shutting down
		d.restart_after_stop = false;
		d.state = State::Starting;
		d.last_active = porting::getTimeMs();
		m_tasks.push_back({true, dimension});
		m_cond.notify_one();
	}
}

void DimensionHost::copyMediaToClientCache(Server *server)
{
	// Lets the host's own client skip downloading media it can read from disk
	u32 n = 0;
	for (auto &it : server->getMediaList()) {
		if (it.first.size() == 20 && clientMediaUpdateCacheCopy(it.first, it.second))
			n++;
	}
	infostream << "Copied " << n << " files directly from server to client cache"
		<< std::endl;
}

void DimensionHost::queueDimension(const std::string &dimension)
{
	// May be called from a server thread. Only reserves a port, the server
	// itself starts when somebody wants to go there.
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		if (m_stopping || !m_started || m_dims.count(dimension))
			return;
		if (!registerLocked(dimension))
			return;
	}
	publishSetting();
}

bool DimensionHost::start(std::string &error)
{
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		Dim &d = m_dims[dimension::DEFAULT_NAME];
		d.port = m_base_port;
		d.state = State::Starting;
	}

	m_had_old_setting = g_settings->getNoEx("dimension_servers", m_old_setting);
	m_setting_saved = true;
	publishSetting();

	if (!startServer(dimension::DEFAULT_NAME, error)) {
		stop();
		return false;
	}

	{
		std::lock_guard<std::mutex> lock(m_mutex);
		m_started = true;
	}
	// Dimensions that already exist, or were created by mods while the main
	// one was loading: reserve their ports (no servers are started)
	for (const std::string &name : dimension::list(m_world_path))
		queueDimension(name);
	publishSetting();

	m_worker = std::thread([this] { workerMain(); });
	return true;
}

void DimensionHost::workerMain()
{
	while (true) {
		Task task;
		{
			std::unique_lock<std::mutex> lock(m_mutex);
			m_cond.wait(lock, [this] { return m_stopping || !m_tasks.empty(); });
			if (m_stopping)
				return;
			task = m_tasks.front();
			m_tasks.pop_front();
		}

		if (!task.start) {
			stopServer(task.name);
			continue;
		}

		std::string error;
		if (!startServer(task.name, error)) {
			errorstream << "DimensionHost: could not start " << error << std::endl;
			std::lock_guard<std::mutex> lock(m_mutex);
			Dim &d = m_dims[task.name];
			d.state = State::Failed;
			d.error = error;
		}
	}
}

std::string DimensionHost::wake(const std::string &dimension)
{
	bool publish = false;
	std::string result;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		if (m_stopping || !m_started)
			return "failed:the host is not ready";

		auto it = m_dims.find(dimension);
		if (it == m_dims.end()) {
			// Created behind our back (not announced by a server)
			if (!dimension::exists(m_world_path, dimension))
				return "failed:unknown world \"" + dimension + "\"";
			if (!registerLocked(dimension))
				return "failed:no free port for the world \"" + dimension + "\"";
			it = m_dims.find(dimension);
			publish = true;
		}

		Dim &d = it->second;
		const u64 now = porting::getTimeMs();
		switch (d.state) {
		case State::Running:
			d.last_active = now;
			result = "ready";
			break;
		case State::Starting:
			result = "starting";
			break;
		case State::Stopping:
			d.restart_after_stop = true;
			result = "starting";
			break;
		case State::Failed:
			// Report the error once, the next call tries again
			d.state = State::Stopped;
			result = "failed:" + d.error;
			break;
		case State::Stopped:
			d.state = State::Starting;
			d.last_active = now;
			m_tasks.push_back({true, dimension});
			m_cond.notify_one();
			result = "starting";
			break;
		}
	}
	if (publish)
		publishSetting();
	return result;
}

void DimensionHost::step()
{
	const u64 now = porting::getTimeMs();
	const float idle_ms = idleTimeout() * 1000.0f;
	std::vector<Server *> servers;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		const bool check_idle = now - m_last_idle_check >= 1000;
		if (check_idle)
			m_last_idle_check = now;

		for (auto &it : m_dims) {
			Dim &d = it.second;
			if (d.state != State::Running || !d.server)
				continue;
			servers.push_back(d.server.get());

			if (!check_idle || idle_ms <= 0.0f ||
					it.first == dimension::DEFAULT_NAME)
				continue;
			if (d.server->getConnectedClientCount() > 0) {
				d.last_active = now;
			} else if (now - d.last_active > idle_ms) {
				// Only the worker destroys a server, and only after this
				// state change, which is made on this thread: the pointers
				// collected above stay valid until we return.
				d.state = State::Stopping;
				m_tasks.push_back({false, it.first});
				m_cond.notify_one();
			}
		}
	}
	// Outside the lock: rethrows fatal errors of the servers
	for (Server *server : servers)
		server->step();
}

bool DimensionHost::isShutdownRequested() const
{
	std::lock_guard<std::mutex> lock(m_mutex);
	for (const auto &it : m_dims) {
		if (it.second.server && it.second.state == State::Running &&
				it.second.server->isShutdownRequested())
			return true;
	}
	return false;
}

void DimensionHost::stop()
{
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		m_stopping = true;
		m_cond.notify_all();
	}
	if (m_worker.joinable())
		m_worker.join();

	// Stop the other dimensions first, the main one last
	std::vector<std::unique_ptr<Server>> servers;
	std::unique_ptr<Server> main_server;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		for (auto &it : m_dims) {
			if (!it.second.server)
				continue;
			if (it.first == dimension::DEFAULT_NAME)
				main_server = std::move(it.second.server);
			else
				servers.push_back(std::move(it.second.server));
		}
		m_dims.clear();
		m_tasks.clear();
	}
	servers.clear();
	main_server.reset();

	if (g_settings && m_setting_saved) {
		if (m_had_old_setting)
			g_settings->set("dimension_servers", m_old_setting);
		else
			g_settings->remove("dimension_servers");
	}
	m_setting_saved = false;
}
