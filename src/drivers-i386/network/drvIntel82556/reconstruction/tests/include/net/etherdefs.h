#ifndef _ETHERDEFS_
#define _ETHERDEFS_

typedef struct {
    unsigned char ether_addr_octet[6];
} enet_addr_t;

typedef struct ether_header ether_header_t;

#endif
