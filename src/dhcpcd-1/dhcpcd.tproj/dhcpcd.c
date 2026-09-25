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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>
#include <sys/socket.h>
#include <net/if.h>
#include "dhcpcd.h"
#include "client.h"
#include "bootcompat.h"
#include "signals.h"

char		*ProgramName	=	NULL;
char            **ProgramEnviron=       NULL;
char		*IfName		=	DEFAULT_IFNAME;
char		*HostName	=	NULL;
char		*Cfilename	=	NULL;
unsigned char	*ClassID	=	NULL;
unsigned char	*ClientID	=	NULL;
void		*(*currState)()	=	&dhcpReboot;
int		DebugFlag	=	0;
int		BeRFC1541	=	0;
int		LeaseTime	=	DEFAULT_LEASETIME;
int		IfName_len	=	DEFAULT_IFNAME_LEN;
int		ClassID_len	=	0;
int		ClientID_len	=	0;
int		HostName_len	=	0;
int		ReplResolvConf	=	1;
int		SetDomainName	=	0;
int		SetHostName	=	0;
int		WaitFlag	=	0;
int		SetDefaultRoute	=	1;
/*****************************************************************************/
int main(argn,argc,argv)
int argn;
char *argc[],*argv[];
{
  int killFlag		=	0;
  int s			=	1;
  int k			=	1;
  int i			=	1;
  time_t TimeOut	=	DEFAULT_TIMEOUT;

  if ( getuid() )
    {
      fprintf(stderr,"****  %s: not a superuser\n",argc[0]);
      exit(1);
    }

  while ( argc[i] )
    if ( argc[i][0]=='-' )
prgs: switch ( argc[i][s] )
	{
	  case 0:
	    i++;
	    s=1;
	    break;
	  case 'k':
	    s++;
	    killFlag=1;
	    goto prgs;
	  case 'd':
	    s++;
	    DebugFlag=1;
	    goto prgs;
	  case 'r':
	    s++;
	    BeRFC1541=1;
	    goto prgs;
	  case 'D':
	    s++;
	    SetDomainName=1;
	    goto prgs;
	  case 'H':
	    s++;
	    SetHostName=1;
	    goto prgs;
	  case 'R':
	    s++;
	    ReplResolvConf=0;
	    goto prgs;
	  case 'w':
	    s++;
	    WaitFlag=1;
	    goto prgs;
	  case 'G':
	    s++;
	    SetDefaultRoute=0;
	    goto prgs;
	  case 'c':
	    i++;
	    Cfilename=argc[i++];
	    if ( Cfilename == NULL || Cfilename[0] == '-' ) goto usage;
	    break;
	  case 'i':
	    i++;
	    ClassID=argc[i++];
	    if ( ClassID == NULL || ClassID[0] == '-' ) goto usage;
	    s=1;
	    if ( (ClassID_len=strlen(ClassID)) < CLASS_ID_MAX_LEN+1 ) break;
	    fprintf(stderr,"****  %s: too long ClassID string: strlen=%d\n",
	    argc[0],ClassID_len);
	    goto usage;
	  case 'I':
	    i++;
	    ClientID=argc[i++];
	    if ( ClientID == NULL || ClientID[0] == '-' ) goto usage;
	    s=1;
	    if ( (ClientID_len=strlen(ClientID)) < CLIENT_ID_MAX_LEN ) break;
	    fprintf(stderr,"****  %s: too long ClientID string: strlen=%d\n",
	    argc[0],ClientID_len);
	    goto usage;
	  case 'h':
	    i++;
	    HostName=argc[i++];
	    if ( HostName == NULL || HostName[0] == '-' ) goto usage;
	    s=1;
	    if ( (HostName_len=strlen(HostName)) < HOSTNAME_MAX_LEN ) break;
	    fprintf(stderr,"****  %s: too long HostName: strlen=%d\n",
	    argc[0],HostName_len);
	    goto usage;
	    break;
	  case 't':
	    i++;
	    if ( argc[i] )
	      TimeOut=atol(argc[i++]);
	    else
	      goto usage;
	    s=1;
	    if ( TimeOut > 0 ) break;
	    goto usage;
	  case 'l':
	    i++;
	    if ( argc[i] )
	      LeaseTime=atol(argc[i++]);
	    else
	      goto usage;
	    s=1;
	    if ( LeaseTime > 0 ) break;
          default:
usage:	    fprintf(stderr,"\
DHCP Client Daemon v."PROGRAM_VERSION"\n\
Copyright (C) 1996 - 1997 Yoichi Hariguchi <yoichi@fore.com>\n\
Copyright (C) January, 1998 Sergei Viznyuk <sv@phystech.com>\n\
Usage: dhcpcd [-dkrDHRwG] [-l leasetime] [-h hostname] [-t timeout]\n\
       [-i vendorClassID] [-I ClientID] [-c filename] [interface]\n");
	    exit(1);
	}
    else
      argc[k++]=argc[i++];
  if ( k > 1 )
    {
      if ( (IfName_len=strlen(argc[1])) > IFNAMSIZ )
        goto usage;
      else
        IfName=argc[1];
    }
  ProgramName=argc[0];
  ProgramEnviron=argv;
  if ( killFlag ) killPid();
  checkIfAlreadyRunning();
  openlog(PROGRAM_NAME,LOG_PID|LOG_CONS,LOG_LOCAL0);	/* 0800_Network runs before syslogd */
  signalSetup();
  alarm(TimeOut);
  currState=(void *(*)())currState();
  alarm(0);
  if ( currState == NULL ) exit(1);
#ifndef DEBUG
  if ( WaitFlag ) bootcompatPrint();
  if ( fork() ) exit(0); /* got into bound state. */
  setsid();
  freopen("/dev/null","w",stdout);	/* config=$(dhcpcd -w ...) waits for EOF */
#endif
  chdir("/");
  writePidFile();
  do currState=(void *(*)())currState(); while ( currState );
  deletePidFile();
  exit(1);
}
