/*
 * bpfif.h - BSD/BPF raw-Ethernet backend for dhcpcd-1
 *
 * Replaces dhcpcd's upstream Linux SOCK_PACKET raw-packet layer.
 * dhcpSocket stays a plain file descriptor. Callers send and receive
 * through bpfSendFrame()/bpfRecvFrame(), and wait with bpfPeek() rather
 * than peekfd(): one read() can return several frames, and select()
 * cannot see the ones still buffered here.
 */

#ifndef BPFIF_H
#define BPFIF_H

int bpfOpenForInterface(const char *ifname, unsigned char hwaddr[6]);
int bpfSendFrame(int bpf_fd, const void *frame, int framelen);
int bpfRecvFrame(int bpf_fd, void *frame, int frame_max);
int bpfPeek(int bpf_fd, int tv_usec);

#endif /* BPFIF_H */
