/*
 * bpfif.h - BSD/BPF raw-Ethernet backend for dhcpcd-1
 *
 * Replaces dhcpcd's upstream Linux SOCK_PACKET raw-packet layer.
 * dhcpSocket stays a plain file descriptor after bpfOpenForInterface():
 * client.c and arp.c read()/write()/select() on it exactly as they did
 * on the Linux socket fd before this port.
 */

#ifndef BPFIF_H
#define BPFIF_H

int bpfOpenForInterface(const char *ifname, unsigned char hwaddr[6]);
int bpfSendFrame(int bpf_fd, const void *frame, int framelen);
int bpfRecvFrame(int bpf_fd, void *frame, int frame_max);

#endif /* BPFIF_H */
