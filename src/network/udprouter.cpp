// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "udprouter.h"
#include "log.h"
#include "networkexceptions.h"
#include "porting.h"
#include <cstring>

namespace udprouter
{

namespace {
const u8 MAGIC[4] = {'W', 'S', '4', '7'};
// A sender that has been silent for this long is forgotten (the protocol
// itself drops silent peers after 30 s)
constexpr u64 SESSION_TIMEOUT_MS = 120000;
constexpr int RECEIVE_BUFFER = 65536;
}

std::vector<u8> makePacket(u8 type, const std::string &dimension)
{
	const size_t len = std::min<size_t>(dimension.size(), 255);
	std::vector<u8> out;
	out.reserve(6 + len);
	out.insert(out.end(), MAGIC, MAGIC + 4);
	out.push_back(type);
	out.push_back((u8)len);
	out.insert(out.end(), dimension.begin(), dimension.begin() + len);
	return out;
}

bool parsePacket(const void *data, int size, u8 &type, std::string &dimension)
{
	if (size < 6 || memcmp(data, MAGIC, 4) != 0)
		return false;
	const u8 *p = (const u8 *)data;
	const int len = p[5];
	if (size < 6 + len)
		return false;
	type = p[4];
	dimension.assign((const char *)p + 6, len);
	return true;
}

Router::Router(const Address &bind_addr, const std::string &main_dimension) :
	m_socket(bind_addr.isIPv6()),
	m_port(bind_addr.getPort()),
	m_main(main_dimension)
{
	m_socket.Bind(bind_addr);
	// Only the router thread reads from the socket; the timeout is how often
	// it notices that it has to stop
	m_socket.setTimeoutMs(250);
}

Router::~Router()
{
	stop();
}

void Router::start()
{
	if (m_thread.joinable())
		return;
	m_stop = false;
	m_thread = std::thread([this] { threadMain(); });
}

void Router::stop()
{
	m_stop = true;
	if (m_thread.joinable())
		m_thread.join();
}

std::shared_ptr<VirtualEndpoint> Router::addBackend(const std::string &dimension)
{
	auto endpoint = std::make_shared<VirtualEndpoint>(
		[this](const Address &to, const void *data, int size) {
			sendRaw(to, data, size);
		});
	std::lock_guard<std::mutex> lock(m_mutex);
	auto it = m_backends.find(dimension);
	if (it != m_backends.end())
		it->second->close();
	m_backends[dimension] = endpoint;
	return endpoint;
}

void Router::removeBackend(const std::string &dimension)
{
	std::lock_guard<std::mutex> lock(m_mutex);
	auto it = m_backends.find(dimension);
	if (it == m_backends.end())
		return;
	it->second->close();
	m_backends.erase(it);
	for (auto s = m_sessions.begin(); s != m_sessions.end();) {
		if (s->second.dimension == dimension)
			s = m_sessions.erase(s);
		else
			++s;
	}
}

std::string Router::sessionKey(const Address &addr)
{
	return addr.serializeString() + ":" + std::to_string(addr.getPort());
}

void Router::sendRaw(const Address &to, const void *data, int size)
{
	try {
		m_socket.Send(to, data, size);
	} catch (const SendFailedException &) {
		// Like any lost datagram
	}
}

void Router::handleHello(const Address &from, const std::string &dimension)
{
	u8 reply;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		auto it = m_backends.find(dimension);
		if (it == m_backends.end() || it->second->isClosed()) {
			reply = PKT_REFUSED;
		} else {
			Session &s = m_sessions[sessionKey(from)];
			s.dimension = dimension;
			s.last_seen = porting::getTimeMs();
			reply = PKT_ACK;
		}
	}
	const std::vector<u8> pkt = makePacket(reply, dimension);
	sendRaw(from, pkt.data(), (int)pkt.size());
}

void Router::routeDatagram(const Address &from, const void *data, int size)
{
	std::shared_ptr<VirtualEndpoint> target;
	{
		std::lock_guard<std::mutex> lock(m_mutex);
		const u64 now = porting::getTimeMs();
		const std::string key = sessionKey(from);
		auto s = m_sessions.find(key);
		if (s != m_sessions.end()) {
			auto b = m_backends.find(s->second.dimension);
			if (b != m_backends.end() && !b->second->isClosed()) {
				s->second.last_seen = now;
				target = b->second;
			} else {
				m_sessions.erase(s);
			}
		}
		if (!target) {
			// Somebody new (or whose world is gone): the main dimension
			auto b = m_backends.find(m_main);
			if (b == m_backends.end() || b->second->isClosed())
				return;
			Session &ns = m_sessions[key];
			ns.dimension = m_main;
			ns.last_seen = now;
			target = b->second;
		}
	}
	target->push(from, data, size);
}

void Router::expireSessions(u64 now)
{
	if (now - m_last_expire < 5000)
		return;
	m_last_expire = now;
	std::lock_guard<std::mutex> lock(m_mutex);
	for (auto s = m_sessions.begin(); s != m_sessions.end();) {
		if (now - s->second.last_seen > SESSION_TIMEOUT_MS)
			s = m_sessions.erase(s);
		else
			++s;
	}
}

void Router::threadMain()
{
	std::vector<u8> buffer(RECEIVE_BUFFER);
	while (!m_stop) {
		try {
			Address from;
			const int n = m_socket.Receive(from, buffer.data(), (int)buffer.size());
			expireSessions(porting::getTimeMs());
			if (n < 0)
				continue;

			u8 type;
			std::string dimension;
			if (parsePacket(buffer.data(), n, type, dimension)) {
				if (type == PKT_HELLO)
					handleHello(from, dimension);
				continue;
			}
			routeDatagram(from, buffer.data(), n);
		} catch (const std::exception &e) {
			warningstream << "UDP router: " << e.what() << std::endl;
		}
	}
}

}
