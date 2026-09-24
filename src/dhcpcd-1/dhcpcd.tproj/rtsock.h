/*
 * rtsock.h - BSD routing-socket default route for dhcpcd-1
 *
 * Replaces upstream dhcpcd's Linux SIOCADDRT/struct rtentry code in
 * dhcpConfig(). Addresses are in network byte order.
 * A router outside the leased subnet is not supported: this kernel's
 * route add looks up the destination, not the gateway, so it fails
 * with ENETUNREACH.
 */

#ifndef RTSOCK_H
#define RTSOCK_H

int rtsockAddDefault(unsigned int gateway);

#endif /* RTSOCK_H */
