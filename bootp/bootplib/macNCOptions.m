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
 * macNCOptions.m
 * - handle dhcp/bootp options specific to the macNC
 */
/*
 * Modification History:
 *
 * December 15, 1997	Dieter Siegmund (dieter@apple)
 * - created
 */
#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>
#import <sys/types.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <string.h>
#import "rfc_options.h"
#import "macNCOptions.h"

typedef struct {
    macNCtype_t		type;
    type_info_t			info;
} macNC_type_info_t;

static macNC_type_info_t type_info[] = {
    { macNCtype_pstring_e, 	{ 1, dhcptype_none_e, "PString" } },
    { macNCtype_afp_path_e, 	{ 0, dhcptype_none_e, "AFP path" } },
    { macNCtype_afp_password_e, { 8, dhcptype_none_e, "AFP password" } },
};

static int type_info_size = sizeof(type_info) / sizeof(macNC_type_info_t);

typedef struct {
    macNCtag_t		tag;
    tag_info_t			info;
} macNC_tag_info_t;

static macNC_tag_info_t tag_info[] = {
 { macNCtag_client_version_e, {dhcptype_uint32_e, "macNC_client_version" } },
 { macNCtag_client_info_e, { dhcptype_opaque_e, "macNC_client_info" } },
 { macNCtag_server_version_e, { dhcptype_uint32_e, "macNC_server_version" } },
 { macNCtag_server_info_e, { dhcptype_opaque_e, "macNC_server_info" } },
 { macNCtag_user_name_e, { dhcptype_string_e, "macNC_user_name" } },
 { macNCtag_password_e, { macNCtype_afp_password_e, "macNC_password" } },
 { macNCtag_shared_system_file_e, 
       { macNCtype_afp_path_e, "macNC_shared_system_file" } },
 { macNCtag_private_system_file_e, 
       { macNCtype_afp_path_e, "macNC_private_system_file" } },
 { macNCtag_page_file_e, 
       { macNCtype_afp_path_e, "macNC_page_file" } },
 { macNCtag_MacOS_machine_name_e, 
       { dhcptype_string_e, "macNC_MacOS_machine_name" } },
 { macNCtag_shared_system_shadow_file_e,
       { macNCtype_afp_path_e, "macNC_shared_system_shadow_file" } },
 { macNCtag_private_system_shadow_file_e,
       { macNCtype_afp_path_e, "macNC_private_system_shadow_file" } },
};

static int tag_info_size = sizeof(tag_info) / sizeof(macNC_tag_info_t);

static __inline__ tag_info_t *
get_tag_info(int tag)
{
    int i;

    for (i = 0; i < tag_info_size; i++) {
	if (tag == tag_info[i].tag)
	    return (&tag_info[i].info);
    }
    return (NULL);
}

static __inline__ type_info_t *
get_type_info(int type)
{
    int i;
    for (i = 0; i < type_info_size; i++) {
	if (type == type_info[i].type)
	    return (&type_info[i].info);
    }
    return (NULL);
}

@implementation macNCOptions
+ (tag_info_t *) tagInfo:(int)tag
{
    tag_info_t * t = [super tagInfo:tag];
    if (t)
	return (t);
    return (get_tag_info(tag));
}

+ (type_info_t *) typeInfo:(int)type
{
    type_info_t * t = [super typeInfo:type];

    if (t)
	return (t);
    return (get_type_info(type));
}

