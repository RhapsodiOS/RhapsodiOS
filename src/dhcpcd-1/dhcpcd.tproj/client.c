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

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <syslog.h>
#include <errno.h>
#include <setjmp.h>
#include "client.h"
#include "buildmsg.h"
#include "udpipgen.h"
#include "pathnames.h"
#include "rtsock.h"
#include "bpfif.h"

extern	char		*ProgramName,**ProgramEnviron,*Cfilename;
extern	char		*IfName;
extern	int		IfName_len;
extern	char		*HostName;
extern	unsigned char	*ClassID;
extern	int		ClassID_len;
extern	unsigned char	*ClientID;
extern	int		ClientID_len;
extern	int		DebugFlag;
extern	int		BeRFC1541;
extern	int		LeaseTime;
extern	int		ReplResolvConf;
extern	int		SetDomainName;
extern	int		SetHostName;
extern	int		WaitFlag;
extern	int		SetDefaultRoute;
extern	unsigned short	ip_id;

#ifdef ARPCHECK
int arpCheck();
#endif
int arpRelease();
int arpInform();

int		dhcpSocket;
int             prev_ip_addr;
time_t		ReqSentTime;
dhcpInterface	DhcpIface;
dhcpOptions	DhcpOptions;
udpipMessage	UdpIpMsg;
dhcpMessage	*DhcpMsgRecv;
jmp_buf		env;
unsigned char	ClientHwAddr[ETHER_ADDR_LEN];

