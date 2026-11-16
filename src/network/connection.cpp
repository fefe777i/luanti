// Minetest
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "network/connection.h"
#include "network/mtp/impl.h"
#include "constants.h"
#include "settings.h"

namespace con
{

float getConfiguredConnectionTimeout()
{
	float seconds = CONNECTION_TIMEOUT;
	if (g_settings && g_settings->exists("connection_timeout"))
		seconds = std::max<float>(seconds, g_settings->getFloat("connection_timeout"));
	return seconds;
}

IConnection *createMTP(float timeout, bool ipv6, PeerHandler *handler)
{
	// safe minimum across internet networks for ipv4 and ipv6
	constexpr u32 MAX_PACKET_SIZE = 512;
	return new con::Connection(MAX_PACKET_SIZE, timeout, ipv6, handler);
}

}
