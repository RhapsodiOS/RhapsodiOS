/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * BPF.m
 * Berkeley Packet Filter (BPF) DriverKit Implementation
 *
 * This driver provides an DriverKit wrapper for the BSD BPF subsystem.
 */

#import "BPF.h"
#import <driverkit/generalFuncs.h>
#import <string.h>

/* External references to BPF kernel globals */
extern int bpf_bufsize;
extern void *bpf_dtab;
extern void *bpf_iflist_enodev;
extern void *mbstat;
extern void *mbutl;
extern void *mclfree;
extern void *mclrefcnt;
extern void *mfree;
extern int nbpfilter;
extern void *nulldev;
extern int tick;
extern void *bpfops;
extern void *enodev;

/* External BPF globals */
extern void *bpf_iflist;

/*
 * Set or clear promiscuous mode on interface
 * Returns 0 on success, error code on failure
 */
static int ifpromisc(int ifp, int pswitch)
{
    int result;
    unsigned char local_24[16];
    unsigned short local_14;

    /* Check if IFF_UP flag is set */
    if ((*(unsigned char *)(ifp + 0x1a) & 1) == 0) {
        return 0x32;  /* EINVAL */
    }

    if (pswitch == 0) {
        /* Disabling promiscuous mode */
        *(int *)(ifp + 0xc) = *(int *)(ifp + 0xc) - 1;
        if (*(int *)(ifp + 0xc) < 1) {
            /* Clear IFF_PROMISC flag */
            *(unsigned short *)(ifp + 0x1a) = *(unsigned short *)(ifp + 0x1a) & 0xfeff;
            goto call_ioctl;
        }
    } else {
        /* Enabling promiscuous mode */
        *(int *)(ifp + 0xc) = *(int *)(ifp + 0xc) + 1;
        if (*(int *)(ifp + 0xc) == 1) {
            /* Set IFF_PROMISC flag */
            *(unsigned short *)(ifp + 0x1a) = *(unsigned short *)(ifp + 0x1a) | 0x100;
call_ioctl:
            local_14 = *(unsigned short *)(ifp + 0x1a);
            result = (**(int (**)(int, int, unsigned char *))(ifp + 0x74))(ifp, 0x80206910, local_24);
            return result;
        }
    }
    return 0;
}

/*
 * Catch a packet and store it in the BPF buffer
 */
static void catchpacket(int *d, void *pkt, unsigned int pktlen, unsigned int snaplen,
                       void (*cpfn)(const void *, void *, unsigned int))
{
    int hdrlen;
    int caplen;
    unsigned int slen_aligned;
    int *bpf_hdr;
    unsigned int totlen;

    /* Get BPF header length from interface */
    hdrlen = *(int *)(*(int *)((int)d + 0x1c) + 0x10);  /* d->bd_bif->bif_hdrlen */

    /* Determine actual capture length */
    if (pktlen < snaplen) {
        snaplen = pktlen;
    }

    /* Calculate total capture length (header + data) */
    totlen = snaplen + hdrlen;
    if (*(int *)((int)d + 0x18) < (int)totlen) {  /* bd_bufsize */
        totlen = *(int *)((int)d + 0x18);
    }
    caplen = totlen - hdrlen;

    /* Align store buffer length to 4-byte boundary */
    slen_aligned = (*(int *)((int)d + 0x10) + 3) & 0xfffffffc;  /* (bd_slen + 3) & ~3 */

    /* Check if packet fits in current store buffer */
    if (*(int *)((int)d + 0x18) < (int)(totlen + slen_aligned)) {  /* bd_bufsize */
        /* Buffer full - need to rotate buffers */
        if (*(int *)((int)d + 0xc) == 0) {  /* bd_sbuf == NULL */
            /* No free buffer available, drop packet */
            *(int *)((int)d + 0x2c) = *(int *)((int)d + 0x2c) + 1;  /* ps_drop++ */
            return;
        }

        /* Rotate buffers: free -> hold, store -> free */
        *(int *)((int)d + 8) = *(int *)((int)d + 4);     /* bd_hbuf = bd_fbuf */
        *(int *)((int)d + 0x14) = *(int *)((int)d + 0x10);  /* bd_hlen = bd_slen */
        *(int *)((int)d + 4) = *(int *)((int)d + 0xc);   /* bd_fbuf = bd_sbuf */
        *(int *)((int)d + 0x10) = 0;  /* bd_slen = 0 */
        *(int *)((int)d + 0xc) = 0;   /* bd_sbuf = NULL */

        /* Wake up any readers waiting for data */
        wakeup(d);
        selwakeup((void *)((int)d + 0x34));  /* &d->bd_sel */
        *(int *)((int)d + 0x34) = 0;

        slen_aligned = 0;
    } else if (*(char *)((int)d + 0x32) != 0) {  /* bd_immediate */
        /* Immediate mode - wake up readers even if buffer not full */
        wakeup(d);
        selwakeup((void *)((int)d + 0x34));
        *(int *)((int)d + 0x34) = 0;
    }

    /* Calculate position to write BPF packet header */
    bpf_hdr = (int *)(slen_aligned + *(int *)((int)d + 4));  /* bd_fbuf + slen_aligned */

    /* Fill in BPF packet header */
    microtime(bpf_hdr);  /* bh_timestamp */
    bpf_hdr[3] = pktlen;  /* bh_wirelen */
    *(unsigned short *)((int)bpf_hdr + 0x10) = (unsigned short)hdrlen;  /* bh_hdrlen */
    bpf_hdr[2] = caplen;  /* bh_caplen */

    /* Copy packet data after header */
    (*cpfn)(pkt, (void *)((int)bpf_hdr + hdrlen), caplen);

    /* Update store buffer length */
    *(int *)((int)d + 0x10) = slen_aligned + totlen;  /* bd_slen */
}

/*
 * Extract a 16-bit halfword from an mbuf chain at offset k
 */
