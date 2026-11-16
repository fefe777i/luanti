// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include "irrlichttypes.h"
#include "address.h"
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>

class Address;

void sockets_init();
void sockets_cleanup();

/*
	A datagram endpoint inside this process that takes the place of an OS
	socket (see UDPSocket::attachVirtual() and udprouter.h): several servers of
	one process can share one public UDP port, a router hands each of them the
	datagrams of "its" clients.
*/
class VirtualEndpoint
{
public:
	// Called for every datagram the owner of the endpoint sends
	using SendFn = std::function<void(const Address &to, const void *data, int size)>;

	explicit VirtualEndpoint(SendFn send) : m_send(std::move(send)) {}

	// Router -> owner. Drops the datagram if the queue is full or closed.
	void push(const Address &from, const void *data, int size);
	// Owner -> router
	void send(const Address &to, const void *data, int size);
	// Waits up to timeout_ms for a datagram, returns true if there is one
	bool waitData(int timeout_ms);
	// Returns -1 if there is no datagram (the datagram is cut to `size`)
	int receive(Address &from, void *data, int size);
	// The owner is gone: wakes up readers, drops everything
	void close();
	bool isClosed() const;

private:
	struct Datagram
	{
		Address from;
		std::vector<u8> data;
	};

	mutable std::mutex m_mutex;
	std::condition_variable m_cond;
	std::deque<Datagram> m_queue;
	SendFn m_send;
	bool m_closed = false;
};

class UDPSocket
{
public:
	UDPSocket() = default;
	UDPSocket(bool ipv6); // calls init()
	~UDPSocket();
	bool init(bool ipv6, bool noExceptions = false);

	void Bind(Address addr);

	void Send(const Address &destination, const void *data, int size);
	// Returns -1 if there is no data
	int Receive(Address &sender, void *data, int size);
	void setTimeoutMs(int timeout_ms);
	// Returns true if there is data, false if timeout occurred
	bool WaitData(int timeout_ms);

	// Debugging purposes only
	int GetHandle() const { return m_handle; };

	// From now on this socket exchanges datagrams with a virtual endpoint
	// instead of the network (Bind() then does nothing).
	void attachVirtual(std::shared_ptr<VirtualEndpoint> endpoint);

	// A server that is told to listen on `port` while a virtual endpoint is
	// registered for it, uses that endpoint and does not bind the port.
	static void registerVirtual(u16 port, std::shared_ptr<VirtualEndpoint> endpoint);
	static void unregisterVirtual(u16 port);
	static std::shared_ptr<VirtualEndpoint> findVirtual(u16 port);

private:
	std::shared_ptr<VirtualEndpoint> getVirtual() const;

	std::shared_ptr<VirtualEndpoint> m_virtual;
	mutable std::mutex m_virtual_mutex;
	int m_handle = -1;
	int m_timeout_ms = -1;
	unsigned short m_addr_family = 0;
};
