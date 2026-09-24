/*
 * dhcpcd - DHCP client daemon -
 * Copyright (C) 1996 - 1997 Yoichi Hariguchi <yoichi@fore.com>
 * Copyright (C) January, 1998 Sergei Viznyuk <sv@phystech.com>
 * 
 * dhcpcd is an RFC2131 and RFC1541 compliant DHCP client daemon.
 *
 * This is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <string.h>
#include <netinet/in.h>
#include <net/if_arp.h>
#include "client.h"
#include "udpipgen.h"

extern	dhcpMessage	*DhcpMsgSend;
extern	dhcpOptions	DhcpOptions;
extern	dhcpInterface	DhcpIface;
extern	char		*HostName;
extern	int		HostName_len;
extern	int		DebugFlag;
extern	int		BeRFC1541;
extern	int		LeaseTime;
extern	unsigned char	ClientHwAddr[6];
extern  udpipMessage	UdpIpMsg;

/*****************************************************************************/
void buildDhcpDiscover(xid)
unsigned xid;
{
  register unsigned char *p = DhcpMsgSend->options + 4;

/* build Ethernet header */
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);

  DhcpMsgSend->op	=	DHCP_BOOTREQUEST;
  DhcpMsgSend->htype	=	ARPHRD_ETHER;
  DhcpMsgSend->hlen	=	ETHER_ADDR_LEN;
/*  DhcpMsgSend->hops	=	0; */
  DhcpMsgSend->xid	=	xid;
  DhcpMsgSend->secs	=       htons(5);
#ifdef NEED_BCAST_RESPONSE
  DhcpMsgSend->flags	=	htons(BROADCAST_FLAG);
#endif
  memcpy(DhcpMsgSend->chaddr,ClientHwAddr,ETHER_ADDR_LEN);
  *((unsigned long *)DhcpMsgSend->options) = htonl(MAGIC_COOKIE);
  *p++ = dhcpMessageType;
  *p++ = 1;
  *p++ = DHCP_DISCOVER;
  *p++ = padOption;
  *p++ = dhcpMaxMsgSize;
  *p++ = 2;
  *((unsigned short *)p) = htons(sizeof(dhcpMessage));
  p += sizeof(unsigned short);
  if ( DhcpIface.client_iaddr )
    {
      if ( BeRFC1541 )
        DhcpMsgSend->ciaddr = DhcpIface.client_iaddr;
      else
        {
          *p++ = dhcpRequestedIPaddr;
          *p++ = 4;
          *((unsigned int *)p) = DhcpIface.client_iaddr;
          p += sizeof(unsigned int); 
        }
    }
  *p++ = dhcpIPaddrLeaseTime;
  *p++ = 4;
  *((unsigned long *)p) = htonl(LeaseTime);
  p += sizeof(unsigned long);
  *p++ = dhcpParamRequest;
  *p++ = 8;
  *p++ = subnetMask;
  *p++ = routersOnSubnet;
  *p++ = dns;
  *p++ = hostName;
  *p++ = domainName;
  *p++ = broadcastAddr;
  *p++ = ntpServers;
  *p++ = nisDomainName;
  if ( HostName )
    {
      *p++ = hostName;
      *p++ = HostName_len;
      memcpy(p,HostName,HostName_len);
      p += HostName_len;
    }
  *p++ = dhcpClassIdentifier;
  *p++ = DhcpIface.class_len;
  memcpy(p,DhcpIface.class_id,DhcpIface.class_len);
  p += DhcpIface.class_len;
  memcpy(p,DhcpIface.client_id,DhcpIface.client_len);
  p += DhcpIface.client_len;
  *p = endOption;

/* build UDP/IP header */
  udpipgen((udpiphdr *)UdpIpMsg.udpipmsg,0,INADDR_BROADCAST,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
}
/*****************************************************************************/
void buildDhcpRequest(xid)
unsigned xid;
{
  register unsigned char *p = DhcpMsgSend->options + 4;
 
/* build Ethernet header */
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);

  DhcpMsgSend->op	=	DHCP_BOOTREQUEST;
  DhcpMsgSend->htype	=	ARPHRD_ETHER;
  DhcpMsgSend->hlen	=	ETHER_ADDR_LEN;
/*  DhcpMsgSend->hops	=	0; */
  DhcpMsgSend->xid	=	xid;
  DhcpMsgSend->secs	=	htons(5);
#ifdef NEED_BCAST_RESPONSE
  DhcpMsgSend->flags	=	htons(BROADCAST_FLAG);