static unsigned short m_xhalf(int *m, int k, int *err)
{
    int mlen;
    int mdata;
    int next;
    unsigned short result;

    while (m != NULL) {
        mlen = m[2];  /* m->m_len */

        if (k < mlen) {
            mdata = m[3];  /* m->m_data */

            if (1 < mlen - k) {
                /* Halfword is entirely within this mbuf */
                *err = 0;
                result = *(unsigned short *)(k + mdata);
                return (result >> 8) | (result << 8);
            }

            /* Halfword spans mbufs */
            next = *m;  /* m->m_next */
            if (next != 0) {
                *err = 0;
                /* First byte from current mbuf, second byte from next */
                return (*(unsigned char *)(k + mdata) << 8) |
                       *(unsigned char *)(*(int *)(next + 0xc));
            }
            break;
        }

        k = k - mlen;
        m = (int *)*m;  /* m = m->m_next */
    }

    *err = 1;
    return 0;
}

/*
 * Extract a 32-bit word from an mbuf chain at offset k
 */
static unsigned int m_xword(int *m, int k, int *err)
{
    int mlen;
    int mdata;
    int next;
    unsigned int *pword;
    unsigned char *pb;
    unsigned int result;

    while (m != NULL) {
        mlen = m[2];  /* m->m_len */

        if (k < mlen) {
            pword = (unsigned int *)(k + m[3]);  /* k + m->m_data */

            if (3 < mlen - k) {
                /* Word is entirely within this mbuf */
                *err = 0;
                result = *pword;
                return (result >> 24) | ((result & 0xff0000) >> 8) |
                       ((result & 0xff00) << 8) | (result << 24);
            }

            /* Word spans mbufs */
            next = *m;  /* m->m_next */
            if ((next != 0) && (3 < (mlen + *(int *)(next + 8)) - k)) {
                *err = 0;
                pb = *(unsigned char **)(next + 0xc);  /* next->m_data */

                if (mlen - k == 1) {
                    /* 1 byte in current, 3 in next */
                    return ((unsigned int)pb[2]) |
                           ((unsigned int)*(unsigned char *)(k + (int)pword) << 24) |
                           ((unsigned int)pb[0] << 16) |
                           ((unsigned int)pb[1] << 8);
                } else if (mlen - k == 2) {
                    /* 2 bytes in current, 2 in next */
                    return ((unsigned int)pb[1]) |
                           ((unsigned int)*(unsigned char *)(k + (int)pword) << 24) |
                           ((unsigned int)*(unsigned char *)((int)pword + k + 1) << 16) |
                           ((unsigned int)pb[0] << 8);
                } else {
                    /* 3 bytes in current, 1 in next */
                    return ((unsigned int)pb[0]) |
                           ((unsigned int)*(unsigned char *)(k + (int)pword) << 24) |
                           ((unsigned int)*(unsigned char *)((int)pword + k + 1) << 16) |
                           ((unsigned int)*(unsigned char *)((int)pword + k + 2) << 8);
                }
            }
            break;
        }

        k = k - mlen;
        m = (int *)*m;  /* m = m->m_next */
    }

    *err = 1;
    return 0;
}

/*
 * Allocate BPF buffers
 */
int bpf_allocbufs(int *d)
{
    int buf1;
    int buf2;

    buf1 = (int)MALLOC(d[6], 2, 0);  /* d->bd_bufsize at offset 0x18 */
    d[3] = buf1;  /* d->bd_sbuf at offset 0xc */

    if (buf1 != 0) {
        buf2 = (int)MALLOC(d[6], 2, 0);
        d[1] = buf2;  /* d->bd_hbuf at offset 0x4 */

        if (buf2 != 0) {
            d[4] = 0;  /* d->bd_slen at offset 0x10 */
            d[5] = 0;  /* d->bd_hlen at offset 0x14 */
            return 0;
        }

        FREE((void *)d[3], 2);
    }

    return 0x37;  /* ENOMEM */
}

/*
 * Attach a BPF descriptor to an interface
 */
void bpf_attachd(int *d, int *ifp)
{
    d[7] = (int)ifp;           /* d->bd_bif at offset 0x1c */
    d[0] = ifp[1];             /* d->bd_next = ifp->bif_dlist */
    ifp[1] = (int)d;           /* ifp->bif_dlist = d */
    *(int **)ifp[2] = ifp;     /* *ifp->driverp = ifp */
}

/*
 * Detach a BPF descriptor from an interface
 */
void bpf_detachd(int *d)
{
    int **p;
    int *pd;
    int *ifp;
    int result;

    ifp = (int *)d[7];  /* d->bd_bif */

    if (*(char *)((int)d + 0x30) != 0) {  /* d->bd_promisc */
        *(char *)((int)d + 0x30) = 0;
        result = ifpromisc((void *)ifp[5], 0);  /* ifp->bif_ifp at offset 0x14 */
        if (result != 0) {
            panic("bpf: ifpromisc failed");
        }
    }

    /* Remove d from the interface's descriptor list */
    p = (int **)&ifp[1];  /* &ifp->bif_dlist */
    pd = ifp[1];

    while (pd != NULL) {
        if (pd == d) {
            *p = (int *)d[0];  /* Remove from list */
            if (ifp[1] == 0) {
                *(int **)ifp[2] = 0;  /* Clear driverp if list empty */
            }
            d[7] = 0;  /* Clear bd_bif */
            return;
        }
        p = (int **)pd;
        pd = (int *)*p;
        if (pd == NULL) {
            break;
        }
    }

    panic("bpf_detachd: descriptor not in list");
}

/*
 * Reset a BPF descriptor's buffer state
 */
void reset_d(int *d)
{
    /* If hold buffer exists, move it to store buffer */
    if (*(int *)((int)d + 0x8) != 0) {
        *(int *)((int)d + 0xc) = *(int *)((int)d + 0x8);
        *(int *)((int)d + 0x8) = 0;
    }

    /* Clear buffer lengths */
    *(int *)((int)d + 0x10) = 0;  /* bd_slen */
    *(int *)((int)d + 0x14) = 0;  /* bd_hlen */

    /* Clear additional fields at offsets 0x28 and 0x2c */
    *(int *)((int)d + 0x28) = 0;
    *(int *)((int)d + 0x2c) = 0;
}

/*
 * Free BPF descriptor buffers and resources
 */
