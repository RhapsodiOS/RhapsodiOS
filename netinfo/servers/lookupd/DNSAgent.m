/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
	DNSAgent.m

	DNS lookup agent for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "DNSAgent.h"
#import "LUPrivate.h"
#import "Controller.h"
#import "Syslog.h"
#import <sys/types.h>
#import <netinet/in.h>
#import <netdb.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <string.h>
#import <arpa/nameser.h>
#import <resolv.h>
#import <sys/param.h>
#import "stringops.h"
#include <stdio.h>
#include <string.h>
#include <libc.h>

extern int res_search(const char *, int, int, u_char *, int);
extern char *nettoa(unsigned long);

static DNSAgent *_sharedDNSAgent = nil;

/* XXX Max size of a DNS reply packet */
#define MaxDNSReplyPacketSize 1024
#define MaxDNSHostNameLength 1024
#ifndef T_SRV
#define T_SRV		 33
#endif

static inline short getDNSShort(char *p)
{
	union {
		char b[2];
		short s;
	} u;
	short datum;

	u.b[0] = *p;
	u.b[1] = *(p + 1);

	datum = u.s;
	return ntohs(datum);
}

static inline unsigned long getDNSUnsignedLong(char *p)
{
	union {
		char b[4];
		unsigned long l;
	} u;
	unsigned long datum;

	u.b[0] = *p;
	u.b[1] = *(p + 1);
	u.b[2] = *(p + 2);
	u.b[3] = *(p + 3);

	datum = u.l;
	return ntohl(datum);
}

@implementation DNSAgent

- (DNSAgent *)init
{
	BOOL isRunning;

	if (didInit) return self;

	[super init];

	[controller rpcLock];
	res_init();
	[controller rpcUnlock];
	isRunning = _res.options & RES_INIT;
	if (!isRunning)
	{
		[self dealloc];
		return nil;
	}

	stats = [[LUDictionary alloc] init];
	[stats setBanner:"DNSAgent statistics"];

	myDomainName = copyString(_res.defdname);
	[stats setValue:"Domain_Name_System" forKey:"information_system"];
	[stats setValue:myDomainName forKey:"domain_name"];

	threadLock = [[NSLock alloc] init];

	return self;
}

+ (DNSAgent *)alloc
{
	char str[128];

	if (_sharedDNSAgent != nil)
	{
		[_sharedDNSAgent retain];
		return _sharedDNSAgent;
	}

	_sharedDNSAgent = [super alloc];
	_sharedDNSAgent = [_sharedDNSAgent init];
	if (_sharedDNSAgent == nil) return nil;

	sprintf(str, "Allocated DNSAgent 0x%x\n", (int)_sharedDNSAgent);
	[lookupLog syslogDebug:str];

	return _sharedDNSAgent;
}

- (void)reInit
{
	[controller rpcLock];
	res_init();
	[controller rpcUnlock];
}

- (const char *)name
{
	return "Domain_Name_System";
}

- (const char *)shortName
{
	return "DNSAgent";
}

- (void)dealloc
{
	char str[128];

	if (stats != nil) [stats release];
	freeString(myDomainName);
	myDomainName = NULL;
	if (threadLock != nil) [threadLock release];

	sprintf(str, "Deallocated DNSAgent 0x%x\n", (int)self);
	[lookupLog syslogDebug:str];

	[super dealloc];

	_sharedDNSAgent = nil;
}

- (LUDictionary *)statistics
{
	return stats;
}

- (void)resetStatistics
{
	if (stats != nil) [stats release];
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"DNSAgent statistics"];
	[stats setValue:"Domain_Name_System" forKey:"information_system"];
	[stats setValue:myDomainName forKey:"domain_name"];
}

- (BOOL)isValid:(LUDictionary *)item
{
	time_t now, ttl;
	time_t bestBefore;

	if (item == nil) return NO;

	bestBefore = [item unsignedLongForKey:"_lookup_DNS_timestamp"];
	ttl = [item unsignedLongForKey:"_lookup_DNS_time_to_live"];
	bestBefore += ttl;

	now = time(0);
	if (now > bestBefore) return NO;
	return YES;
}

- (LUDictionary *)stamp:(LUDictionary *)item
{
	[item setAgent:self];
	[item setValue:"DNS" forKey:"_lookup_info_system"];
	return item;
}