#endif
  memcpy(DhcpMsgSend->chaddr,ClientHwAddr,ETHER_ADDR_LEN);
  *((unsigned long *)DhcpMsgSend->options) = htonl(MAGIC_COOKIE);
  *p++ = dhcpMessageType;
  *p++ = 1;
  *p++ = DHCP_REQUEST;
  *p++ = padOption;
  *p++ = dhcpMaxMsgSize;
  *p++ = 2;
  *((unsigned short *)p) = htons(sizeof(dhcpMessage));
  p += sizeof(unsigned short);
  *p++ = dhcpServerIdentifier;
  *p++ = 4;
  *((unsigned int *)p) = *((unsigned int *)DhcpOptions.val[dhcpServerIdentifier]);
  p += sizeof(unsigned int);
  if ( BeRFC1541 )
    DhcpMsgSend->ciaddr = DhcpIface.client_iaddr;
  else
    {
      *p++ = dhcpRequestedIPaddr;
      *p++ = 4;
      *((unsigned int *)p) = DhcpIface.client_iaddr;
      p += sizeof(unsigned int); 
    }
  if ( DhcpOptions.val[dhcpIPaddrLeaseTime] )
    {
      *p++ = dhcpIPaddrLeaseTime;
      *p++ = 4;
      *((unsigned long *)p) = *((unsigned long *)DhcpOptions.val[dhcpIPaddrLeaseTime]);
      p += sizeof(unsigned long);
    }
  *p++ = dhcpParamRequest;
  *p++ = 8;
  *p++ = subnetMask;
  *p++ = routersOnSubnet;
  *p++ = dns;
  *p++ = hostName;
  *p++ = domainName;
  *p++ = broadcastAddr;
  *p++ = ntpServers;
  *p++ = nisDomainName;
  if ( HostName )
    {
      *p++ = hostName;
      *p++ = HostName_len;
      memcpy(p,HostName,HostName_len);
      p += HostName_len;
    }
  *p++ = dhcpClassIdentifier;
  *p++ = DhcpIface.class_len;
  memcpy(p,DhcpIface.class_id,DhcpIface.class_len);
  p += DhcpIface.class_len;
  memcpy(p,DhcpIface.client_id,DhcpIface.client_len);
  p += DhcpIface.client_len;
  *p = endOption;

/* build UDP/IP header */
  udpipgen((udpiphdr *)UdpIpMsg.udpipmsg,0,INADDR_BROADCAST,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
}
/*****************************************************************************/
void buildDhcpRenew(xid)
unsigned xid;
{
  register unsigned char *p = DhcpMsgSend->options + 4;
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,DhcpIface.server_haddr,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);

  DhcpMsgSend->op	=	DHCP_BOOTREQUEST;
  DhcpMsgSend->htype	=	ARPHRD_ETHER;
  DhcpMsgSend->hlen	=	ETHER_ADDR_LEN;
/*  DhcpMsgSend->hops	=	0; */
  DhcpMsgSend->xid	=	xid;
  DhcpMsgSend->secs	=	htons(5);
#ifdef NEED_BCAST_RESPONSE
  DhcpMsgSend->flags	=	htons(BROADCAST_FLAG);
#endif
  memcpy(DhcpMsgSend->chaddr,ClientHwAddr,ETHER_ADDR_LEN);
  DhcpMsgSend->ciaddr = DhcpIface.client_iaddr;
  *((unsigned long *)DhcpMsgSend->options) = htonl(MAGIC_COOKIE);
  *p++ = dhcpMessageType;
  *p++ = 1;
  *p++ = DHCP_REQUEST;
  *p++ = padOption;
  *p++ = dhcpMaxMsgSize;
  *p++ = 2;
  *((unsigned short *)p) = htons(sizeof(dhcpMessage));
  p += sizeof(unsigned short);
  if ( DhcpOptions.val[dhcpIPaddrLeaseTime] )
    {
      *p++ = dhcpIPaddrLeaseTime;
      *p++ = 4;
      *((unsigned long *)p) = *((unsigned long *)DhcpOptions.val[dhcpIPaddrLeaseTime]);
      p += sizeof(unsigned long);
    }
  *p++ = dhcpParamRequest;
  *p++ = 8;
  *p++ = subnetMask;
  *p++ = routersOnSubnet;
  *p++ = dns;
  *p++ = hostName;
  *p++ = domainName;
  *p++ = broadcastAddr;
  *p++ = ntpServers;
  *p++ = nisDomainName;
  if ( HostName )
    {
      *p++ = hostName;
      *p++ = HostName_len;
      memcpy(p,HostName,HostName_len);
      p += HostName_len;
    }
  *p++ = dhcpClassIdentifier;
  *p++ = DhcpIface.class_len;
  memcpy(p,DhcpIface.class_id,DhcpIface.class_len);
  p += DhcpIface.class_len;
  memcpy(p,DhcpIface.client_id,DhcpIface.client_len);
  p += DhcpIface.client_len;
  *p = endOption;