void bpf_freed(int *d)
{
    /* Free buffers if allocated */
    if (*(int *)((int)d + 0x4) != 0) {
        FREE((void *)*(int *)((int)d + 0x4), 2);

        if (*(int *)((int)d + 0x8) != 0) {
            FREE((void *)*(int *)((int)d + 0x8), 2);
        }

        if (*(int *)((int)d + 0xc) != 0) {
            FREE((void *)*(int *)((int)d + 0xc), 2);
        }
    }

    /* Free filter program if allocated */
    if (*(int *)((int)d + 0x24) != 0) {
        FREE((void *)*(int *)((int)d + 0x24), 2);
    }

    /* Mark descriptor as freed by pointing to itself */
    *d = (int)d;
}

/*
 * Construct interface name with unit number (e.g., "eth0")
 */
void bpf_ifname(char **ifp, char *name)
{
    char c;
    char *src;
    char *dst;

    src = *ifp;  /* Interface name base string */

    /* Copy interface name until null terminator */
    do {
        dst = name;
        c = *src;
        *dst = c;
        src = src + 1;
        name = dst + 1;
    } while (c != '\0');

    /* Append unit number as a digit character */
    dst[1] = *(char *)((int)ifp + 0x16) + '0';
    dst[2] = '\0';
}

/*
 * Copy data from an mbuf chain to a buffer
 */
void bpf_mcopy(int *m, void *buf, unsigned int len)
{
    unsigned int copylen;
    void *dst;

    dst = buf;

    if (len != 0) {
        do {
            if (m == NULL) {
                panic("bpf_mcopy");
            }

            /* Get length of current mbuf */
            copylen = (unsigned int)m[2];  /* m->m_len */

            /* Copy only what's needed */
            if (len < copylen) {
                copylen = len;
            }

            /* Copy from m->m_data to destination */
            bcopy((void *)m[3], dst, copylen);

            /* Move to next mbuf */
            m = (int *)*m;  /* m = m->m_next */

            /* Advance destination pointer */
            dst = (void *)((int)dst + copylen);

            /* Decrement remaining length */
            len = len - copylen;

        } while (len != 0);
    }
}

/*
 * BPF select operation - check if data is available for reading
 */
int bpf_select(unsigned char dev, int rw, void *p)
{
    int offset;
    int spl;

    /* Only support select for read (FREAD = 1) */
    if (rw == 1) {
        /* Calculate offset into bpf_dtab array (0x3c = 60 bytes per descriptor) */
        offset = (unsigned int)dev * 0x3c;

        spl = splimp();

        /* Check if data is available:
         * 1. Hold buffer has data (bd_hlen != 0)
         * 2. Immediate mode is set AND store buffer has data (bd_slen != 0)
         */
        if ((*(int *)((char *)&enodev + offset) != 0) ||
            ((*(char *)((int)&enodev + offset + 0x4e) != 0) &&
             (*(int *)((char *)&enodev + offset - 0x460) != 0))) {
            splx(spl);
            return 1;  /* Data is ready */
        }

        /* No data available, record the select */
        selrecord(p, (void *)((char *)&mfree + offset));
        splx(spl);
    }

    return 0;  /* No data available */
}

/*
 * Set BPF filter program for a descriptor
 */
int bpf_setf(int *d, unsigned int *fcode)
{
    int old_filter;
    int spl;
    void *new_filter;
    int size;
    int result;

    old_filter = *(int *)((int)d + 0x24);  /* bd_filter */

    /* Check if clearing the filter */
    if (fcode[1] == 0) {  /* bf_insns == NULL */
        if (*fcode == 0) {  /* bf_len == 0 */
            /* Clear filter */
            spl = splimp();
            *(int *)((int)d + 0x24) = 0;
            reset_d(d);
            splx(spl);

            /* Free old filter if it existed */
            if (old_filter != 0) {
                FREE((void *)old_filter, 2);
            }
            return 0;
        }
    } else if (*fcode < 0x201) {  /* bf_len < 513 instructions */
        /* Calculate size: bf_len * 8 (each BPF instruction is 8 bytes) */
        size = *fcode * 8;

        /* Allocate memory for new filter */
        new_filter = MALLOC(size, 2, 0);

        /* Copy filter from user space */
        result = copyin((void *)fcode[1], new_filter, size);

        if ((result == 0) && (result = bpf_validate(new_filter, *fcode), result != 0)) {
            /* Filter is valid, install it */
            spl = splimp();
            *(int *)((int)d + 0x24) = (int)new_filter;
            reset_d(d);
            splx(spl);

            /* Free old filter if it existed */
            if (old_filter != 0) {
                FREE((void *)old_filter, 2);
            }
            return 0;
        }

        /* Copy or validation failed, free new filter */
        FREE(new_filter, 2);
    }

    return 0x16;  /* EINVAL */
}

/*
 * BPF ioctl - handle device control operations
 */
