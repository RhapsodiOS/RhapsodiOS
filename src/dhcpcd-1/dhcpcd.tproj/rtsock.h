/*
 * rtsock.h - BSD routing-socket default route for dhcpcd-1
 *
 * Replaces upstream dhcpcd's Linux SIOCADDRT/struct rtentry code in
 * dhcpConfig(). Addresses are in network byte order.
 */

#ifndef RTSOCK_H
#define RTSOCK_H

int rtsockAddDefault(unsigned int gateway, unsigned int ifaddr);

#endif /* RTSOCK_H */
