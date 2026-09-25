/*
 * bpfif.c - BSD/BPF raw-Ethernet backend for dhcpcd-1
 *
 * See bpfif.h. The MAC-address lookup below follows the same
 * AF_LINK/struct sockaddr_dl walk over SIOCGIFCONF that
 * src/bootp-1/bootplib/interfaces.c already uses on this tree.
 */

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#include <net/bpf.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <syslog.h>

#include "client.h"
#include "bpfif.h"

#define BPFIF_DEVMAX 16

static unsigned char	*bpf_buf;	/* raw read buffer, BIOCGBLEN-sized */
static int		bpf_buflen;
static unsigned char	*bpf_next;	/* next unconsumed record, or NULL */
static int		bpf_avail;	/* bytes remaining from bpf_next */

static int
bpfGetHwAddr(ifname, hwaddr)
const char *ifname;
unsigned char hwaddr[6];
{
  int s;
  struct ifconf ifc;
  struct ifreq *ifr;
  char buf[8192];
  char *cp, *cplim;
  int found = 0;

  s = socket(AF_INET,SOCK_DGRAM,0);
  if ( s == -1 ) return -1;

  ifc.ifc_len = sizeof(buf);
  ifc.ifc_buf = buf;
  if ( ioctl(s,SIOCGIFCONF,&ifc) == -1 )
    {
      close(s);
      return -1;
    }

  cp = buf;
  cplim = buf + ifc.ifc_len;
  while ( cp < cplim )
    {
      ifr = (struct ifreq *)cp;
      cp += sizeof(ifr->ifr_name) +
	    (ifr->ifr_addr.sa_len > sizeof(struct sockaddr)
	     ? ifr->ifr_addr.sa_len : sizeof(struct sockaddr));
      if ( strncmp(ifr->ifr_name,ifname,sizeof(ifr->ifr_name)) != 0 )
	continue;
      if ( ifr->ifr_addr.sa_family != AF_LINK )
	continue;
      {
	struct sockaddr_dl *sdl = (struct sockaddr_dl *)&ifr->ifr_addr;
	if ( sdl->sdl_type == IFT_ETHER && sdl->sdl_alen == 6 )
	  {
	    memcpy(hwaddr,LLADDR(sdl),6);
	    found = 1;
	    break;
	  }
      }
    }

  close(s);
  return found ? 0 : -1;
}

int
bpfOpenForInterface(ifname,hwaddr)
const char *ifname;
unsigned char hwaddr[6];
{
  char dev[16];
  int fd,i,s;
  struct ifreq ifr;
  unsigned int enable = 1;

  if ( bpfGetHwAddr(ifname,hwaddr) == -1 )
    {
      syslog(LOG_ERR,
	"bpfOpenForInterface: could not read %s's hardware address\n",ifname);
      return -1;
    }

  /* BIOCSETIF refuses an interface that is down, so bring it up first */
  s = socket(AF_INET,SOCK_DGRAM,0);
  if ( s == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: socket: %m\n");
      return -1;
    }
  memset(&ifr,0,sizeof(ifr));
  strncpy(ifr.ifr_name,ifname,sizeof(ifr.ifr_name)-1);
  if ( ioctl(s,SIOCGIFFLAGS,&ifr) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: SIOCGIFFLAGS %s: %m\n",ifname);
      close(s);
      return -1;
    }
  ifr.ifr_flags |= IFF_UP;
  if ( ioctl(s,SIOCSIFFLAGS,&ifr) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: SIOCSIFFLAGS %s: %m\n",ifname);
      close(s);
      return -1;
    }
  close(s);

  fd = -1;
  for ( i = 0 ; i < BPFIF_DEVMAX ; i++ )
    {
      sprintf(dev,"/dev/bpf%d",i);
      fd = open(dev,O_RDWR);
      if ( fd != -1 ) break;
      if ( errno != EBUSY ) break;
    }
  if ( fd == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: no /dev/bpf* available: %m\n");
      return -1;
    }

  memset(&ifr,0,sizeof(ifr));
  strncpy(ifr.ifr_name,ifname,sizeof(ifr.ifr_name)-1);
  if ( ioctl(fd,BIOCSETIF,&ifr) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: BIOCSETIF %s: %m\n",ifname);
      close(fd);
      return -1;
    }

  if ( ioctl(fd,BIOCIMMEDIATE,&enable) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: BIOCIMMEDIATE: %m\n");
      close(fd);
      return -1;
    }

  if ( ioctl(fd,BIOCGBLEN,&bpf_buflen) == -1 )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: BIOCGBLEN: %m\n");
      close(fd);
      return -1;
    }
  free(bpf_buf);		/* from a previous open, after dhcpStop() */
  bpf_next = NULL;
  bpf_avail = 0;
  bpf_buf = malloc(bpf_buflen);
  if ( bpf_buf == NULL )
    {
      syslog(LOG_ERR,"bpfOpenForInterface: malloc: %m\n");
      close(fd);
      return -1;
    }

  return fd;
}

int
bpfSendFrame(bpf_fd,frame,framelen)
int bpf_fd;
const void *frame;
int framelen;
{
  int n = write(bpf_fd,frame,framelen);
  if ( n == -1 )
    syslog(LOG_ERR,"bpfSendFrame: write: %m\n");
  return n;
}

int
bpfRecvFrame(bpf_fd,frame,frame_max)
int bpf_fd;
void *frame;
int frame_max;
{
  struct bpf_hdr *bh;
  int n, reclen;

  if ( bpf_avail <= 0 )
    {
      n = read(bpf_fd,bpf_buf,bpf_buflen);
      if ( n == -1 )
	{
	  syslog(LOG_ERR,"bpfRecvFrame: read: %m\n");
	  return -1;
	}
      bpf_next = bpf_buf;
      bpf_avail = n;
    }

  if ( bpf_avail <= 0 ) return 0;

  bh = (struct bpf_hdr *)bpf_next;
  n = bh->bh_caplen;
  if ( n > frame_max ) n = frame_max;
  memcpy(frame,bpf_next + bh->bh_hdrlen,n);

  reclen = BPF_WORDALIGN(bh->bh_hdrlen + bh->bh_caplen);
  bpf_next += reclen;
  bpf_avail -= reclen;
  if ( bpf_avail < 0 ) bpf_avail = 0;

  return n;
}

int
bpfPeek(bpf_fd,tv_usec)
int bpf_fd;
int tv_usec;
{
  if ( bpf_avail > 0 ) return 0;	/* a frame is already buffered here */
  return peekfd(bpf_fd,tv_usec);
}