int bpfioctl(unsigned char dev, unsigned int cmd, unsigned int *data)
{
    unsigned int *d;
    int result;
    int spl;
    unsigned int timeout_ms;
    int offset;
    int **ifp;

    offset = (unsigned int)dev * 0x3c;
    d = (unsigned int *)((char *)&bpf_dtab + offset);
    result = 0;

    switch (cmd) {
    case 0x4008426f:  /* BIOCGSTATS - Get statistics */
        data[0] = *(unsigned int *)((char *)&mbutl + offset);    /* ps_recv */
        data[1] = *(unsigned int *)((char *)&mclfree + offset);  /* ps_drop */
        return 0;

    case 0x4004426a:  /* BIOCGDLT - Get data link type */
        if (*(int *)((char *)&m_freem + offset) != 0) {
            *data = *(unsigned int *)(*(int *)((char *)&m_freem + offset) + 0xc);
            return 0;
        }
        break;

    case 0x20004269:  /* BIOCPROMISC - Set promiscuous mode */
        if (*(int *)((char *)&m_freem + offset) != 0) {
            spl = splimp();
            if (((char *)&mclrefcnt)[offset] == 0) {
                result = ifpromisc((void *)*(int *)(*(int *)((char *)&m_freem + offset) + 0x14), 1);
                if (result == 0) {
                    ((char *)&mclrefcnt)[offset] = 1;
                }
            }
            splx(spl);
            return result;
        }
        break;

    case 0x20004268:  /* BIOCFLUSH - Flush buffer */
        spl = splimp();
        reset_d((int *)d);
        splx(spl);
        return 0;

    case 0x40044266:  /* BIOCGBLEN - Get buffer length */
        *data = *(unsigned int *)((char *)&m_clalloc + offset);
        return 0;

    case 0x4004667f:  /* FIONREAD - Get available bytes */
        spl = splimp();
        timeout_ms = *(unsigned int *)((char *)&enodev + offset - 0x460);  /* bd_slen */
        if (*(int *)((char *)&bpfops + offset) != 0) {  /* bd_hbuf != NULL */
            timeout_ms = timeout_ms + *(int *)((char *)&enodev + offset);  /* + bd_hlen */
        }
        splx(spl);
        *data = timeout_ms;
        return 0;

    case 0x40044271:  /* BIOCGVERSION - Get BPF version */
        *(unsigned short *)data = 1;        /* bv_major */
        *(unsigned short *)((int)data + 2) = 1;  /* bv_minor */
        return 0;

    case 0x4008426e:  /* BIOCGRTIMEOUT - Get read timeout */
        timeout_ms = (tick / 1000) * *(int *)((char *)&m_retry + offset);
        data[0] = timeout_ms / 1000;        /* tv_sec */
        data[1] = timeout_ms % 1000;        /* tv_usec */
        return 0;

    case 0x8008426d:  /* BIOCSRTIMEOUT - Set read timeout */
        *(unsigned int *)((char *)&m_retry + offset) =
            ((int)data[1] / 1000 + data[0] * 1000) / (unsigned int)(tick / 1000);
        return 0;

    case 0x80044270:  /* BIOCSIMMEDIATE - Set immediate mode */
        ((char *)&bpf_dtab)[offset + 0x4e] = *(unsigned char *)data;
        return 0;

    case 0x4020426b:  /* BIOCGETIF - Get interface name */
        if (*(int *)((char *)&m_freem + offset) != 0) {
            ifp = (int **)*(int *)(*(int *)((char *)&m_freem + offset) + 0x14);
            bpf_ifname((char **)ifp, (char *)data);
            return 0;
        }
        break;

    case 0x80084267:  /* BIOCSF - Set filter */
        result = bpf_setf((int *)d, data);
        return result;

    case 0xc0044266:  /* BIOCSBLEN - Set buffer length */
        if (*(int *)((char *)&m_freem + offset) == 0) {
            timeout_ms = *data;
            if (timeout_ms > 0x8000) {
                timeout_ms = 0x8000;
                *data = 0x8000;
            } else if (timeout_ms < 0x20) {
                timeout_ms = 0x20;
                *data = 0x20;
            }
            *(unsigned int *)((char *)&m_clalloc + offset) = timeout_ms;
            return 0;
        }
        break;

    case 0x8020426c:  /* BIOCSETIF - Set interface */
        result = bpf_setif((int *)d, (char *)data);
        return result;

    case 0xc0206921:  /* SIOCGIFADDR - Pass through to interface */
        if (*(int *)((char *)&m_freem + offset) != 0) {
            ifp = (int **)*(int *)(*(int *)((char *)&m_freem + offset) + 0x14);
            result = (*(int (**)(int **, unsigned int, unsigned int *))
                      ((int)ifp + 0x74))(ifp, 0xc0206921, data);
            return result;
        }
        break;
    }

    return 0x16;  /* EINVAL */
}

/*
 * BPF write - inject a packet onto the network
 */
int bpfwrite(unsigned char dev, int *uio)
{
    int offset;
    int result;
    int *ifp;
    int spl;
    unsigned int datlen;
    void *mbuf;

    offset = (unsigned int)dev * 0x3c;

    /* Check if attached to an interface */
    if (*(int *)((char *)&m_freem + offset) == 0) {
        return 6;  /* ENXIO - not attached to interface */
    }

    /* Get interface pointer */
    ifp = (int *)*(int *)(*(int *)((char *)&m_freem + offset) + 0x14);

    /* Check if write size is zero */
    if (*(int *)((int)uio + 0x10) == 0) {  /* uio_resid */
        return 0;
    }

    /* Move packet from user space into mbuf */
    result = bpf_movein(uio,
                       *(int *)(*(int *)((char *)&m_freem + offset) + 0xc),  /* link type */
                       (int **)&mbuf,
                       (int *)0x4000,  /* sockaddr buffer */
                       (int *)&datlen);

    if (result == 0) {
        /* Check if packet exceeds interface MTU */
        if (*(unsigned int *)((int)ifp + 0x20) < datlen) {  /* if_mtu */
            return 0x28;  /* EMSGSIZE */
        }

        /* Send packet via interface output function */
        spl = splnet();
        result = (*(int (**)(int *, void *, int, int))((int)ifp + 0x68))
                 (ifp, mbuf, 0x4000, 0);  /* if_output */
        splx(spl);
    }

    return result;
}

/*
 * BPF read - read captured packets from BPF device
 */