- (LUDictionary *)dictForDNSReply:(char *)r length:(int)rlen
{
	LUDictionary *host;
	char *longName = NULL;
	char *shortName = NULL;
	char *domainName = NULL;
	char *cp, *eom;
	struct in_addr a;
	int i, len;
	HEADER *h;
	short nquestions, nanswers, type, class;
	char name[MaxDNSHostNameLength];
	BOOL setTTL = YES;
	time_t now;
	time_t ttl;
	char scratch[32];
	int alias;

	if (r == NULL) return nil;
	h = (HEADER *)r;
	if (h->rcode != NOERROR) return nil;

	nanswers = ntohs(h->ancount);
	nquestions = ntohs(h->qdcount);
	if (nanswers <= 0) return nil;

 	host = [[LUDictionary alloc] init];

	alias = 0;

	cp = r + sizeof(HEADER);
	eom = r + rlen;

	for (i = 0; i < nquestions; i++)
	{
		/* skip over question field [name + (short)type + (short)class] */
		len = dn_expand(r, eom, cp, name, MaxDNSHostNameLength);
		cp += len + 2 + 2;
	}

	for (i = 0; i < nanswers; i++)
	{
		len = dn_expand(r, eom, cp, name, MaxDNSHostNameLength);
		cp += len;
		type = getDNSShort(cp);
		cp += 2;
		class = getDNSShort(cp);
		cp += 2;
		ttl = getDNSUnsignedLong(cp);
		cp += 4;

		if (setTTL)
		{
			sprintf(scratch, "%lu", ttl);
			[host setValue:scratch forKey:"_lookup_DNS_time_to_live"];
			now = time(0);
			sprintf(scratch, "%lu", now);
			[host setValue:scratch forKey:"_lookup_DNS_timestamp"];
			setTTL = NO;
		}

		len = getDNSShort(cp);
		cp += 2;

		switch (type)
		{
			case T_A:
				if (class == C_IN)
				{
					longName = lowerCase(name);
					[host mergeValue:longName forKey:"name"];
					if (i == 0)
					{
						shortName = prefix(longName, '.');
						domainName = postfix(longName, '.');
					}
					freeString(longName);
					longName = NULL;
					bcopy(cp, (char *)&a.s_addr, len);
					[host mergeValue:inet_ntoa(a) forKey:"ip_address"];
				}
				break;
			case T_CNAME:
				alias++;
				longName = lowerCase(name);
				[host mergeValue:longName forKey:"alias"];
				freeString(longName);
				longName = NULL;
	
				len = dn_expand(r, eom, cp, name, MaxDNSHostNameLength);
				longName = lowerCase(name);
				[host mergeValue:longName forKey:"alias"];
				if (i == 0)
				{
					shortName = prefix(longName, '.');
					domainName = postfix(longName, '.');
				}
				freeString(longName);
				longName = NULL;
				break;
			case T_PTR:
				len = dn_expand(r, eom, cp, name, MaxDNSHostNameLength);
				longName = lowerCase(name);
				[host mergeValue:longName forKey:"name"];
				if (i == 0)
				{
					shortName = prefix(longName, '.');
					domainName = postfix(longName, '.');
				}
				freeString(longName);
				longName = NULL;
				break;
			case T_TXT:
				{
				char *ocp, *p;
				char *dst = longName = (char *)malloc(len);
			
				ocp = p = cp;
			
				while (p < ocp + len)
				{
					unsigned char n = (unsigned char) *p++;
					bcopy(p, dst, (int) n);
					p += n;
					dst += n;
				}
				*dst = '\0';
				[host mergeValue:longName forKey:"_lookup_DNS_record"];
				free(longName);
				break;
				}
			case T_SRV:
				len = dn_expand(r, eom, cp + 6, name, MaxDNSHostNameLength);
				sprintf(scratch, "%u", getDNSShort(cp));
				[host addValue:scratch forKey:"_lookup_host_priority"];
				sprintf(scratch, "%u", getDNSShort(cp + 2));
				[host addValue:scratch forKey:"_lookup_host_weight"];
				sprintf(scratch, "%u", getDNSShort(cp + 4));
				[host addValue:scratch forKey:"port"];
				[host addValue:name forKey:"target"];
				break;
			default:
				break;
		}
		cp += len;
	}

	if (alias > 0)
	{
		[host mergeValues:[host valuesForKey:"alias"] forKey:"name"];
		[host removeKey:"alias"];
	}

	if (domainName != NULL)
	{
		[host setValue:domainName forKey:"_lookup_domain"];
		if (strcmp(domainName, myDomainName) == 0)
			[host mergeValue:shortName forKey:"name"];
	}

	freeString(shortName);
	shortName = NULL;
	freeString(domainName);
	domainName = NULL;

	return host;
}

- (LUDictionary *)hostWithName:(char *)name
{
	LUDictionary *host = nil;
	char res[MaxDNSReplyPacketSize];
	int len;

	/* resolver client doesn't support multi-threaded access */
	[threadLock lock];
	
	len = res_search(name, C_IN, T_A, res, MaxDNSReplyPacketSize);

	if (len <= 0)
	{
		[threadLock unlock];
		return nil;
	}

	host = [self dictForDNSReply:res length:len];
	[threadLock unlock];

	if (host != nil) return [self stamp:host];
	
	return nil;
}

