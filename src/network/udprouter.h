// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "irrlichttypes.h"
#include "address.h"
#include "socket.h"
#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

/*
	One public UDP port for all dimensions of a hosted world.

	The router owns the public socket. Every dimension server of the process
	gets a VirtualEndpoint instead of a port of its own, and the router hands
	each datagram to the endpoint of the dimension the sender belongs to.
	Servers see the real address of their clients, and everything they send
	leaves through the public socket, so the whole world is reachable through
	one port (one playit.gg tunnel, one forwarded port, ...).

	A client that connects normally lands in the main dimension. A client that
	is moved to another dimension (TOCLIENT_TRANSFER with a dimension name)
	connects again and starts with a small "hello" datagram that names the
	dimension. The router answers it, and from then on routes that sender to
	the server of that dimension. Datagrams of the normal protocol start with
	the protocol id, "hello" ones with "WS47", so they never get mixed up.
*/
namespace udprouter
{

constexpr u8 PKT_HELLO = 1; // client -> router: I want dimension X
constexpr u8 PKT_ACK = 2;   // router -> client: ok, you are connected to X
constexpr u8 PKT_REFUSED = 3; // router -> client: X is not running (yet)

// Datagram: "WS47", type, name length, name
std::vector<u8> makePacket(u8 type, const std::string &dimension);
// Returns false if the datagram is not a router datagram
bool parsePacket(const void *data, int size, u8 &type, std::string &dimension);

class Router
{
public:
	// Binds the public socket (throws SocketException on failure)
	Router(const Address &bind_addr, const std::string &main_dimension);
	~Router();

	void start();
	void stop();

	// Creates the endpoint a server of the dimension listens on
	std::shared_ptr<VirtualEndpoint> addBackend(const std::string &dimension);
	// The server of the dimension is gone: its clients are forgotten
	void removeBackend(const std::string &dimension);

	u16 getPort() const { return m_port; }

private:
	struct Session
	{
		std::string dimension;
		u64 last_seen = 0; // ms
	};

	void threadMain();
	void handleHello(const Address &from, const std::string &dimension);
	void routeDatagram(const Address &from, const void *data, int size);
	void sendRaw(const Address &to, const void *data, int size);
	void expireSessions(u64 now);
	static std::string sessionKey(const Address &addr);

	UDPSocket m_socket;
	u16 m_port;
	std::string m_main;

	std::mutex m_mutex;
	std::map<std::string, std::shared_ptr<VirtualEndpoint>> m_backends;
	std::map<std::string, Session> m_sessions;
	u64 m_last_expire = 0;

	std::thread m_thread;
	std::atomic<bool> m_stop{false};
};

}