int bpfread(unsigned char dev, char *uio)
{
    int offset;
    int result;
    int spl;

    offset = (unsigned int)dev * 0x3c;

    /* Check that read size matches buffer size */
    if (*(int *)((char *)&m_clalloc + offset) != *(int *)(uio + 0x10)) {
        return 0x16;  /* EINVAL */
    }

    spl = splimp();

    /* Wait for data to be available */
    while (1) {
        /* Check if hold buffer has data */
        if (*(int *)((char *)&bpfops + offset) != 0) {
            break;
        }

        /* Check if immediate mode and store buffer has data */
        if ((((char *)&bpf_dtab)[offset + 0x4e] != 0) &&
            (*(int *)((char *)&enodev + offset - 0x460) != 0)) {
            /* Rotate buffers: move store to hold */
            *(int *)((char *)&bpfops + offset) = *(int *)((char *)&bpf_iflist + offset);     /* bd_hbuf = bd_fbuf */
            *(int *)((char *)&enodev + offset) = *(int *)((char *)&enodev + offset - 0x460); /* bd_hlen = bd_slen */
            *(int *)((char *)&bpf_iflist + offset) = *(int *)((char *)&enodev + offset - 0x454); /* bd_fbuf = bd_sbuf */
            *(int *)((char *)&enodev + offset - 0x460) = 0;  /* bd_slen = 0 */
            *(int *)((char *)&enodev + offset - 0x454) = 0;  /* bd_sbuf = 0 */
            break;
        }

        /* Sleep waiting for data */
        result = tsleep((void *)((char *)&bpf_dtab + offset),
                       0x11a,  /* PZERO + 26 */
                       "bpf",
                       *(int *)((char *)&m_retry + offset));  /* bd_rtout */

        if ((result == 4) || (result == -1)) {  /* EINTR or timeout with no data */
            goto cleanup;
        }

        if (result == 0x23) {  /* EWOULDBLOCK - timeout */
            if (*(int *)((char *)&bpfops + offset) == 0) {
                if (*(int *)((char *)&enodev + offset - 0x460) == 0) {  /* bd_slen == 0 */
                    splx(spl);
                    return 0;  /* No data available */
                }

                /* Rotate buffers on timeout */
                *(int *)((char *)&bpfops + offset) = *(int *)((char *)&bpf_iflist + offset);
                *(int *)((char *)&enodev + offset) = *(int *)((char *)&enodev + offset - 0x460);
                *(int *)((char *)&bpf_iflist + offset) = *(int *)((char *)&enodev + offset - 0x454);
                *(int *)((char *)&enodev + offset - 0x460) = 0;
                *(int *)((char *)&enodev + offset - 0x454) = 0;
            }
            break;
        }
    }

    /* Copy data from hold buffer to user space */
    splx(spl);
    result = uiomove((void *)*(int *)((char *)&bpfops + offset),
                     *(int *)((char *)&enodev + offset),
                     (void *)uio);

    /* Rotate buffers: move hold to store */
    spl = splimp();
    *(int *)((char *)&enodev + offset - 0x454) = *(int *)((char *)&bpfops + offset);  /* bd_sbuf = bd_hbuf */
    *(int *)((char *)&bpfops + offset) = 0;  /* bd_hbuf = 0 */
    *(int *)((char *)&enodev + offset) = 0;  /* bd_hlen = 0 */

cleanup:
    splx(spl);
    return result;
}

/*
 * BPF open - called when a BPF device is opened
 */
int bpfopen(unsigned int dev)
{
    int offset;
    unsigned char minor;

    minor = dev & 0xff;

    /* Check if device number is valid */
    if ((int)minor < nbpfilter) {
        offset = minor * 0x3c;

        /* Check if descriptor is free (first pointer points to itself) */
        if (*(void **)((char *)&bpf_dtab + offset) == (void *)((char *)&bpf_dtab + offset)) {
            /* Initialize descriptor */
            bzero((void *)((char *)&bpf_dtab + offset), 0x3c);
            *(int *)((char *)&m_clalloc + offset) = bpf_bufsize;
            return 0;
        } else {
            return 0x10;  /* EBUSY - device already open */
        }
    }

    return 6;  /* ENXIO - device number out of range */
}

/*
 * BPF filter attach - stub for compatibility
 */
void bpfilterattach(void)
{
    /* Empty stub - actual initialization done elsewhere */
    return;
}

/*
 * BPF close - called when a BPF device is closed
 */
int bpfclose(unsigned char dev)
{
    int spl;
    int offset;

    /* Calculate offset into bpf_dtab array (0x3c = 60 bytes per descriptor) */
    offset = (unsigned int)dev * 0x3c;

    spl = splimp();

    /* Check if descriptor is attached to an interface (bd_bif != 0) */
    if (*(int *)((char *)&m_freem + offset) != 0) {
        bpf_detachd((int *)((char *)&bpf_dtab + offset));
    }

    splx(spl);

    /* Free all descriptor resources */
    bpf_freed((int *)((char *)&bpf_dtab + offset));

    return 0;
}

/*
 * Validate BPF filter program for safety
 */
int bpf_validate(void *fcode, int len)
{
    unsigned short *insn;
    unsigned int jmp_offset;
    int i;

    i = 0;

    /* Validate each instruction */
    if (len > 0) {
        do {
            insn = (unsigned short *)((int)fcode + i * 8);

            /* Check jump instructions (BPF_JMP class, opcode & 7 == 5) */
            if ((*insn & 7) == 5) {
                /* Check if unconditional jump (BPF_JA) */
                if ((*insn & 0xf0) == 0) {
                    /* Get jump offset from k field */
                    jmp_offset = *(unsigned int *)(insn + 2);
                } else {
                    /* Conditional jump - check jt (true) offset */
                    if (len <= (int)(((unsigned int)*(unsigned char *)(insn + 1) + i) + 1)) {
                        return 0;  /* Jump out of bounds */
                    }
                    /* Get jf (false) offset */
                    jmp_offset = (unsigned int)*(unsigned char *)((int)insn + 3);
                }

                /* Check that jump target is within program bounds */
                if (len <= (int)((i + 1) + jmp_offset)) {
                    return 0;  /* Jump out of bounds */
                }
            }

            /* Check store to memory (BPF_ST) or load from memory (BPF_LD|BPF_MEM) */
            if (((*insn & 7) == 2) ||  /* BPF_ST */
                ((*insn & 0xe7) == 0x60)) {  /* BPF_LD|BPF_MEM */
                /* Check memory index is valid (< 16) */
                if (0xf < *(unsigned int *)(insn + 2)) {
                    return 0;  /* Invalid memory index */
                }
            }

            /* Check divide by constant (BPF_DIV|BPF_K, opcode 0x34) */
            if ((*insn == 0x34) && (*(int *)(insn + 2) == 0)) {
                return 0;  /* Division by zero */
            }

            i++;
        } while (i < len);
    }

    /* Check that last instruction is a return (BPF_RET, opcode & 7 == 6) */
    return (unsigned int)((*(unsigned short *)((int)fcode + (len * 8) - 8) & 7) == 6);
}

/*
 * BPF tap - called when a packet arrives on an interface
 */