+ (boolean_t) str:(unsigned char *)str ToType:(int)type Buffer:(void *)buf
 Length:(int *)len_p ErrorString:(unsigned char *)err
{
    type_info_t * 	type_info = [self typeInfo:type];

    switch (type) {
      case macNCtype_afp_password_e: {
	  int len = strlen(str);
	  if (*len_p < AFP_PASSWORD_LEN) {
	      if (err)
		  sprintf(err, "%s: buffer too small (%d < %d)",
			  type_info->name, *len_p, AFP_PASSWORD_LEN);
	      return (FALSE);
	  }
	  if (len > AFP_PASSWORD_LEN) {
	      if (err)
		  sprintf(err, "%s: string too large (%d > %d)",
			  type_info->name, len, AFP_PASSWORD_LEN);
	      return (FALSE);
	  }
	  *len_p = AFP_PASSWORD_LEN;
	  bzero(buf, AFP_PASSWORD_LEN);
	  strncpy((u_char *)buf, str, len);
        }
	break;
      case macNCtype_pstring_e: {
	  int len = strlen(str);
	  if (*len_p < (len + 1)) {
	      if (err)
		  sprintf(err, "%s: buffer too small (%d < %d)",
			  type_info->name, *len_p, len + 1);
	      return (FALSE);
	  }
	  ((u_char *)buf)[0] = len;			/* string length */
	  bcopy(str, buf + 1, len);
	  *len_p = len + 1;
        }
	break;
      case macNCtype_afp_path_e:
	if (err)
	    sprintf(err, "%s: not supported, use strList instead", 
		    type_info->name);
	return (FALSE);
	break;
      default:
	return [super str:str ToType:type Buffer:buf Length:len_p 
	        ErrorString:err];
	break;
    }
    return (TRUE);
}

static void
S_replace_separators(u_char * buf, int len, u_char sep, u_char new_sep)
{
    int i;

    for (i = 0; i < len; i++) {
	if (buf[i] == sep)
	    buf[i] = new_sep;
    }
    return;
}

+ (boolean_t) encodeAFPPath
    :(struct in_addr)iaddr 
    :(u_short)port 
    :(u_char *)volname 
    :(unsigned long) dirID
    :(u_char) pathtype
    :(u_char *)pathname 
    :(u_char) separator
    Into:(void *)buf 
    Length:(int *)len_p 
    ErrorString:(unsigned char *)err
{
    void * 	buf_p = buf;
    int 	l;

    l = strlen(volname) + strlen(pathname);
    if (l > AFP_PATH_LIMIT) {
	if (err)
	    sprintf(err, "volume/path name length %d > %d-byte limit", l, 
		    AFP_PATH_LIMIT);
	return (FALSE);
    }

    if ((l + AFP_PATH_OVERHEAD) > *len_p) {
	if (err)
	    sprintf(err, "buffer too small: %d > %d", l + AFP_PATH_OVERHEAD, 
		    *len_p);
	return (FALSE);
    }
    *len_p = l + AFP_PATH_OVERHEAD;			/* option len */

    *((struct in_addr *)buf_p) = iaddr;		/* ip */
    buf_p += sizeof(iaddr);

    *((u_short *)buf_p) = port;			/* port */
    buf_p += sizeof(port);

    l = strlen(volname);			/* VolName */
    *((u_char *)buf_p) = l;
    buf_p++;
    if (l)
	bcopy(volname, (u_char *)buf_p, l);
    buf_p += l;

    *((u_long *)buf_p) = dirID;			/* DirID */
    buf_p += sizeof(dirID);

    *((u_char *)buf_p) = pathtype;		/* AFPPathType */
    buf_p += sizeof(pathtype);

    l = strlen(pathname);			/* PathName */
    *((u_char *)buf_p) = l;
    buf_p++;
    if (l) {
	bcopy(pathname, (u_char *)buf_p, l);
	S_replace_separators(buf_p, l, separator, AFP_PATH_SEPARATOR);
    }

    return (TRUE);
}

- (void) printType:(dhcptype_t)type Option:(void *)opt
 Length:(int)option_len
{
    int offset;
    unsigned char * option = opt;

    switch (type) {
      case macNCtype_afp_password_e:
	if (option_len != AFP_PASSWORD_LEN)
	    printf("bad password field\n");
	else {
	    u_char buf[9];
	    strncpy(buf, (u_char *)opt, AFP_PASSWORD_LEN);
	    buf[8] = '\0';
	    printf(buf);
	}
	break;
      case macNCtype_afp_path_e:
	offset = 0;
	printf("(");

	[super printType:dhcptype_ip_e Option:option Length:option_len];
	offset += 4;

	printf(", ");
	[super printType:dhcptype_uint16_e Option:option + offset
	 Length:option_len];
	offset += 2;

	printf(", ");
	[self printType:macNCtype_pstring_e Option:option + offset
	 Length:option_len];
	offset += option[offset] + 1;

	printf(", ");
	[super printType:dhcptype_uint32_e Option:option + offset 
	 Length:option_len];
	offset += 4;

	printf(", ");
	[super printType:dhcptype_uint8_e Option:option + offset
	 Length:option_len];
	offset += 1;

	printf(", ");
	[self printType:macNCtype_pstring_e Option:option + offset
         Length:option_len];

	printf(")");
	break;

      case macNCtype_pstring_e: {
	int i;

	for (i = 0; i < option[0]; i++) {
	    u_char ch = option[1 + i];
	    printf("%c", ch ? ch : '.');
	}
	break;
      }
      default:
	[super printType:type Option:option Length:option_len];
	break;
    }
    return;
}