/* build UDP/IP header */
  udpipgen((udpiphdr *)UdpIpMsg.udpipmsg,
  DhcpIface.client_iaddr,DhcpIface.server_iaddr,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
}
/*****************************************************************************/
void buildDhcpRebind(xid)
unsigned xid;
{
  buildDhcpRenew();
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
#if 0
  register unsigned char *p = DhcpMsgSend->options + 4;
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);

  DhcpMsgSend->op	=	DHCP_BOOTREQUEST;
  DhcpMsgSend->htype	=	ARPHRD_ETHER;
  DhcpMsgSend->hlen	=	ETHER_ADDR_LEN;
/*  DhcpMsgSend->hops	=	0; */
  DhcpMsgSend->xid	=	xid;
  DhcpMsgSend->secs	=	htons(5);
#ifdef NEED_BCAST_RESPONSE
  DhcpMsgSend->flags	=	htons(BROADCAST_FLAG);
#endif
  memcpy(DhcpMsgSend->chaddr,ClientHwAddr,ETHER_ADDR_LEN);
  DhcpMsgSend->ciaddr = DhcpIface.client_iaddr;
  *((unsigned long *)DhcpMsgSend->options) = htonl(MAGIC_COOKIE);
  *p++ = dhcpMessageType;
  *p++ = 1;
  *p++ = DHCP_REQUEST;
  *p++ = padOption;
  *p++ = dhcpMaxMsgSize;
  *p++ = 2;
  *((unsigned short *)p) = htons(sizeof(dhcpMessage));
  p += sizeof(unsigned short);
  if ( DhcpOptions.val[dhcpIPaddrLeaseTime] )
    {
      *p++ = dhcpIPaddrLeaseTime;
      *p++ = 4;
      *((unsigned long *)p) = *((unsigned long *)DhcpOptions.val[dhcpIPaddrLeaseTime]);
      p += sizeof(unsigned long);
    }
  *p++ = dhcpParamRequest;
  *p++ = 8;
  *p++ = subnetMask;
  *p++ = routersOnSubnet;
  *p++ = dns;
  *p++ = hostName;
  *p++ = domainName;
  *p++ = broadcastAddr;
  *p++ = ntpServers;
  *p++ = nisDomainName;
  if ( HostName )
    {
      *p++ = hostName;
      *p++ = HostName_len;
      memcpy(p,HostName,HostName_len);
      p += HostName_len;
    }
  *p++ = dhcpClassIdentifier;
  *p++ = DhcpIface.class_len;
  memcpy(p,DhcpIface.class_id,DhcpIface.class_len);
  p += DhcpIface.class_len;
  memcpy(p,DhcpIface.client_id,DhcpIface.client_len);
  p += DhcpIface.client_len;
  *p = endOption;

/* build UDP/IP header */
  udpipgen((udpiphdr *)UdpIpMsg.udpipmsg,
  DhcpIface.client_iaddr,INADDR_BROADCAST,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
#endif
}
/*****************************************************************************/
void buildDhcpReboot(xid)
unsigned xid;
{
  register unsigned char *p = DhcpMsgSend->options + 4;
 
/* build Ethernet header */
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);

  DhcpMsgSend->op	=	DHCP_BOOTREQUEST;
  DhcpMsgSend->htype	=	ARPHRD_ETHER;
  DhcpMsgSend->hlen	=	ETHER_ADDR_LEN;
/*  DhcpMsgSend->hops	=	0; */
  DhcpMsgSend->xid	=	xid;
  DhcpMsgSend->secs	=	htons(5);
#ifdef NEED_BCAST_RESPONSE
  DhcpMsgSend->flags	=	htons(BROADCAST_FLAG);