void bpf_tap(int *ifp, void *pkt, unsigned int pktlen)
{
    int *d;
    unsigned int snaplen;

    /* Iterate through all descriptors attached to this interface */
    for (d = *(int **)((int)ifp + 4); d != NULL; d = (int *)*d) {
        /* Increment packet statistics counter at offset 0x28 (index 10) */
        d[10] = d[10] + 1;

        /* Run the BPF filter on this packet */
        snaplen = bpf_filter((void *)*(int *)((int)d + 0x24), pkt, pktlen, pktlen);

        /* If filter matched (returned non-zero), capture the packet */
        if (snaplen != 0) {
            catchpacket(d, pkt, pktlen, snaplen, bcopy);
        }
    }
}

/*
 * Set interface for BPF descriptor
 */
int bpf_setif(int *d, char *ifname)
{
    char c;
    char **ifp_name;
    int **ifp;
    int result;
    int spl;
    char *p;
    int unit;

    /* Null-terminate interface name at position 15 */
    ifname[15] = '\0';

    /* Parse interface name and unit number */
    unit = 0;
    c = *ifname;
    p = ifname;

    /* Find start of unit number (first digit) */
    while (c != '\0') {
        if ((unsigned char)(p[1] - '0') < 10) {
            /* Found digit, extract unit number */
            unit = p[1] - '0';
            p[1] = '\0';  /* Terminate name before unit */
            p = p + 2;
            c = *p;

            /* Parse remaining digits */
            while (c != '\0') {
                unit = (c - '0') + unit * 10;
                p = p + 1;
                c = *p;
            }
            break;
        }
        p = p + 1;
        c = *p;
    }

    /* Search for matching interface in bpf_iflist */
    ifp = (int **)bpf_iflist;
    while (ifp != NULL) {
        ifp_name = (char **)ifp[5];  /* bif_ifp */

        if ((ifp_name != NULL) &&
            (unit == *(short *)((int)ifp_name + 0x16)) &&  /* if_unit */
            (strcmp(*ifp_name, ifname) == 0)) {  /* if_name */

            /* Check if interface is UP (IFF_UP flag at offset 0x1a) */
            if ((*(unsigned char *)((int)ifp_name + 0x1a) & 1) != 0) {
                /* Allocate buffers if not already done */
                if (*(int *)((int)d + 0x4) == 0) {  /* bd_hbuf */
                    result = bpf_allocbufs(d);
                    if (result != 0) {
                        return result;
                    }
                }

                spl = splimp();

                /* If already attached to a different interface, detach */
                if (*(int **)((int)d + 0x1c) != ifp) {  /* bd_bif */
                    if (*(int *)((int)d + 0x1c) != 0) {
                        bpf_detachd(d);
                    }
                    bpf_attachd(d, (int *)ifp);
                }

                /* Reset descriptor state */
                reset_d(d);
                splx(spl);

                return 0;
            }

            /* Interface exists but is down */
            return 0x32;  /* ENETDOWN */
        }

        /* Move to next interface in list */
        ifp = (int **)*ifp;
    }

    /* Interface not found */
    return 6;  /* ENXIO */
}

/*
 * Move packet data from user space into an mbuf
 */
int bpf_movein(int *uio, int linktype, int **mp, int *sockp, int *datlen)
{
    short *refcnt;
    unsigned int totlen;
    int spl;
    int **m;
    int result;
    int hdrlen;

    /* Determine header length based on link type */
    switch (linktype) {
    case 0:   /* DLT_NULL */
    case 9:   /* DLT_PPP */
        *(unsigned char *)(sockp + 1) = 0;
        hdrlen = 0;
        break;

    case 1:   /* DLT_EN10MB */
        *(unsigned char *)(sockp + 1) = 0;
        hdrlen = 14;  /* Ethernet header */
        break;

    case 8:   /* DLT_SLIP */
        *(unsigned char *)(sockp + 1) = 2;
        hdrlen = 0;
        break;

    case 10:  /* DLT_FDDI */
        *(unsigned char *)(sockp + 1) = 0;
        hdrlen = 24;  /* FDDI header */
        break;

    default:
        return 5;  /* EIO */
    }

    /* Get total length from uio structure */
    totlen = *(unsigned int *)((int)uio + 0x10);  /* uio_resid */
    *datlen = totlen - hdrlen;

    /* Check for oversized packet */
    if (totlen > 0x800) {  /* > 2048 bytes */
        return 5;  /* EIO */
    }

    /* Allocate mbuf from free list */
    spl = splimp();
    m = (int **)mfree;
    if (mfree != NULL) {
        refcnt = (short *)(mclrefcnt + ((int)mfree - mbutl >> 11) * 2);
        *refcnt = *refcnt + 1;
        mfree = (void *)*mfree;
    }
    splx(spl);

    /* If no mbuf available, try to allocate one */
    if (m == NULL) {
        m = (int **)m_retry(1, 1);
    } else {
        /* Initialize mbuf */
        m[1] = 0;           /* m_next */
        *m = 0;             /* m_nextpkt */
        *(short *)(m + 4) = 1;  /* m_type = MT_DATA */
        m[3] = (int *)(m + 5);  /* m_data */
        *(short *)((int)m + 0x12) = 0;  /* m_flags */
    }

    if (m == NULL) {
        return 0x37;  /* ENOBUFS */
    }

    /* Allocate cluster if packet is larger than MLEN (108 bytes) */
    if (totlen > 0x6c) {
        spl = splimp();
        m_clalloc(1, 1);
        result = mclfree;
        m[7] = (int *)mclfree;  /* m_ext.ext_buf */
        if (result != 0) {
            refcnt = (short *)(mclrefcnt + (result - mbutl >> 11) * 2);
            *refcnt = *refcnt + 1;
            mbstat = mbstat - 1;
            mclfree = *(int *)m[7];
        }
        splx(spl);

        if (m[7] != 0) {
            m[3] = m[7];  /* m_data = ext_buf */
            *(unsigned char *)((int)m + 0x12) = *(unsigned char *)((int)m + 0x12) | 1;  /* M_EXT */
            m[9] = (int *)0x800;  /* ext_size = 2048 */
            m[8] = 0;  /* ext_free */
            m[12] = m + 11;  /* ext_refs */
            m[11] = m + 11;  /* *ext_refs = ext_refs */
        }

        /* Check if cluster allocation succeeded */
        if ((*(unsigned char *)((int)m + 0x12) & 1) == 0) {
            result = 0x37;  /* ENOBUFS */
            goto cleanup;
        }
    }

    /* Set mbuf length */
    m[2] = (int *)totlen;

    /* Return mbuf */
    *mp = (int *)m;

    /* Copy link-level header if present */
    if (hdrlen != 0) {
        m[2] = (int *)((int)m[2] - hdrlen);
        m[3] = (int *)((int)m[3] + hdrlen);
        result = uiomove((void *)(sockp + 2), hdrlen, uio);
        if (result != 0) {
            goto cleanup;
        }
    }

    /* Copy packet data */
    result = uiomove(m[3], totlen - hdrlen, uio);
    if (result == 0) {
        return 0;
    }

cleanup:
    m_freem(m);
    return result;
}