const dhcpMessage *DhcpMsgSend = (dhcpMessage *)&UdpIpMsg.udpipmsg[sizeof(udpiphdr)];
/*****************************************************************************/
int parseDhcpMsgRecv()
{
#ifdef DEBUG
  int i,j;
#endif
  register u_char *p = DhcpMsgRecv->options+4;
  unsigned char *end = DhcpMsgRecv->options+sizeof(DhcpMsgRecv->options);
  while ( p < end )
    switch ( *p )
      {
        case endOption: goto swend;
       	case padOption: p++; break;
       	default:
	  if ( p[1] )
	    {
	      if ( DhcpOptions.len[*p] == p[1] )
	        memcpy(DhcpOptions.val[*p],p+2,p[1]);
	      else
	        {
		  DhcpOptions.len[*p] = p[1];
	          if ( DhcpOptions.val[*p] )
	            free(DhcpOptions.val[*p]);
	      	  else
		    DhcpOptions.num++;
	      	  DhcpOptions.val[*p] = malloc(p[1]+1);
		  memset(DhcpOptions.val[*p],0,p[1]+1);
	  	  memcpy(DhcpOptions.val[*p],p+2,p[1]);
	        }
	    }
	  p+=p[1]+2;
      }
swend:
#ifdef DEBUG
  fprintf(stderr,"parseDhcpMsgRecv: %d options received:\n",DhcpOptions.num);
  for (i=1;i<255;i++)
    if ( DhcpOptions.val[i] )
      switch ( i )
        {
	  case 1:
	  case 3:
	  case 4:
	  case 5:
	  case 6:
	  case 28:
	  case 50:
	  case 54:
	    for (j=0;j<DhcpOptions.len[i];j+=4)
	      fprintf(stderr,"i=%-2d  len=%-2d  option = %u.%u.%u.%u\n",
		i,DhcpOptions.len[i],
		((unsigned char *)DhcpOptions.val[i])[0+j],
		((unsigned char *)DhcpOptions.val[i])[1+j],
		((unsigned char *)DhcpOptions.val[i])[2+j],
		((unsigned char *)DhcpOptions.val[i])[3+j]);
	    break;
	  case 2:
	  case 51:
	  case 57:
	  case 58:
	  case 59:
	    fprintf(stderr,"i=%-2d  len=%-2d  option = %u\n",
		i,DhcpOptions.len[i],
		    ntohl(*(unsigned int *)DhcpOptions.val[i]));
	    break;
	  case 53:
	    fprintf(stderr,"i=%-2d  len=%-2d  option = %u\n",
		i,DhcpOptions.len[i],*(unsigned char *)DhcpOptions.val[i]);
	    break;
	  default:
	    fprintf(stderr,"i=%-2d  len=%-2d  option = \"%s\"\n",
		i,DhcpOptions.len[i],(char *)DhcpOptions.val[i]);
	}
fprintf(stderr,"\
DhcpMsgRecv->yiaddr  = %u.%u.%u.%u\n\
DhcpMsgRecv->siaddr  = %u.%u.%u.%u\n\
DhcpMsgRecv->giaddr  = %u.%u.%u.%u\n\
DhcpMsgRecv->sname   = \"%s\"\n\
ServerHardwareAddr   = %02X.%02X.%02X.%02X.%02X.%02X\n",
((unsigned char *)&DhcpMsgRecv->yiaddr)[0],
((unsigned char *)&DhcpMsgRecv->yiaddr)[1],
((unsigned char *)&DhcpMsgRecv->yiaddr)[2],
((unsigned char *)&DhcpMsgRecv->yiaddr)[3],
((unsigned char *)&DhcpMsgRecv->siaddr)[0],
((unsigned char *)&DhcpMsgRecv->siaddr)[1],
((unsigned char *)&DhcpMsgRecv->siaddr)[2],
((unsigned char *)&DhcpMsgRecv->siaddr)[3],
((unsigned char *)&DhcpMsgRecv->giaddr)[0],
((unsigned char *)&DhcpMsgRecv->giaddr)[1],
((unsigned char *)&DhcpMsgRecv->giaddr)[2],
((unsigned char *)&DhcpMsgRecv->giaddr)[3],
DhcpMsgRecv->sname,
UdpIpMsg.ethhdr.ether_shost[0],
UdpIpMsg.ethhdr.ether_shost[1],
UdpIpMsg.ethhdr.ether_shost[2],
UdpIpMsg.ethhdr.ether_shost[3],
UdpIpMsg.ethhdr.ether_shost[4],
UdpIpMsg.ethhdr.ether_shost[5]);
#endif
  if ( ! DhcpOptions.val[dhcpServerIdentifier] ) /* did not get dhcpServerIdentifier */
    {	/* make it the same as IP address of the sender */
      struct ip *ip=(struct ip *)((struct udpiphdr *)UdpIpMsg.udpipmsg)->ip;
      DhcpOptions.val[dhcpServerIdentifier] = malloc(sizeof(struct in_addr));
      *(unsigned int *)DhcpOptions.val[dhcpServerIdentifier] = ip->ip_src.s_addr;
      DhcpOptions.len[dhcpServerIdentifier] = sizeof(struct in_addr);
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"dhcpServerIdentifier option is missing in DHCP server response. Assuming %u.%u.%u.%u\n",
	((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[0],
	((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[1],
	((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[2],
	((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[3]);
    }
  if ( ! DhcpOptions.val[dns] ) /* did not get DNS */
    {	/* make it the same as dhcpServerIdentifier */
      DhcpOptions.val[dns] = malloc(sizeof(struct in_addr));
      *(unsigned int *)DhcpOptions.val[dns] = *(unsigned int *)DhcpOptions.val[dhcpServerIdentifier];
      DhcpOptions.len[dns] = sizeof(struct in_addr);
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"dns option is missing in DHCP server response. Assuming %u.%u.%u.%u\n",
	((unsigned char *)DhcpOptions.val[dns])[0],
	((unsigned char *)DhcpOptions.val[dns])[1],
	((unsigned char *)DhcpOptions.val[dns])[2],
	((unsigned char *)DhcpOptions.val[dns])[3]);
    }
  if ( ! DhcpOptions.val[subnetMask] ) /* did not get subnetMask */
    {	/* make it 255.255.255.0  */
      DhcpOptions.val[subnetMask] = malloc(sizeof(struct in_addr));
      ((unsigned char *)DhcpOptions.val[subnetMask])[0] = 255;
      ((unsigned char *)DhcpOptions.val[subnetMask])[1] = 255;
      ((unsigned char *)DhcpOptions.val[subnetMask])[2] = 255;
      ((unsigned char *)DhcpOptions.val[subnetMask])[3] = 0;
      DhcpOptions.len[subnetMask] = sizeof(struct in_addr);
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"subnetMask option is missing in DHCP server response. Assuming 255.255.255.0\n");
    }
  if ( ! DhcpOptions.val[broadcastAddr] ) /* did not get broadcastAddr */
    {
      DhcpOptions.val[broadcastAddr] = malloc(sizeof(struct in_addr));
      *(unsigned int *)DhcpOptions.val[broadcastAddr] = DhcpMsgRecv->yiaddr | ~*((int *)DhcpOptions.val[subnetMask]);
      DhcpOptions.len[broadcastAddr] = sizeof(struct in_addr);
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"broadcastAddr option is missing in DHCP server response. Assuming %u.%u.%u.%u\n",
	((unsigned char *)DhcpOptions.val[broadcastAddr])[0],
	((unsigned char *)DhcpOptions.val[broadcastAddr])[1],
	((unsigned char *)DhcpOptions.val[broadcastAddr])[2],
	((unsigned char *)DhcpOptions.val[broadcastAddr])[3]);
    }
  if ( DhcpOptions.val[routersOnSubnet] )
    {
      if ( ! DhcpMsgRecv->giaddr )
        DhcpMsgRecv->giaddr = *(unsigned int *)DhcpOptions.val[routersOnSubnet];
    }
  else
    {
      DhcpOptions.val[routersOnSubnet] = malloc(sizeof(struct in_addr));
      if ( DhcpMsgRecv->giaddr )
      	*(unsigned int *)DhcpOptions.val[routersOnSubnet] = DhcpMsgRecv->giaddr;
      else
	*(unsigned int *)DhcpOptions.val[routersOnSubnet] = *(unsigned int *)DhcpOptions.val[dhcpServerIdentifier];
      DhcpOptions.len[routersOnSubnet] = sizeof(struct in_addr);
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"routersOnSubnet option is missing in DHCP server response. Assuming %u.%u.%u.%u\n",
	((unsigned char *)DhcpOptions.val[routersOnSubnet])[0],
	((unsigned char *)DhcpOptions.val[routersOnSubnet])[1],
	((unsigned char *)DhcpOptions.val[routersOnSubnet])[2],
	((unsigned char *)DhcpOptions.val[routersOnSubnet])[3]);
    }
  if ( ! DhcpOptions.val[hostName] )
    {
      DhcpOptions.val[hostName] = malloc(1);
      ((unsigned char *)DhcpOptions.val[hostName])[0] = 0;
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"hostName option is missing in DHCP server response\n");
    }
  if ( ! DhcpOptions.val[domainName] )
    {
      DhcpOptions.val[domainName] = malloc(1);
      ((unsigned char *)DhcpOptions.val[domainName])[0] = 0;
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"domainName option is missing in DHCP server response\n");
    }
  if ( ! DhcpOptions.val[dhcpIPaddrLeaseTime] ) /* did not get dhcpIPaddrLeaseTime */
    {
      DhcpOptions.val[dhcpIPaddrLeaseTime] = malloc(sizeof(long));
      *(unsigned int *)DhcpOptions.val[dhcpIPaddrLeaseTime] = htonl(DEFAULT_LEASETIME);
      DhcpOptions.len[dhcpIPaddrLeaseTime] = sizeof(long);
      DhcpOptions.num++;
      if ( DebugFlag )
	syslog(LOG_DEBUG,"dhcpIPaddrLeaseTime option is missing in DHCP server response. Assuming %u sec\n",LeaseTime);
    }
  if ( ! DhcpOptions.val[dhcpT1value] ) /* did not get T1 */
    {
      DhcpOptions.val[dhcpT1value] = malloc(sizeof(long));
      *(unsigned int *)DhcpOptions.val[dhcpT1value] = htonl((unsigned )(0.5*ntohl(*(unsigned int *)DhcpOptions.val[dhcpIPaddrLeaseTime])));
      DhcpOptions.len[dhcpT1value] = sizeof(long);
      DhcpOptions.num++;
    }
  if ( ! DhcpOptions.val[dhcpT2value] ) /* did not get T2 */
    {
      DhcpOptions.val[dhcpT2value] = malloc(sizeof(long));
      *(unsigned int *)DhcpOptions.val[dhcpT2value] = htonl((unsigned )(0.875*ntohl(*(unsigned int *)DhcpOptions.val[dhcpIPaddrLeaseTime])));
      DhcpOptions.len[dhcpT2value] = sizeof(long);
      DhcpOptions.num++;
    }
  if ( DhcpOptions.val[dhcpMessageType] )
    return *(unsigned char *)DhcpOptions.val[dhcpMessageType];
  return 0;
}
/*****************************************************************************/
void classIDsetup()
{
  struct utsname sname;
  if ( uname(&sname) ) syslog(LOG_ERR,"classIDsetup: uname: %m\n");
  DhcpIface.class_len=sprintf(DhcpIface.class_id,
  "%s %s %s",sname.sysname,sname.release,sname.machine);
}
/*****************************************************************************/
void clientIDsetup()
{
  unsigned char *c = DhcpIface.client_id;
  *c++ = dhcpClientIdentifier;
  if ( ClientID )
    {
      *c++ = ClientID_len + 1;	/* 1 for the field below */
      *c++ = 0;			/* type: string */
      memcpy(c,ClientID,ClientID_len);
      DhcpIface.client_len = ClientID_len + 3;
      return;
    }
  *c++ = ETHER_ADDR_LEN + 1;	/* length: 6 (MAC Addr) + 1 (# field) */
  *c++ = ARPHRD_ETHER;		/* type: Ethernet address */
  memcpy(c,ClientHwAddr,ETHER_ADDR_LEN);
  DhcpIface.client_len = ETHER_ADDR_LEN + 3;
}
/*****************************************************************************/
void releaseDhcpOptions()
{
  register int i;
  for (i=1;i<256;i++)
    if ( DhcpOptions.val[i] ) free(DhcpOptions.val[i]);
  memset(&DhcpOptions,0,sizeof(dhcpOptions));
}
/*****************************************************************************/
int dhcpSendAndRecv(xid,msg,buildUdpIpMsg)
unsigned xid,msg;
void (*buildUdpIpMsg)(unsigned);
{
  int i,len;
  int j=100000;
  struct ip *ip=(struct ip *)((struct udpiphdr *)UdpIpMsg.udpipmsg)->ip;
  struct udphdr *udp=(struct udphdr *)((struct udpiphdr *)UdpIpMsg.udpipmsg)->udp;
  do
    {
      do
    	{
      	  j+=j+100000;
	  buildUdpIpMsg(xid);
      	  if ( bpfSendFrame(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
		      sizeof(udpiphdr)+sizeof(dhcpMessage)) == -1 )
	    {
	      syslog(LOG_ERR,"bpfSendFrame: %m\n");
	      return -1;
	    }
      	  i=random();
    	}
      while ( bpfPeek(dhcpSocket,j+i%200000) );
      do
	{
	  memset(&UdpIpMsg,0,sizeof(udpipMessage));
      	  len=bpfRecvFrame(dhcpSocket,&UdpIpMsg,sizeof(udpipMessage));
	  if ( len == -1 )
    	    {
      	      syslog(LOG_ERR,"bpfRecvFrame: %m\n");
      	      return -1;
    	    }
	  if ( UdpIpMsg.ethhdr.ether_type != htons(ETHERTYPE_IP) )
	    continue;
	  if ( ip->ip_p != IPPROTO_UDP ) continue;
	  len-=sizeof(struct ether_header);
	  i=(int )ntohs(ip->ip_len);
	  if ( len < i )
	    {
	      if ( DebugFlag ) syslog(LOG_DEBUG,
		"corrupted IP packet of size=%d and ip_len=%d discarded\n",len,i);
	      continue;
	    }
	  len=i-(ip->ip_hl<<2);
	  i=(int )ntohs(udp->uh_ulen);
	  if ( len < i )
	    {
	      if ( DebugFlag ) syslog(LOG_DEBUG,
		"corrupted UDP msg of size=%d and uh_ulen=%d discarded\n",len,i);
	      continue;
	    }
	  len=udpipchk((udpiphdr *)UdpIpMsg.udpipmsg);
	  if ( len )
	    {
	      if ( DebugFlag )
	      	switch ( len )
		  {
		    case -1: syslog(LOG_DEBUG,
		      "corrupted IP packet with ip_len=%d in_cksum=%d discarded\n",
		      (int )ntohs(ip->ip_len),len);
	      	      break;
	     	    case -2: syslog(LOG_DEBUG,
		      "corrupted UDP msg with uh_ulen=%d in_cksum=%d discarded\n",
		      (int )ntohs(udp->uh_ulen),len);
	      	      break;
		  }
	      continue;
	    }
	  DhcpMsgRecv = (dhcpMessage *)&UdpIpMsg.udpipmsg[(ip->ip_hl<<2)+sizeof(struct udphdr)];
	  if ( DhcpMsgRecv->htype != ARPHRD_ETHER ) continue;
	  if ( DhcpMsgRecv->xid != xid ) continue;
	  if ( DhcpMsgRecv->op != DHCP_BOOTREPLY ) continue;
	  if ( parseDhcpMsgRecv() == msg ) return 0;
	  if ( *(unsigned char *)DhcpOptions.val[dhcpMessageType] == DHCP_NAK )
	    {
	      if ( DhcpOptions.val[dhcpMsg] )
		syslog(LOG_ERR,
		"dhcpInit: DHCP_NAK server response received: %s\n",
		(char *)DhcpOptions.val[dhcpMsg]);
	      else
		syslog(LOG_ERR,
		"dhcpInit: DHCP_NAK server response received\n");
	    }
    	}
      while ( bpfPeek(dhcpSocket,j/2) == 0 );
    }
  while ( 1 );
  return 1;
}
/*****************************************************************************/
int dhcpConfig()
{
  int s;
  FILE *f;
  char	cache_file[48];
  struct ifreq		ifr;
  struct ifaliasreq	ifra;
  struct sockaddr_in	*p;

  s = socket(AF_INET,SOCK_DGRAM,0);
  if ( s == -1 )
    {
      syslog(LOG_ERR,"dhcpConfig: socket: %m\n");
      return -1;
    }
  memset(&ifr,0,sizeof(struct ifreq));
  memcpy(ifr.ifr_name,IfName,IfName_len);
  ioctl(s,SIOCDIFADDR,&ifr);	/* old address, if any: SIOCAIFADDR would add an alias */
  memset(&ifra,0,sizeof(struct ifaliasreq));
  memcpy(ifra.ifra_name,IfName,IfName_len);
  p = (struct sockaddr_in *)&ifra.ifra_addr;
  p->sin_len = sizeof(struct sockaddr_in);
  p->sin_family = AF_INET;
  p->sin_addr.s_addr = DhcpIface.client_iaddr;
  p = (struct sockaddr_in *)&ifra.ifra_mask;
  p->sin_len = sizeof(struct sockaddr_in);
  p->sin_family = AF_INET;
  p->sin_addr.s_addr = *((unsigned int *)DhcpOptions.val[subnetMask]);
  p = (struct sockaddr_in *)&ifra.ifra_broadaddr;
  p->sin_len = sizeof(struct sockaddr_in);
  p->sin_family = AF_INET;
  p->sin_addr.s_addr = *((unsigned int *)DhcpOptions.val[broadcastAddr]);
  if ( ioctl(s,SIOCAIFADDR,&ifra) == -1 )
    {
      syslog(LOG_ERR,"dhcpConfig: ioctl SIOCAIFADDR: %m\n");
      close(s);
      return -1;
    }

  if ( SetDefaultRoute ) rtsockAddDefault(DhcpIface.giaddr);

  close(s);
  arpInform();
  sprintf(cache_file,DHCP_CACHE_FILE,IfName);
  s=open(cache_file,O_WRONLY|O_CREAT|O_TRUNC,S_IRUSR+S_IWUSR);
  if ( s == -1 ||
      write(s,(char *)&DhcpIface,sizeof(dhcpInterface)) == -1 ||
      close(s) == -1 )
    syslog(LOG_ERR,"dhcpConfig: open/write/close: %m\n");
  sprintf(cache_file,DHCP_HOSTINFO,IfName);
  f=fopen(cache_file,"w");
  if ( f )
    {
      int c = DhcpIface.client_iaddr & *((int *)DhcpOptions.val[subnetMask]);
      fprintf(f,"\
IPADDR=%u.%u.%u.%u\n\
NETMASK=%u.%u.%u.%u\n\
NETWORK=%u.%u.%u.%u\n\
BROADCAST=%u.%u.%u.%u\n\
GATEWAY=%u.%u.%u.%u\n\
HOSTNAME=%s\n\
DOMAIN=%s\n\
DNS=%u.%u.%u.%u\n\
DHCPSIADDR=%u.%u.%u.%u\n\
DHCPSHADDR=%02X:%02X:%02X:%02X:%02X:%02X\n\
DHCPSNAME=%s\n\
LEASETIME=%u\n\
RENEWALTIME=%u\n\
REBINDTIME=%u\n",
((unsigned char *)&DhcpIface.client_iaddr)[0],
((unsigned char *)&DhcpIface.client_iaddr)[1],
((unsigned char *)&DhcpIface.client_iaddr)[2],
((unsigned char *)&DhcpIface.client_iaddr)[3],
((unsigned char *)DhcpOptions.val[subnetMask])[0],
((unsigned char *)DhcpOptions.val[subnetMask])[1],
((unsigned char *)DhcpOptions.val[subnetMask])[2],
((unsigned char *)DhcpOptions.val[subnetMask])[3],
((unsigned char *)&c)[0],
((unsigned char *)&c)[1],
((unsigned char *)&c)[2],
((unsigned char *)&c)[3],
((unsigned char *)DhcpOptions.val[broadcastAddr])[0],
((unsigned char *)DhcpOptions.val[broadcastAddr])[1],
((unsigned char *)DhcpOptions.val[broadcastAddr])[2],
((unsigned char *)DhcpOptions.val[broadcastAddr])[3],
((unsigned char *)&DhcpIface.giaddr)[0],
((unsigned char *)&DhcpIface.giaddr)[1],
((unsigned char *)&DhcpIface.giaddr)[2],
((unsigned char *)&DhcpIface.giaddr)[3],
(char *)DhcpOptions.val[hostName],
(char *)DhcpOptions.val[domainName],
((unsigned char *)DhcpOptions.val[dns])[0],
((unsigned char *)DhcpOptions.val[dns])[1],
((unsigned char *)DhcpOptions.val[dns])[2],
((unsigned char *)DhcpOptions.val[dns])[3],
((unsigned char *)&DhcpIface.server_iaddr)[0],
((unsigned char *)&DhcpIface.server_iaddr)[1],
((unsigned char *)&DhcpIface.server_iaddr)[2],
((unsigned char *)&DhcpIface.server_iaddr)[3],
DhcpIface.server_haddr[0],
DhcpIface.server_haddr[1],
DhcpIface.server_haddr[2],
DhcpIface.server_haddr[3],
DhcpIface.server_haddr[4],
DhcpIface.server_haddr[5],
DhcpMsgRecv->sname,
ntohl(*(unsigned int *)DhcpOptions.val[dhcpIPaddrLeaseTime]),
ntohl(*(unsigned int *)DhcpOptions.val[dhcpT1value]),
ntohl(*(unsigned int *)DhcpOptions.val[dhcpT2value]));
      fclose(f);
    }
  else
    syslog(LOG_ERR,"dhcpConfig: fopen: %m\n");
  if ( ReplResolvConf )
    {
      rename(RESOLV_CONF,""RESOLV_CONF".sv");
      f=fopen(RESOLV_CONF,"w");
      if ( f )
	{
	  int i;
	  fprintf(f,"domain %s\n",(char *)DhcpOptions.val[domainName]);
	  for (i=0;i<DhcpOptions.len[dns];i+=4)
	    fprintf(f,"nameserver %u.%u.%u.%u\n",
	    ((unsigned char *)DhcpOptions.val[dns])[i],
	    ((unsigned char *)DhcpOptions.val[dns])[i+1],
	    ((unsigned char *)DhcpOptions.val[dns])[i+2],
	    ((unsigned char *)DhcpOptions.val[dns])[i+3]);
	  fclose(f);
	}
      else
	syslog(LOG_ERR,"dhcpConfig: fopen: %m\n");
    }
  if ( ! WaitFlag )
    fprintf(stdout,"dhcpcd: your IP address = %u.%u.%u.%u\n",
      ((unsigned char *)&DhcpIface.client_iaddr)[0],
      ((unsigned char *)&DhcpIface.client_iaddr)[1],
      ((unsigned char *)&DhcpIface.client_iaddr)[2],
      ((unsigned char *)&DhcpIface.client_iaddr)[3]);
  if ( SetHostName && DhcpOptions.len[hostName] )
    {
       sethostname(DhcpOptions.val[hostName],DhcpOptions.len[hostName]);
       if ( ! WaitFlag )
	 fprintf(stdout,"dhcpcd: your hostname = %s\n",
		 (char *)DhcpOptions.val[hostName]);
    }
  if ( SetDomainName && DhcpOptions.len[domainName] )
    {
       setdomainname(DhcpOptions.val[domainName],DhcpOptions.len[domainName]);
       if ( ! WaitFlag )
	 fprintf(stdout,"dhcpcd: your domainname = %s\n",
		 (char *)DhcpOptions.val[domainName]);
    }
  if ( Cfilename )
    if ( fork() == 0 )
      {
	char *argc[2];
	argc[0]=Cfilename;
	argc[1]=NULL;
	if ( execve(Cfilename,argc,ProgramEnviron) )
	  syslog(LOG_ERR,"error executing \"%s\": %m\n",
	  Cfilename);
	exit(0);
      }
  if ( *(unsigned int *)DhcpOptions.val[dhcpIPaddrLeaseTime] == 0xffffffff )
    {
      syslog(LOG_INFO,"infinite IP address lease time. Exiting\n");
      exit(0);
    }
  return 0;
}
/*****************************************************************************/
int readDhcpCache()
{
  int i,o;
  char cache_file[48];
  sprintf(cache_file,DHCP_CACHE_FILE,IfName);
  i=open(cache_file,O_RDONLY);
  if ( i == -1 ) return -1;
  o=read(i,(char *)&DhcpIface,sizeof(dhcpInterface));
  close(i);
  if ( o < sizeof(dhcpInterface) ) return -1;
  prev_ip_addr=DhcpIface.client_iaddr;
  return 0;
}
/*****************************************************************************/
void deleteDhcpCache()
{
  char cache_file[48];
  sprintf(cache_file,DHCP_CACHE_FILE,IfName);
  unlink(cache_file);
}
/*****************************************************************************/
void *dhcpStart()
{
  dhcpSocket = bpfOpenForInterface(IfName,ClientHwAddr);
  if ( dhcpSocket == -1 )
    {
      syslog(LOG_ERR,"dhcpStart: bpfOpenForInterface: %m\n");
      exit(1);
    }
  return &dhcpInit;
}
/*****************************************************************************/
void *dhcpReboot()
{
  dhcpStart();
  ip_id=time(NULL)&0xffff;
  srandom(ip_id);
  memset(&DhcpOptions,0,sizeof(DhcpOptions));
  memset(&DhcpIface,0,sizeof(dhcpInterface));
  if ( readDhcpCache() )
    {
      memset(&DhcpIface,0,sizeof(dhcpInterface));
      if ( ClassID )
	{
    	  memcpy(DhcpIface.class_id,ClassID,ClassID_len);
	  DhcpIface.class_len=ClassID_len;
	}
      else
    	classIDsetup();
      clientIDsetup();
      return dhcpInit();
    }
  return dhcpRequest(random(),&buildDhcpReboot);
}
/*****************************************************************************/
void *dhcpInit()
{
  releaseDhcpOptions();

#ifdef DEBUG
fprintf(stderr,"ClassID  = \"%s\"\n\
ClientID = \"%u.%u.%u.%02X.%02X.%02X.%02X.%02X.%02X\"\n",
DhcpIface.class_id,
DhcpIface.client_id[0],DhcpIface.client_id[1],DhcpIface.client_id[2],
DhcpIface.client_id[3],DhcpIface.client_id[4],DhcpIface.client_id[5],
DhcpIface.client_id[6],DhcpIface.client_id[7],DhcpIface.client_id[8]);
#endif

/* send the message and read and parse replies into DhcpOptions */
  if ( DebugFlag ) syslog(LOG_DEBUG,"broadcasting DHCP_DISCOVER\n");
  if ( dhcpSendAndRecv(random(),DHCP_OFFER,&buildDhcpDiscover) )
    {
      dhcpStop();
      return 0;
    }
/* DHCP_OFFER received */
  memcpy(DhcpIface.server_haddr,UdpIpMsg.ethhdr.ether_shost,ETHER_ADDR_LEN);
  DhcpIface.server_iaddr = *(unsigned int *)DhcpOptions.val[dhcpServerIdentifier];
  prev_ip_addr = DhcpIface.client_iaddr;
  DhcpIface.client_iaddr = DhcpMsgRecv->yiaddr;
  DhcpIface.giaddr = *((unsigned int *)DhcpOptions.val[routersOnSubnet]);
  DhcpIface.xid = DhcpMsgRecv->xid;
  if ( DebugFlag )
    syslog(LOG_DEBUG,"DHCP_OFFER received from %s (%u.%u.%u.%u)\n",
    DhcpMsgRecv->sname,
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[0],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[1],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[2],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[3]);

  return dhcpRequest(DhcpIface.xid,&buildDhcpRequest);
}
/*****************************************************************************/
void *dhcpRequest(xid,buildDhcpMsg)
unsigned xid;
void (*buildDhcpMsg)(unsigned);
{
/* send the message and read and parse replies into DhcpOptions */
  if ( DebugFlag )
    syslog(LOG_DEBUG,"broadcasting DHCP_REQUEST for %u.%u.%u.%u\n",
	   ((unsigned char *)&DhcpIface.client_iaddr)[0],
	   ((unsigned char *)&DhcpIface.client_iaddr)[1],
	   ((unsigned char *)&DhcpIface.client_iaddr)[2],
	   ((unsigned char *)&DhcpIface.client_iaddr)[3]);
  if ( dhcpSendAndRecv(xid,DHCP_ACK,buildDhcpMsg) ) return dhcpInit();
  ReqSentTime=time(NULL);
  if ( DebugFlag ) syslog(LOG_DEBUG,
    "DHCP_ACK received from %s (%u.%u.%u.%u)\n",DhcpMsgRecv->sname,
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[0],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[1],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[2],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[3]);
#ifdef ARPCHECK
/* check if the offered IP address already in use */
  if ( arpCheck() )
    {
      if ( DebugFlag ) syslog(LOG_DEBUG,
	"requested %u.%u.%u.%u address is in use\n",
	((unsigned char *)&DhcpIface.client_iaddr)[0],
	((unsigned char *)&DhcpIface.client_iaddr)[1],
	((unsigned char *)&DhcpIface.client_iaddr)[2],
	((unsigned char *)&DhcpIface.client_iaddr)[3]);
      dhcpDecline();
      DhcpIface.client_iaddr = 0;
      return dhcpInit();
    }
  if ( DebugFlag ) syslog(LOG_DEBUG,
    "verified %u.%u.%u.%u address is not in use\n",
    ((unsigned char *)&DhcpIface.client_iaddr)[0],
    ((unsigned char *)&DhcpIface.client_iaddr)[1],
    ((unsigned char *)&DhcpIface.client_iaddr)[2],
    ((unsigned char *)&DhcpIface.client_iaddr)[3]);
#endif
  DhcpIface.giaddr = *(unsigned int *)DhcpOptions.val[routersOnSubnet];
  if ( dhcpConfig() )
    {
      dhcpStop();
      return 0;
    }
  if ( DhcpIface.client_iaddr != prev_ip_addr ) /* IP address has changed */
    {
      if ( fork() == 0 )
	{
	  char *argc[4],filename[64],ipaddrstr[16];
	  sprintf(ipaddrstr,"%u.%u.%u.%u",
	  ((unsigned char *)&DhcpIface.client_iaddr)[0],
	  ((unsigned char *)&DhcpIface.client_iaddr)[1],
	  ((unsigned char *)&DhcpIface.client_iaddr)[2],
	  ((unsigned char *)&DhcpIface.client_iaddr)[3]);
	  sprintf(filename,EXEC_ON_IP_CHANGE,IfName);
	  argc[0]=PROGRAM_NAME;
	  argc[1]=ipaddrstr;
	  if ( DebugFlag )
	    argc[2]="-d";
	  else
	    argc[2]=NULL;
	  argc[3]=NULL;
	  if ( execve(filename,argc,ProgramEnviron) && errno != ENOENT )
	    syslog(LOG_ERR,"error executing \"%s %s\": %m\n",
	    filename,ipaddrstr);
	  exit(0);
	}
      prev_ip_addr=DhcpIface.client_iaddr;
    }
  return &dhcpBound;
}
/*****************************************************************************/
void *dhcpBound()
{
  int i;
  if ( sigsetjmp(env,0xffff) ) return &dhcpRenew;
  i=ReqSentTime+ntohl(*(unsigned int *)DhcpOptions.val[dhcpT1value])-time(NULL);
  if ( i > 0 )
    alarm(i);
  else
    return &dhcpRenew;

  sleep(ntohl(*(u_int *)DhcpOptions.val[dhcpT1value]));
  return &dhcpRenew;
}
/*****************************************************************************/
void *dhcpRenew()
{
  int i;
  if ( sigsetjmp(env,0xffff) ) return &dhcpRebind;
  i = ReqSentTime+ntohl(*(unsigned int *)DhcpOptions.val[dhcpT2value])-time(NULL);
  if ( i > 0 )
    alarm(i);
  else
    return &dhcpRebind;

  if ( DebugFlag )
    syslog(LOG_DEBUG,"sending DHCP_REQUEST for %u.%u.%u.%u to %u.%u.%u.%u\n",
	   ((unsigned char *)&DhcpIface.client_iaddr)[0],
	   ((unsigned char *)&DhcpIface.client_iaddr)[1],
	   ((unsigned char *)&DhcpIface.client_iaddr)[2],
	   ((unsigned char *)&DhcpIface.client_iaddr)[3],
	   ((unsigned char *)&DhcpIface.server_iaddr)[0],
	   ((unsigned char *)&DhcpIface.server_iaddr)[1],
	   ((unsigned char *)&DhcpIface.server_iaddr)[2],
	   ((unsigned char *)&DhcpIface.server_iaddr)[3]);
  if ( dhcpSendAndRecv(random(),DHCP_ACK,&buildDhcpRenew) ) return &dhcpRebind;
  ReqSentTime=time(NULL);
  if ( DebugFlag ) syslog(LOG_DEBUG,
    "DHCP_ACK received from %s (%u.%u.%u.%u)\n",DhcpMsgRecv->sname,
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[0],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[1],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[2],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[3]);
  DhcpIface.giaddr = *(unsigned int *)DhcpOptions.val[routersOnSubnet];
  if ( SetDefaultRoute ) rtsockAddDefault(DhcpIface.giaddr);
  return &dhcpBound;
}
/*****************************************************************************/
void *dhcpRebind()
{
  int i;
  if ( sigsetjmp(env,0xffff) ) return &dhcpStop;
  i = ReqSentTime+ntohl(*(unsigned int *)DhcpOptions.val[dhcpIPaddrLeaseTime])-time(NULL);
  if ( i > 0 )
    alarm(i);
  else
    return &dhcpStop;

  if ( DebugFlag )
    syslog(LOG_DEBUG,"broadcasting DHCP_REQUEST for %u.%u.%u.%u\n",
	   ((unsigned char *)&DhcpIface.client_iaddr)[0],
	   ((unsigned char *)&DhcpIface.client_iaddr)[1],
	   ((unsigned char *)&DhcpIface.client_iaddr)[2],
	   ((unsigned char *)&DhcpIface.client_iaddr)[3]);
  if ( dhcpSendAndRecv(random(),DHCP_ACK,&buildDhcpRebind) ) return &dhcpStop;
  ReqSentTime=time(NULL);
  if ( DebugFlag ) syslog(LOG_DEBUG,
    "DHCP_ACK received from %s (%u.%u.%u.%u)\n",DhcpMsgRecv->sname,
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[0],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[1],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[2],
    ((unsigned char *)DhcpOptions.val[dhcpServerIdentifier])[3]);
  DhcpIface.giaddr = *(unsigned int *)DhcpOptions.val[routersOnSubnet];
  if ( SetDefaultRoute ) rtsockAddDefault(DhcpIface.giaddr);
  return &dhcpBound;
}
/*****************************************************************************/
void *dhcpRelease()
{
  deleteDhcpCache();
  if ( DhcpIface.client_iaddr == 0 ) return &dhcpInit;

  buildDhcpRelease(random());

  if ( DebugFlag )
    syslog(LOG_DEBUG,"sending DHCP_RELEASE for %u.%u.%u.%u to %u.%u.%u.%u\n",
	   ((unsigned char *)&DhcpIface.client_iaddr)[0],
	   ((unsigned char *)&DhcpIface.client_iaddr)[1],
	   ((unsigned char *)&DhcpIface.client_iaddr)[2],
	   ((unsigned char *)&DhcpIface.client_iaddr)[3],
	   ((unsigned char *)&DhcpIface.server_iaddr)[0],
	   ((unsigned char *)&DhcpIface.server_iaddr)[1],
	   ((unsigned char *)&DhcpIface.server_iaddr)[2],
	   ((unsigned char *)&DhcpIface.server_iaddr)[3]);
  if ( bpfSendFrame(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
	      sizeof(udpiphdr)+sizeof(dhcpMessage)) == -1 )
    syslog(LOG_ERR,"dhcpRelease: bpfSendFrame: %m\n");
  arpRelease(); /* clear ARP cache entries for client IP addr */
  return &dhcpInit;
}
/*****************************************************************************/
void *dhcpStop()
{
  int s;
  struct ifreq ifr;
  struct sockaddr_in	*p = (struct sockaddr_in *)&(ifr.ifr_addr);

  releaseDhcpOptions();
  s = socket(AF_INET,SOCK_DGRAM,0);
  if ( s == -1 )
    {
      syslog(LOG_ERR,"dhcpStop: socket: %m\n");
      s=dhcpSocket;
    }
  else
    close(dhcpSocket);
  memset(&ifr,0,sizeof(struct ifreq));
  memcpy(ifr.ifr_name,IfName,IfName_len);
  p->sin_family = AF_INET;
  p->sin_addr.s_addr = 0;
  if ( ioctl(s,SIOCSIFADDR,&ifr) == -1 )
    syslog(LOG_ERR,"dhcpStop: ioctl SIOCSIFADDR: %m\n");
  if ( ioctl(s,SIOCSIFFLAGS,&ifr) )
    syslog(LOG_ERR,"dhcpStop: ioctl SIOCSIFFLAGS: %m\n");
  close(s);
  if ( ReplResolvConf )
    rename(""RESOLV_CONF".sv",RESOLV_CONF);
  return &dhcpStart;
}
/*****************************************************************************/
#ifdef ARPCHECK
void *dhcpDecline()
{
  memset(&UdpIpMsg,0,sizeof(udpipMessage));
  memcpy(UdpIpMsg.ethhdr.ether_dhost,MAC_BCAST_ADDR,ETHER_ADDR_LEN);
  memcpy(UdpIpMsg.ethhdr.ether_shost,ClientHwAddr,ETHER_ADDR_LEN);
  UdpIpMsg.ethhdr.ether_type = htons(ETHERTYPE_IP);
  buildDhcpDecline(random());
  udpipgen((udpiphdr *)&UdpIpMsg.udpipmsg,0,INADDR_BROADCAST,
  htons(DHCP_CLIENT_PORT),htons(DHCP_SERVER_PORT),sizeof(dhcpMessage));
  if ( DebugFlag ) syslog(LOG_DEBUG,"broadcasting DHCP_DECLINE\n");
  if ( bpfSendFrame(dhcpSocket,&UdpIpMsg,sizeof(struct ether_header)+
	      sizeof(udpiphdr)+sizeof(dhcpMessage)) == -1 )
    syslog(LOG_ERR,"dhcpDecline: bpfSendFrame: %m\n");
  return &dhcpInit;
}
#endif
/*****************************************************************************/
void checkIfAlreadyRunning()
{
  int o;
  char pidfile[48];
  sprintf(pidfile,PID_FILE_PATH,IfName);
  o=open(pidfile,O_RDONLY);
  if ( o == -1 ) return;
  close(o);
  fprintf(stderr,"\
****  %s: already running\n\
****  %s: if not then delete %s file\n",ProgramName,ProgramName,pidfile);
  exit(1);
}
