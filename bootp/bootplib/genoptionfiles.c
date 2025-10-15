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
 * genoptionfiles.c
 * - generates dhcp-related header files
 * - its purpose is to avoid the inevitable errors that arise when trying 
 *   to keep separate but related tables in synch by hand
 */

/*
 * Modification History
 * 12 Dec 1997	Dieter Siegmund (dieter@apple)
 *		- created
 */

#import <mach/boolean.h>

#define COMMENT		0xffff
#define END		0xfffe

#define LAST_TAG	127

struct {
    unsigned char *		name;
    unsigned int		size;
    unsigned char *		multiple_of;

} types[] = {
    { "none",		0,	0 },
    { "opaque",		0,	0 },
    { "bool",		1,	0 },
    { "uint8",		1,	0 },
    { "uint16",		2,	0 },
    { "uint32",		4,	0 },
    { "int32",		4,	0 },
    { "uint8_mult",	1,	"uint8" },
    { "uint16_mult",	2,	"uint16" },
    { "string",		0,	0 },
    { "ip",		4,	0 },
    { "ip_mult",	4,	"ip" },
    { "ip_pairs",	8,	"ip" },
    { 0, 0, 0 },
};

struct {
    int 			code;
    unsigned char *		type;
    unsigned char *		name;
} option[] = {
    { COMMENT, "/* rfc 1497 vendor extensions: 0..18, 255 */", 0 },
    /* value	name 		type */
    { 0,	"none",		"pad" },
    { 255,	"none",		"end" },
    { 1,	"ip",		"subnet_mask" },
    { 2,	"int32",	"time_offset" },
    { 3,	"ip_mult",	"router" },
    { 4,	"ip_mult",	"time_server" },
    { 5,	"ip_mult",	"name_server" },
    { 6,	"ip_mult",	"domain_name_server" },
    { 7,	"ip_mult",	"log_server" },
    { 8,	"ip_mult",	"cookie_server" },
    { 9,	"ip_mult",	"lpr_server" },
    { 10,	"ip_mult",	"impress_server" },
    { 11,	"ip_mult",	"resource_location_server" },
    { 12,	"string",	"host_name" },
    { 13,	"uint16",	"boot_file_size" },
    { 14,	"string",	"merit_dump_file" },
    { 15,	"string",	"domain_name" },
    { 16,	"ip",		"swap_server" },
    { 17,	"string",	"root_path" },
    { 18,	"string",	"extensions_path" },
    { COMMENT,  "/* ip layer parameters per host: 19..25 */", 0 },
    { 19,	"bool",		"ip_forwarding" },
    { 20,	"bool",		"non_local_source_routing" },
    { 21,	"ip_pairs",	"policy_filter" },
    { 22,	"uint16",	"max_dgram_reassembly_size" },
    { 23,	"uint8",	"default_ip_time_to_live" },
    { 24,	"uint32",	"path_mtu_aging_timeout" },
    { 25,	"uint16_mult",	"path_mtu_plateau_table" },
    { COMMENT, "/* ip layer parameters per interface: 26..33 */", 0 },
    { 26,	"uint16",	"interface_mtu" },
    { 27,	"bool",		"all_subnets_local" },
    { 28,	"ip",		"broadcast_address" },
    { 29,	"bool",		"perform_mask_discovery" },
    { 30,	"bool",		"mask_supplier" },
    { 31,	"bool",		"perform_router_discovery" },
    { 32,	"ip",		"router_solicitation_address" },
    { 33,	"ip_pairs",	"static_route" },
    { 34,	"bool",		"trailer_encapsulation" },
    { 35,	"uint32",	"arp_cache_timeout" },
    { 36,	"bool",		"ethernet_encapsulation" },
    { COMMENT, "/* tcp parameters: 37..39 */", 0 },
    { 37,	"uint8",	"default_ttl" },
    { 38,	"uint32",	"keepalive_interval" },
    { 39,	"bool",		"keepalive_garbage" },
    { COMMENT, "/* application & service parameters: 40..49, 64, 65, 68..76 */", 0},
    { 40,	"string",	"nis_domain" },
    { 41,	"ip_mult",	"nis_servers" },
    { 42,	"ip_mult",	"network_time_protocol_servers" },
    { 43,	"opaque",	"vendor_specific" },
    { 44,	"ip_mult",	"nb_over_tcpip_name_server" },
    { 45,	"ip_mult",	"nb_over_tcpip_dgram_dist_server" },
    { 46,	"uint8",	"nb_over_tcpip_node_type" },
    { 47,	"string",	"nb_over_tcpip_scope" },
    { 48,	"ip_mult",	"x_windows_font_server" },
    { 49,	"ip_mult",	"x_windows_display_manager" },
    { 64,	"string",	"nis_plus_domain" },
    { 65,	"ip_mult",	"nis_plus_servers" },
    { 68,	"ip_mult",	"mobile_ip_home_agent" },
    { 69,	"ip_mult",	"smtp_server" },
    { 70,	"ip_mult",	"pop3_server" },
    { 71,	"ip_mult",	"nntp_server" },
    { 72,	"ip_mult",	"default_www_server" },
    { 73,	"ip_mult",	"default_finger_server" },
    { 74,	"ip_mult",	"default_irc_server" },
    { 75,	"ip_mult",	"streettalk_server" },
    { 76,	"ip_mult",	"stda_server" },
    { COMMENT, "/* dhcp-specific extensions: 50..61, 66, 67  */", 0 },
    { 50,	"ip",		"requested_ip_address" },
    { 51,	"uint32",	"ip_address_lease_time" },
    { 52,	"uint8",	"option_overload" },
    { 53,	"uint8",	"dhcp_message_type" },
    { 54,	"ip",		"server_identifier" },
    { 55,	"uint8_mult",	"parameter_request_list" },
    { 56,	"string",	"message" },
    { 57,	"uint16",	"max_dhcp_message_size" },
    { 58,	"uint32",	"renewal_t1_time_value" },
    { 59,	"uint32",	"rebinding_t2_time_value" },
    { 60,	"string",	"vendor_class_identifier" },
    { 61,	"uint8_mult",	"client_identifier" },
    { 66,	"ip_mult",	"tftp_server_name" },
    { 67,	"ip_mult",	"bootfile_name" },
    { COMMENT, "/* undefined: 62, 63, 77..111 */", 0 },
    { COMMENT, "/* netinfo parent tags: 112, 113 */", 0 },
    { 112, 	"ip", 		"netinfo_server_address" },
    { 113, 	"string",	"netinfo_server_tag" }, 
    { COMMENT, "/* undefined: 114-127 */", 0 },
    { COMMENT, "/* site-specific: 128..254 */", 0 },
    { 128,	"opaque",	"site_specific_start" },
    { 254,	"opaque",	"site_specific_end" },
    { END, 0, 0 },
};