/*
 * BPF filter interpreter - executes BPF bytecode
 */
unsigned int bpf_filter(void *pc, void *p, unsigned int wirelen, unsigned int buflen)
{
    unsigned int A = 0;        /* Accumulator */
    unsigned int X = 0;        /* Index register */
    unsigned int M[16];        /* Memory store */
    unsigned short *insn;
    unsigned int k;
    unsigned char jt, jf;
    unsigned int tmp;
    int err;
    void **m;
    int *mlen;

    if (pc == 0) {
        return 0xffffffff;
    }

    insn = (unsigned short *)((int)pc - 8);

    while (1) {
        insn += 4;  /* Move to next instruction */

        switch (insn[0]) {
        case 0x00:  /* BPF_LD|BPF_IMM */
            A = *(unsigned int *)(insn + 3);
            continue;

        case 0x01:  /* BPF_LDX|BPF_IMM */
            X = *(unsigned int *)(insn + 3);
            continue;

        case 0x02:  /* BPF_ST */
            M[*(unsigned int *)(insn + 3)] = A;
            continue;

        case 0x03:  /* BPF_STX */
            M[*(unsigned int *)(insn + 3)] = X;
            continue;

        case 0x04:  /* BPF_ALU|BPF_ADD|BPF_K */
            A = A + *(unsigned int *)(insn + 3);
            continue;

        case 0x05:  /* BPF_JMP|BPF_JA */
            insn += *(int *)(insn + 3) * 4;
            continue;

        case 0x06:  /* BPF_RET|BPF_K */
            return *(unsigned int *)(insn + 3);

        case 0x07:  /* BPF_MISC|BPF_TAX */
            X = A;
            continue;

        case 0x0c:  /* BPF_ALU|BPF_ADD|BPF_X */
            A = A + X;
            continue;

        case 0x14:  /* BPF_ALU|BPF_SUB|BPF_K */
            A = A - *(unsigned int *)(insn + 3);
            continue;

        case 0x15:  /* BPF_JMP|BPF_JEQ|BPF_K */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if (*(unsigned int *)(insn + 3) == A) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x16:  /* BPF_RET|BPF_A */
            return A;

        case 0x1c:  /* BPF_ALU|BPF_SUB|BPF_X */
            A = A - X;
            continue;

        case 0x1d:  /* BPF_JMP|BPF_JEQ|BPF_X */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if (X == A) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x20:  /* BPF_LD|BPF_ABS|BPF_W */
            k = *(unsigned int *)(insn + 3);
            if (buflen < k + 4) {
                if (buflen != 0) {
                    return 0;
                }
                A = m_xword((int *)p, k, &err);
                if (err != 0) {
                    return 0;
                }
            } else {
                tmp = *(unsigned int *)(k + (int)p);
                A = (tmp >> 24) | ((tmp & 0xff0000) >> 8) |
                    ((tmp & 0xff00) << 8) | (tmp << 24);
            }
            continue;

        case 0x24:  /* BPF_ALU|BPF_MUL|BPF_K */
            A = A * *(unsigned int *)(insn + 3);
            continue;

        case 0x25:  /* BPF_JMP|BPF_JGT|BPF_K */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if (A > *(unsigned int *)(insn + 3)) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x28:  /* BPF_LD|BPF_ABS|BPF_H */
            k = *(unsigned int *)(insn + 3);
            if (buflen < k + 2) {
                if (buflen != 0) {
                    return 0;
                }
                A = m_xhalf((int *)p, k, &err);
            } else {
                A = (unsigned int)(unsigned short)
                    ((*(unsigned short *)(k + (int)p) >> 8) |
                     (*(unsigned short *)(k + (int)p) << 8));
            }
            continue;

        case 0x2c:  /* BPF_ALU|BPF_MUL|BPF_X */
            A = A * X;
            continue;

        case 0x2d:  /* BPF_JMP|BPF_JGT|BPF_X */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if (X > A) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x30:  /* BPF_LD|BPF_ABS|BPF_B */
            k = *(unsigned int *)(insn + 3);
            if (k < buflen) {
                A = (unsigned int)*(unsigned char *)(k + (int)p);
            } else {
                if (buflen != 0) {
                    return 0;
                }
                m = (void **)p;
                mlen = ((int **)p)[2];
                while ((int)mlen <= (int)k) {
                    k = k - (int)mlen;
                    m = (void **)*m;
                    if (m == NULL) {
                        return 0;
                    }
                    mlen = ((int **)m)[2];
                }
                A = (unsigned int)*(unsigned char *)(k + (int)((int **)m)[3]);
            }
            continue;

        case 0x34:  /* BPF_ALU|BPF_DIV|BPF_K */
            A = A / *(unsigned int *)(insn + 3);
            continue;

        case 0x35:  /* BPF_JMP|BPF_JGE|BPF_K */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if (A >= *(unsigned int *)(insn + 3)) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x3c:  /* BPF_ALU|BPF_DIV|BPF_X */
            if (X == 0) {
                return 0;
            }
            A = A / X;
            continue;

        case 0x3d:  /* BPF_JMP|BPF_JGE|BPF_X */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if (X >= A) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x40:  /* BPF_LD|BPF_IND|BPF_W */
            k = X + *(unsigned int *)(insn + 3);
            if (buflen < k + 4) {
                if (buflen != 0) {
                    return 0;
                }
                A = m_xword((int *)p, k, &err);
                if (err != 0) {
                    return 0;
                }
            } else {
                tmp = *(unsigned int *)(k + (int)p);
                A = (tmp >> 24) | ((tmp & 0xff0000) >> 8) |
                    ((tmp & 0xff00) << 8) | (tmp << 24);
            }
            continue;

        case 0x44:  /* BPF_ALU|BPF_OR|BPF_K */
            A = A | *(unsigned int *)(insn + 3);
            continue;

        case 0x45:  /* BPF_JMP|BPF_JSET|BPF_K */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if ((*(unsigned int *)(insn + 3) & A) != 0) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x48:  /* BPF_LD|BPF_IND|BPF_H */
            k = X + *(unsigned int *)(insn + 3);
            if (buflen < k + 2) {
                if (buflen != 0) {
                    return 0;
                }
                A = m_xhalf((int *)p, k, &err);
                if (err != 0) {
                    return 0;
                }
            } else {
                A = (unsigned int)(unsigned short)
                    ((*(unsigned short *)(k + (int)p) >> 8) |
                     (*(unsigned short *)(k + (int)p) << 8));
            }
            continue;

        case 0x4c:  /* BPF_ALU|BPF_OR|BPF_X */
            A = A | X;
            continue;

        case 0x4d:  /* BPF_JMP|BPF_JSET|BPF_X */
            jt = *(unsigned char *)(insn + 2);
            jf = *(unsigned char *)((int)insn + 5);
            if ((X & A) != 0) {
                insn += jt * 4;
            } else {
                insn += jf * 4;
            }
            continue;

        case 0x50:  /* BPF_LD|BPF_IND|BPF_B */
            k = X + *(unsigned int *)(insn + 3);
            if (k < buflen) {
                A = (unsigned int)*(unsigned char *)(k + (int)p);
            } else {
                if (buflen != 0) {
                    return 0;
                }
                m = (void **)p;
                mlen = ((int **)p)[2];
                while ((int)mlen <= (int)k) {
                    k = k - (int)mlen;
                    m = (void **)*m;
                    if (m == NULL) {
                        return 0;
                    }
                    mlen = ((int **)m)[2];
                }
                A = (unsigned int)*(char *)(k + (int)((int **)m)[3]);
            }
            continue;

        case 0x54:  /* BPF_ALU|BPF_AND|BPF_K */
            A = A & *(unsigned int *)(insn + 3);
            continue;

        case 0x5c:  /* BPF_ALU|BPF_AND|BPF_X */
            A = A & X;
            continue;

        case 0x60:  /* BPF_LD|BPF_MEM */
            A = M[*(unsigned int *)(insn + 3)];
            continue;

        case 0x61:  /* BPF_LDX|BPF_MEM */
            X = M[*(unsigned int *)(insn + 3)];
            continue;

        case 0x64:  /* BPF_ALU|BPF_LSH|BPF_K */
            A = A << (*(unsigned int *)(insn + 3) & 0x1f);
            continue;

        case 0x6c:  /* BPF_ALU|BPF_LSH|BPF_X */
            A = A << (X & 0x1f);
            continue;

        case 0x74:  /* BPF_ALU|BPF_RSH|BPF_K */
            A = A >> (*(unsigned int *)(insn + 3) & 0x1f);
            continue;

        case 0x7c:  /* BPF_ALU|BPF_RSH|BPF_X */
            A = A >> (X & 0x1f);
            continue;

        case 0x80:  /* BPF_LD|BPF_LEN */
            A = wirelen;
            continue;

        case 0x81:  /* BPF_LDX|BPF_LEN */
            X = wirelen;
            continue;

        case 0x84:  /* BPF_ALU|BPF_NEG */
            A = -A;
            continue;

        case 0x87:  /* BPF_MISC|BPF_TXA */
            A = X;
            continue;

        case 0xb1:  /* BPF_LDX|BPF_MSH|BPF_B */
            k = *(unsigned int *)(insn + 3);
            if (k < buflen) {
                X = ((*(unsigned char *)(k + (int)p) & 0xf) << 2);
            } else {
                if (buflen != 0) {
                    return 0;
                }
                m = (void **)p;
                mlen = ((int **)p)[2];
                while ((int)mlen <= (int)k) {
                    k = k - (int)mlen;
                    m = (void **)*m;
                    if (m == NULL) {
                        return 0;
                    }
                    mlen = ((int **)m)[2];
                }
                X = ((*(unsigned char *)(k + (int)((int **)m)[3]) & 0xf) << 2);
            }
            continue;

        default:
            return 0;
        }
    }
}