@end
#ifdef TESTING

/**
 **
 ** Testing 1 2 3
 **
 **/
u_char test[] = 
{
    dhcptag_subnet_mask_e,
    4,
    255, 255, 252, 0,
    
    dhcptag_router_e,
    12,
    17, 202, 40, 1,
    17, 202, 41, 1,
    17, 202, 42, 1, 
    
    dhcptag_domain_name_server_e,
    4,
    17, 128, 100, 12,
    
    dhcptag_host_name_e,
    7,
    's', 'i', 'e', 'g', 'd', 'i', '7',
    
    dhcptag_pad_e,
    
    dhcptag_all_subnets_local_e,
    1,
    0,
    
    dhcptag_vendor_specific_e,
    24,
    't', 'h', 'i', 's', ' ', 'i', 's', ' ', 'a', ' ', 't', 'e', 's', 't',
    234, 212, 0, 1, 2, 3, 4, 5, 6, 7,

    macNCtag_user_name_e,
    10,
    'M', 'a', 'c', 'N', 'C', ' ', '#', ' ', '1', '9',

    macNCtag_shared_system_file_e,
    29,
    17, 202, 40, 191,
    0x20, 0x00,
    4, 'a', 'b', 'c', 'd',
    0, 0, 0, 0,
    2,
    12, 0, 'e', 0, 'f', 0, 'g', 'h', 'i', 0, 'j', 'k', 'l',
    
    dhcptag_end_e,
};

#if 0
u_char test[] = {
0x01, 0x04, 0xff, 0x00, 0x00, 0x00, 0x03, 0x04, 0x0f, 0x03, 0x03, 0x09, 0x06, 
0x04, 0x0f, 0x03, 0x03, 0x09, 0xe8, 0x09, 0x08, 0x6d, 0x61, 0x63, 0x6e, 0x63, 0x30, 0x30, 0x30,
0xed, 0x09, 0x08, 0x6d, 0x61, 0x63, 0x6e, 0x63, 0x30, 0x30, 0x30, 0xe9, 0x09, 0x08, 0x74, 0x65,
0x73, 0x74, 0x69, 0x6e, 0x67, 0x32, 0xea, 0x18, 0x0f, 0x03, 0x03, 0x05, 0x02, 0x24, 0x00, 0x06,
0x64, 0x75, 0x63, 0x61, 0x74, 0x73, 0x09, 0x31, 0x35, 0x2e, 0x33, 0x2e, 0x33, 0x2e, 0x31, 0x37,
0xeb, 0x18, 0x0f, 0x03, 0x03, 0x05, 0x02, 0x24, 0x00, 0x06, 0x64, 0x75, 0x63, 0x61, 0x74, 0x73,
0x09, 0x31, 0x35, 0x2e, 0x33, 0x2e, 0x33, 0x2e, 0x31, 0x37, 0xec, 0x18, 0x0f, 0x03, 0x03, 0x05,
0x02, 0x24, 0x00, 0x06, 0x64, 0x75, 0x63, 0x61, 0x74, 0x73, 0x09, 0x31, 0x35, 0x2e, 0x33, 0x2e,
0x33, 0x2e, 0x31, 0x37, 0xff,
};
#endif

#import "macNCOptions.h"

