/*
 * rtsock.c - BSD routing-socket default route for dhcpcd-1
 *
 * See rtsock.h. Messages are laid out the way route(8) builds them in
 * src/Commands/network_cmds/route.tproj/route.c.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <syslog.h>

#include "rtsock.h"

#define ROUNDUP(a) \
	((a) > 0 ? (1 + (((a) - 1) | (sizeof(long) - 1))) : sizeof(long))

static int
rtsockSend(s,type,flags,dst,gateway,withmask)
int s,type,flags;
unsigned int dst,gateway;
int withmask;
{
  static int seq;
  struct
    {
      struct rt_msghdr	rtm;
      char		space[512];
    } msg;
  struct sockaddr_in sin;
  char *cp;

  memset(&msg,0,sizeof(msg));
  msg.rtm.rtm_type = type;
  msg.rtm.rtm_flags = flags;
  msg.rtm.rtm_version = RTM_VERSION;
  msg.rtm.rtm_seq = ++seq;
  msg.rtm.rtm_addrs = RTA_DST|RTA_GATEWAY;
  if ( withmask ) msg.rtm.rtm_addrs |= RTA_NETMASK;

  memset(&sin,0,sizeof(sin));
  sin.sin_len = sizeof(sin);
  sin.sin_family = AF_INET;

  cp = msg.space;
  sin.sin_addr.s_addr = dst;
  memcpy(cp,&sin,sizeof(sin));
  cp += ROUNDUP(sizeof(sin));
  sin.sin_addr.s_addr = gateway;
  memcpy(cp,&sin,sizeof(sin));
  cp += ROUNDUP(sizeof(sin));
  if ( withmask )
    cp += ROUNDUP(0);	/* zero-length netmask: the default route */

  msg.rtm.rtm_msglen = cp - (char *)&msg;
  if ( write(s,(char *)&msg,msg.rtm.rtm_msglen) == -1 ) return -1;
  return 0;
}

int
rtsockAddDefault(gateway,ifaddr)
unsigned int gateway,ifaddr;
{
  int s,rc;

  s = socket(PF_ROUTE,SOCK_RAW,0);
  if ( s == -1 )
    {
      syslog(LOG_ERR,"rtsockAddDefault: socket: %m\n");
      return -1;
    }

  rc = rtsockSend(s,RTM_ADD,RTF_UP|RTF_GATEWAY|RTF_STATIC,0,gateway,1);
  if ( rc == -1 && errno == ENETUNREACH )
    {
      /* gateway is off our subnet: reach it through our own address first */
      if ( rtsockSend(s,RTM_ADD,RTF_UP|RTF_HOST|RTF_STATIC,gateway,ifaddr,0) == 0
	   || errno == EEXIST )
	rc = rtsockSend(s,RTM_ADD,RTF_UP|RTF_GATEWAY|RTF_STATIC,0,gateway,1);
    }
  if ( rc == -1 && errno == EEXIST )
    rc = rtsockSend(s,RTM_CHANGE,RTF_UP|RTF_GATEWAY|RTF_STATIC,0,gateway,1);
  if ( rc == -1 )
    syslog(LOG_ERR,"rtsockAddDefault: default route: %m\n");

  close(s);
  return rc;
}