@implementation BPF

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    BOOL result;
    id instance;

    result = [self addToCdevswFromDescription:deviceDescription
                                         open:bpfopen
                                        close:bpfclose
                                         read:bpfread
                                        write:bpfwrite
                                        ioctl:bpfioctl
                                         stop:nulldev
                                        reset:nulldev
                                       select:bpfselect
                                         mmap:enodev
                                     strategy:enodev
                                      getstat:enodev];

    if (result == YES) {
        instance = [[self alloc] initFromDeviceDescription:deviceDescription];
        if (instance != nil) {
            return YES;
        }
        [self removeFromCdevsw];
    }

    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    bpfops = (void *)0xce0;
    [self setName:"bpf"];
    [super initFromDeviceDescription:deviceDescription];
    [self registerDevice];

    return self;
}

- (IOReturn)getIntValues:(int *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned int *)count
{
    int i;
    BOOL match;
    char *p1, *p2;
    unsigned int majorNum;

    /* Compare parameter name with "BpfMajorMinor" (14 chars) */
    i = 14;
    match = YES;
    p1 = parameterName;
    p2 = "BpfMajorMinor";
    do {
        if (i == 0) break;
        i--;
        match = (*p1 == *p2);
        p1++;
        p2++;
    } while (match);

    if (match && (*count == 2)) {
        /* Get character major number from class method */
        majorNum = [[self class] characterMajor];

        /* Return major device number and number of BPF devices */
        parameterArray[0] = majorNum;
        parameterArray[1] = nbpfilter;
        *count = 2;

        return 0;  /* IO_R_SUCCESS */
    }

    /* Call superclass implementation */
    return [super getIntValues:parameterArray
                  forParameter:parameterName
                         count:count];
}

@end
