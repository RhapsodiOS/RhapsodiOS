/*
 * bootcompat.c - see bootcompat.h
 */

#include <sys/types.h>
#include <stdio.h>
#include <ctype.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "client.h"
#include "bootcompat.h"

extern dhcpInterface	DhcpIface;
extern dhcpOptions	DhcpOptions;

/* SetNetConfig evals these lines as root, so pass only a plain host name */
static int
validHostName(name)
const char *name;
{
  const char *p;

  if ( *name == '\0' || *name == '-' ) return 0;
  for ( p = name ; *p ; p++ )
    if ( !isalnum((unsigned char)*p) && *p != '-' && *p != '.' ) return 0;
  return 1;
}

void
bootcompatPrint()
{
  struct in_addr addr;

  addr.s_addr = DhcpIface.client_iaddr;
  printf("ip_address=%s\n",inet_ntoa(addr));

  if ( DhcpOptions.val[subnetMask] )
    {
      addr.s_addr = *(unsigned int *)DhcpOptions.val[subnetMask];
      printf("subnet_mask=%s\n",inet_ntoa(addr));
    }

  if ( DhcpOptions.val[routersOnSubnet] )
    {
      addr.s_addr = *(unsigned int *)DhcpOptions.val[routersOnSubnet];
      printf("router=%s\n",inet_ntoa(addr));
    }

  if ( DhcpOptions.val[hostName]
       && validHostName((char *)DhcpOptions.val[hostName]) )
    printf("host_name=%s\n",(char *)DhcpOptions.val[hostName]);

  addr.s_addr = DhcpIface.server_iaddr;
  printf("server_ip_address=%s\n",inet_ntoa(addr));

  fflush(stdout);
}