- (LUDictionary *)hostWithInternetAddress:(struct in_addr *)addr
{
	LUDictionary *host = nil;
	char name[MaxDNSHostNameLength];
	char res[MaxDNSReplyPacketSize];
	int len;
	union
	{
		unsigned long a;
		unsigned char b[4];
	} ab;

	ab.a = addr->s_addr;
	
	sprintf(name, "%u.%u.%u.%u.in-addr.arpa",
		ab.b[3], ab.b[2], ab.b[1], ab.b[0]);

	/* resolver client doesn't support multi-threaded access */
	[threadLock lock];
	len = res_search(name, C_IN, T_PTR, res, MaxDNSReplyPacketSize);

	if (len <= 0)
	{
		[threadLock unlock];
		return nil;
	}

	host = [self dictForDNSReply:res length:len];
	[threadLock unlock];

	if (host != nil)
	{
		[host mergeValue:inet_ntoa(*addr) forKey:"ip_address"];
		return [self stamp:host];
	}

	return nil;
}

/*
 * Network lookups are a hack to reuse as much of the host
 * lookup code as possible. I figure there's little point
 * compromising host lookups to optimize network lookups
 * when the latter are relatively infrequent. I wanted to
 * avoid touching too much of the existing code, also.
 *
 * This code will probably break on architectures with
 * non-continuous byte ordering.
 *
 * 98-02-14 lukeh
 */ 
- (LUDictionary *)convertHost:(LUDictionary *)host
{
	char *address;
	unsigned long ip;
	char str[sizeof("255.255.255.255")];
	
	if (host == nil)
		return nil;
	
	address = [host valueForKey:"ip_address"];
	if (address == NULL)
		return nil;
	
	/*
	 * Get the "network" address, in host byte order.
	 */
	ip = ntohl(inet_addr(address));
	if (ip == INADDR_NONE)
		return nil;

	/*
	 * Verify that the address is indeed a "network" address,
	 * by checking that the least significant byte is non
	 * zero.
	 */
	if (ip & 0x000000ff)
	{
		return nil;
	}
	else if (ip)
	{
		/*
		 * Network addresses are packed with leading zeros.
		 * In network byte order, this looks like 0.203.13.32
		 * for the network 203.13.32.0. We need to right-shift
		 * any contiguous zero bytes so that nettoa()
		 * is happy.
		 */
		while ((ip & 0x000000ff) == 0) ip >>= 8;
	}

	sprintf(str, "%s", nettoa(ip));
	[host setValue:str forKey:"address"]; 
	[host removeKey:"ip_address"];

	return host;
}

- (LUDictionary *)networkWithName:(char *)name
{
	LUDictionary *host;
	LUDictionary *network;
	
	host = [self hostWithName:name];
	network = [self convertHost:host];
	
	if (network == nil) [host release];

	return network;
}

- (LUDictionary *)networkWithInternetAddress:(struct in_addr *)addrp
{
	LUDictionary *host;
	LUDictionary *network;
	struct in_addr addr;

	addr.s_addr = addrp->s_addr;

	if (addr.s_addr & 0xff000000)
	{
		/*
		 * This is a host address, not a network address.
		 * (We don't know about networks not on byte
		 * boundaries.)
		 */
		return nil;
	}
	else if (addr.s_addr)
	{
		/*
		 * Network addresses are packed with leading zeros.
		 * In network byte order, this looks like 0.203.13.32
		 * for the network 203.13.32.0. We need to left-shift
		 * any contiguous zero bytes so that gethostbyname()
		 * is happy.
		 */
		while ((addr.s_addr & 0xff000000) == 0)
			addr.s_addr <<= 8;
	}
	
	/*
	 * Convert to network byte order to keep gethostbyname()
	 * happy.
	 */
	addr.s_addr = htonl(addr.s_addr);
	host = [self hostWithInternetAddress:&addr];
	network = [self convertHost:host];
	
	if (network == nil) [host release];

	return network;
}

- (LUDictionary *)hostsWithService:(char *)name protocol:(char *)protocol
{
	LUDictionary *service = nil;
	char res[MaxDNSReplyPacketSize];
	char *srv;
	int len;

	srv = copyString(name);
	srv = concatString(srv, ".");
	srv = concatString(srv, protocol);
	
	/* resolver client doesn't support multi-threaded access */	
	[threadLock lock];
	len = res_search(srv, C_IN, T_SRV, res, MaxDNSReplyPacketSize);

	if (len <= 0)
	{
		[threadLock unlock];
		freeString(srv);
		return nil;
	}

	service = [self dictForDNSReply:res length:len];
	[threadLock unlock];

	if (service == nil)
	{
		freeString(srv);
		return nil;
	}
	
	[service setValue:name forKey:"name"];
	[service setValue:protocol forKey:"protocol"];
	[service setValue:myDomainName forKey:"_lookup_domain"];
	
	freeString(srv);
	return [self stamp:service];
}

- (void)resolverLock
{
	[threadLock lock];
}

- (void)resolverUnlock
{
	[threadLock unlock];
}

@end