#endif
  memcpy(DhcpMsgSend->chaddr,ClientHwAddr,ETHER_ADDR_LEN);
  *((unsigned long *)DhcpMsgSend->options) = htonl(MAGIC_COOKIE);
  *p++ = dhcpMessageType;
  *p++ = 1;
  *p++ = DHCP_REQUEST;
  *p++ = padOption;
  *p++ = dhcpMaxMsgSize;
  *p++ = 2;
  *((unsigned short *)p) = htons(sizeof(dhcpMessage));
  p += sizeof(unsigned short);
  if ( BeRFC1541 )
    DhcpMsgSend->ciaddr = DhcpIface.client_iaddr;
  else
    {
      *p++ = dhcpRequestedIPaddr;
      *p++ = 4;
      *((unsigned int *)p) = DhcpIface.client_iaddr;
      p += sizeof(unsigned int); 
    }
  *p++ = dhcpIPaddrLeaseTime;
  *p++ = 4;
  *((unsigned long *)p) = htonl(LeaseTime);
  p += sizeof(unsigned long);
  *p++ = dhcpParamRequest;
  *p++ = 8;
  *p++ = subnetMask;
  *p++ = routersOnSubnet;
  *p++ = dns;
  *p++ = hostName;
  *p++ = domainName;
  *p++ = broadcastAddr;
  *p++ = ntpServers;
  *p++ = nisDomainName;
  if ( HostName )
    {
      *p++ = hostName;
      *p++ = HostName_len;
      memcpy(p,HostName,HostName_len);
      p += HostName_len;
    }
  *p++ = dhcpClassIdentifier;
  *p++ = DhcpIface.class_len;
  memcpy(p,DhcpIface.class_id,DhcpIface.class_len);
  p += DhcpIface.class_len;
  memcpy(p,DhcpIface.client_id,DhcpIface.client_len);
  p += DhcpIface.client_len;
  *p = endOption;

/* build UDP/IP header */
  udpipgen((udpiphdr *)UdpIpMsg.udpipmsg,0,INADDR_BROADCAST,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
}
/*****************************************************************************/
void buildDhcpRelease(xid)
unsigned xid;
{
  register u_char *p = DhcpMsgSend->options + 4;
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,DhcpIface.server_haddr,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);

  DhcpMsgSend->op	=	DHCP_BOOTREQUEST;
  DhcpMsgSend->htype	=	ARPHRD_ETHER;
  DhcpMsgSend->hlen	=	ETHER_ADDR_LEN;
  DhcpMsgSend->xid	=	xid;
  DhcpMsgSend->ciaddr	=	DhcpIface.client_iaddr;
  memcpy(DhcpMsgSend->chaddr,ClientHwAddr,ETHER_ADDR_LEN);
  *((unsigned long *)DhcpMsgSend->options) = htonl(MAGIC_COOKIE);
  *p++ = dhcpMessageType;
  *p++ = 1;
  *p++ = DHCP_RELEASE;
  *p++ = padOption;
  *p++ = dhcpServerIdentifier;
  *p++ = 4;
  *((unsigned int *)p) = *((unsigned int *)DhcpOptions.val[dhcpServerIdentifier]);
  p += sizeof(unsigned int);
  memcpy(p,DhcpIface.client_id,DhcpIface.client_len);
  p += DhcpIface.client_len;
  *p = endOption;

/* build UDP/IP header */
  udpipgen((udpiphdr *)UdpIpMsg.udpipmsg,DhcpIface.client_iaddr,
  DhcpIface.server_iaddr,htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),
  sizeof(dhcpMessage));
}
/*****************************************************************************/
#ifdef ARPCHECK
void buildDhcpDecline(xid)
unsigned xid;
{
  register unsigned char *p = DhcpMsgSend->options + 4;
  DhcpMsgSend->op	=	DHCP_BOOTREQUEST;
  DhcpMsgSend->htype	=	ARPHRD_ETHER;
  DhcpMsgSend->hlen	=	ETHER_ADDR_LEN;
  DhcpMsgSend->xid	=	xid;
  memcpy(DhcpMsgSend->chaddr,ClientHwAddr,ETHER_ADDR_LEN);
  *((unsigned long *)DhcpMsgSend->options) = htonl(MAGIC_COOKIE);
  *p++ = dhcpMessageType;
  *p++ = 1;
  *p++ = DHCP_DECLINE;
  *p++ = padOption;
  *p++ = dhcpServerIdentifier;
  *p++ = 4;
  *((unsigned int *)p) = *((unsigned int *)DhcpOptions.val[dhcpServerIdentifier]);
  p += sizeof(unsigned int);
  if ( BeRFC1541 )
    DhcpMsgSend->ciaddr = DhcpIface.client_iaddr;
  else
    {
      *p++ = dhcpRequestedIPaddr;
      *p++ = 4;
      *((unsigned int *)p) = DhcpIface.client_iaddr;
      p += sizeof(unsigned int); 
    }
  memcpy(p,DhcpIface.client_id,DhcpIface.client_len);
  p += DhcpIface.client_len;
  *p = endOption;
}
#endif