int
find_option(int code)
{
    int i;
    for (i = 0; option[i].code != END; i++) {
	if (option[i].code == code)
	    return (i);
    }
    return (-1);
}

unsigned char *
make_option(unsigned char * name)
{
    static unsigned char buf[80];

    sprintf(buf, "dhcptag_%s_e", name);
    return (buf);
}

unsigned char *
make_type(unsigned char * name)
{
    static unsigned char buf[80];
    sprintf(buf, "dhcptype_%s_e", name);
    return (buf);
}

static void
S_upper_case(unsigned char * name)
{
    while (*name) {
	*name = toupper(*name);
	name++;
    }
}

unsigned char *
make_option_define(unsigned char * name)
{
    static unsigned char buf[80];
    sprintf(buf, "DHCPTAG_%s", name);
    S_upper_case(buf);
    return (buf);
}


main(int argc, char * argv[])
{
    int dhcptag = 0;
    int dhcptype = 0;
    int table = 0;
    int i;

    if (argc != 2)
	exit(0);

    if (strcmp(argv[1], "-table") == 0)
	table = 1;
    else if (strcmp(argv[1], "-dhcptag") == 0)
	dhcptag = 1;
    else if (strcmp(argv[1], "-dhcptype") == 0)
	dhcptype = 1;
    else
	exit(1);

    printf("/*\n"
	   " * This file was auto-generated by %s %s, do not edit!\n"
	   " */\n", argv[0], argv[1]);
    if (dhcptag) {
	printf("typedef enum {\n");
	for (i = 0; option[i].code != END; i++) {
	    if (option[i].code == COMMENT)
		printf("\n    %s\n", option[i].type);
	    else {
		printf("    %-35s\t= %d,\n", make_option(option[i].name), 
		       option[i].code);
	    }
	}
	printf("} dhcptag_t;\n\n");
    
	for (i = 0; option[i].code != END; i++) {
	    if (option[i].code != COMMENT) {
		printf("#define %-35s\t\"%s\"\n", 
		       make_option_define(option[i].name),
		       option[i].name);
	    }
	}
    
	exit (0);
    }

    if (dhcptype) {
	printf("\ntypedef enum {\n");
	for (i = 0; types[i].name; i++) {
	    if (i == 0) {
		printf("    %-20s\t = %d,\n", make_type("first"), i);
		printf("    %-20s\t =", make_type(types[i].name));
		printf(" %s,\n", make_type("first"));
	    }
	    else
		printf("    %-20s\t = %d,\n", make_type(types[i].name), i);
	}
	printf("    %-20s\t =", make_type("last"));
	printf(" %s,\n", make_type(types[i ? (i - 1) : 0].name));
    
	printf("} dhcptype_t;\n\n");
	printf("typedef struct {\n"
	       "    dhcptype_t	type;\n"
	       "    unsigned char *	name;\n"
	       "} tag_info_t;\n\n");
	printf("typedef struct {\n"
	       "    int		size;  /* in bytes */\n"
	       "    int		multiple_of; /* type of element */\n"
	       "    unsigned char * name;\n"
	       "} type_info_t;\n\n");
	exit (0);

    }
    printf("static tag_info_t dhcptag_info[] = {\n");
    for (i = 0; i <= LAST_TAG; i++) {
	int opt;
	int type;

	opt = find_option(i);
	if (opt < 0) {
	    printf("  /* %3d */ { %-20s, 0 },\n", i, make_type("opaque"));
	}
	else
	    printf("  /* %3d */ { %-20s, \"%s\" },\n", i,
		   make_type(option[opt].type), option[opt].name);
    }
    printf("};\n\n");

    printf("static type_info_t dhcptype_info[] = {\n");
    for (i = 0; types[i].name; i++) {
	char * type = types[i].multiple_of;

	printf("  /* %2d */ { %d, %s, \"%s\"},\n", i, types[i].size, 
	       make_type((type != 0) ? type : "none"), types[i].name);
    }
    printf("};\n");
    exit (0);
}