main()
{
    id			options;

    options = [[macNCOptions alloc] initWithBuffer:test
	       Size:sizeof(test)];
    if (options == nil) {
	printf("macNCOptions failed to initialize\n");
	exit(1);
    }
    if ([options parse] == FALSE) {
	printf("%s\n", [options errString]);
	exit(1);
    }
    [options print];
    {
	struct in_addr	iaddr;
	int i = sizeof(iaddr);
	
	if ([options str:"17.202.42.129" ToType:dhcptype_ip_e 
	     Buffer:(void *)&iaddr Length:&i] == FALSE) {
	    printf("conversion failed %s\n", [options errString]);
	}
	else {
	    printf("ip address should be 17.202.42.129: ");
	    [options printType:dhcptype_ip_e Size:i Option:(void *)&iaddr
	     Length:i];
	    printf("\n");
	}
    }
    {
	unsigned char buf[32] = "Mac NC #33";
	unsigned char buf2[34];
	int len = sizeof(buf2);
	
	if ([options str:buf ToType:macNCtype_pstring_e Buffer:buf2
	     Length:&len] == FALSE) {
	    printf("conversion failed %s\n", [options errString]);
	}
	else {
	    printf("macNCtype string should be %s:", buf);
	    [options printType:macNCtype_pstring_e Size:0 Option:buf2
	     Length:len];
	    printf("\n");
	}
    }
    {
	struct in_addr	iaddr[10];
	int l = sizeof(iaddr);
	u_char * strList[] = { "17.202.40.1", "17.202.41.1", "17.202.42.1",
			     "17.202.43.1" };
	int num = sizeof(strList) / sizeof(*strList);

	if ([options strList:strList Number:num Tag:dhcptag_router_e
	     Buffer:(void *)iaddr Length:&l] == FALSE) {
	    printf("conversion failed %s\n", [options errString]);
	}
	else {
	    [options printType:dhcptype_ip_mult_e Size:4 Option:(void *)iaddr
	     Length:l];
	    printf("\n");
	}
    }
    {
	u_char buf[100];
	u_char * strList[] = { "17.86.91.2", "0x100", "0", "greatVolumeName",
				   "/spectacular/path/name/eh" };
	int l = sizeof(buf);
	int num = sizeof(strList) / sizeof(*strList);

#if 0
	if ([macNCOptions strList:strList Number:num 
	     Tag:macNCtag_system_path_shared_e Buffer:(void *)buf Length:&l
	     ErrorString:[options errString]] == FALSE) {
	    printf("conversion failed %s\n", [options errString]);
	}
	else {
	    printf("conversion OK\n");
	    [options printType:macNCtype_afp_path_e Size:0 Option:(void *)buf
	     Length:l];
	    printf("\n");
	}
#endif
    }
    {
	u_char buf[100];
	int l = sizeof(buf);
	struct in_addr iaddr;

	iaddr.s_addr = inet_addr("17.202.101.100");
	if ([macNCOptions encodeAFPPath
	     : iaddr 
	     : 0x1234
	     : "volumeName"
	     : AFP_DIRID_NULL
	     : AFP_PATHTYPE_LONG
	     : "this:is:the:path" 
	     : ':'
	     Into: (void *)buf 
	     Length: &l 
	     ErrorString: [options errString]] == FALSE) {
	    printf("conversion path failed %s\n", [options errString]);
	}
	else {
	    printf("conversion OK\n");
	    [options printType:macNCtype_afp_path_e Size:0 Option:(void *)buf
	     Length:l];
	    printf("\n");
	}
	
    }
    [options free];
    options = nil;
    { 
	unsigned char buf[300];
	int len = sizeof(buf);
	id o = [[macNCOptions alloc] initWithBuffer:(void *)buf Size:len];

	if (o == nil) {
	    printf("initWithBuffer failed\n");
	}
	else {
	    if ([o addOption:macNCtag_user_name_e FromString:"Mac NC # 22"] 
		== FALSE
		||
		[o addOption:dhcptag_subnet_mask_e FromString:"255.255.255.0"]
		== FALSE
		||
		[o addOption:dhcptag_end_e Length:0 Data:0] == FALSE
		) {
		printf("%s", [o errString]);
	    }
	    else {
		[o parse];
		[o print];
	    }
	}
    }
	
    
    exit(0);
}
#endif TESTING

