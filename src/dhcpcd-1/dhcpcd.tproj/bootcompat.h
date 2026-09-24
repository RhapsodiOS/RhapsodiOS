/*
 * bootcompat.h - bootpc-compatible boot-time status output for dhcpcd-1
 *
 * 0800_Network captures dhcpcd's stdout via `config=$(dhcpcd -w "$if")`
 * exactly as it captures bootpc's today, then feeds it to SetNetConfig.
 * bootcompatPrint() reproduces the subset of bootpc's key=value output
 * 0800_Network actually reads back (ip_address, subnet_mask, router,
 * host_name, server_ip_address).
 */

#ifndef BOOTCOMPAT_H
#define BOOTCOMPAT_H

void bootcompatPrint(void);

#endif /* BOOTCOMPAT_H */
