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
 * dhcpOptions.m
 * - parse/manipulate dhcp options
 */

/*
 * Modification History:
 *
 * December 15, 1997	Dieter Siegmund (dieter@apple)
 * - created
 */
#import "dhcpOptions.h"

#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>
#import <sys/types.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <strings.h>

#import "rfc_options.h"
#import "gen_dhcp_types.h"
#import "gen_dhcp_parse_table.h"
#import "dhcpOptionsPrivate.h"

#define START_NUM_OPTIONS	32

@implementation dhcpOptions
- init
{
    [super init];

    option_count = 0;
    options_size = START_NUM_OPTIONS;
    options = (unsigned char * *)malloc(sizeof(*options) * options_size);
    if (!options)
	return [self free];
    buffer_size = options_end = 0;
    buffer = NULL;
    good_parse = FALSE;
    end_tag_present = FALSE;
    return self;
}

- free
{
    if (options) {
	*options = 0;
	free(options);
    }
    return [super free];
	
}

- initWithBuffer:(void *)buf Size:(int)size
{
    if ([self init] == nil)
	return [self free];
    return [self setBuffer:buf Size:size];
}

/*
 * Method: setBuffer:Size
 *
 * Purpose:
 *   Associate ourselves with a particular buffer.
 *   Initializes variables in preparation for parse.
 */
- setBuffer:(void *)buf Size:(int)size
{
    option_count = 0;
    buffer = buf;
    buffer_size = size;
    options_end = 0;
    good_parse = FALSE;
    end_tag_present = FALSE;
    return self;
}

- (unsigned char *) errString
{
    return (errString);
}

/*
 * Method: parse
 *
 * Purpose:
 *   Parse the packet to validate the integrity and allow for 
 *   convenient access to the options.
 */
- (boolean_t) parse
{
    int			len;
    unsigned char	option_len;
    unsigned char *	scan;
    unsigned char	tag = dhcptag_pad_e;

    if (!buffer) {
	sprintf(errString, "no buffer set");
	return (FALSE);
    }
    len = buffer_size;
    if (good_parse)
	[self setBuffer:buffer Size:buffer_size];
    good_parse = FALSE;
    for (scan = buffer; len > 0; ) {
	tag = scan[TAG_OFFSET];
	if (tag == dhcptag_end_e) /* we hit the end of the options */
	    break;
	if (tag == dhcptag_pad_e) { /* discard pad characters */
	    scan++;
	    len--;
	}
	else {
	    option_len = scan[LEN_OFFSET];
	    if (option_count == options_size) { /* grow the array */
		options_size *= 2;
		options = (unsigned char * *)
		    realloc(options, sizeof(*options) * options_size);
	    }
	    options[option_count++] = scan;
	    len -= (option_len + 2);
	    scan += (option_len + 2);
	}
    }
    if (len < 0 || tag != dhcptag_end_e) { /* we ran off the end */
	if (len < 0)
	    sprintf(errString, "parse error encountered near tag %d", tag);
	else
	    sprintf(errString, "end tag missing");

	return (FALSE);
    }
    options = (unsigned char * *) /* make it the "right" size */
	realloc(options, sizeof(*options) * option_count);
    options_end = scan - (u_char *)buffer + 1; /* one past the end tag */
    good_parse = TRUE;
    end_tag_present = TRUE;
    return (TRUE);
}

/*
 * Method: findOptionWithTag:Length
 *
 * Purpose:
 *   Find the tag with the given code, returning the length and the
 *   pointer to the option start.
 */
- (void *)findOptionWithTag:(int)tag Length:(int *)len_p
{
    int i;

    if (good_parse == FALSE)
	return (NULL);

    for (i = 0; i < option_count; i++) {
	unsigned char * option = options[i];

	if (option[TAG_OFFSET] == tag) {
	    if (len_p)
		*len_p = option[LEN_OFFSET];
	    return (option + OPTION_OFFSET);
	}
    }
    return (NULL);
}

/*
 * Method: dhcpMessage:
 *
 * Purpose:
 *   Append a dhcp message option to the option area.
 */
- (boolean_t) dhcpMessage:(dhcp_msgtype_t)m
{
    u_char msgtype = m;
    return ([self addOption:dhcptag_dhcp_message_type_e 
	     Length:1 Data:&msgtype]);
}

/*
 * Method: addOption:Length:Data
 *
 * Purpose:
 *   Append an option to the options area.
 */
- (boolean_t) addOption:(int)tag Length:(int)len Data:(void *)data
{
    if (end_tag_present) {
	strcpy(errString, "end tag present, can't add more options");
	return (FALSE);
    }

    if (len > DHCP_OPTION_MAX) {
	sprintf(errString, "option too long: %d > %d", len,
		DHCP_OPTION_MAX);
	return (FALSE);
    }

    switch (tag) {
      case dhcptag_end_e:
	if ((options_end + 1) >= buffer_size) {
	    strcpy(errString, "no room for end tag");
	    return (FALSE);
	}
	((u_char *)buffer)[options_end + TAG_OFFSET] = tag;
	options_end++;
	end_tag_present = TRUE;
	break;
      case dhcptag_pad_e:
	/* 1 for pad tag, 1 for end tag which must be present */
	if ((options_end + 1 + 1) >= buffer_size) {
	    strcpy(errString, "no room for pad");
	}
	((u_char *)buffer)[options_end + TAG_OFFSET] = tag;
	options_end++;
	break;

      default:
	/* 2 for tag/len, 1 for end tag which must be present */
	if ((options_end + len + 2 + 1) >= buffer_size) {
	    sprintf(errString, "no room for tag, %d >= %d", 
		    options_end + len + 2 + 1, buffer_size);
	    return (FALSE);
	}
	((u_char *)buffer)[options_end + TAG_OFFSET] = tag;
	((u_char *)buffer)[options_end + LEN_OFFSET] = len;
	if (len)
	    bcopy(data, (u_char *)buffer + (OPTION_OFFSET + options_end), len);
	options_end += len + OPTION_OFFSET;
	break;
    }
    return (TRUE);
}

/*
 * Method: addOption:FromString:
 *
 * Purpose:
 *   Parse (if necessary) the string into a dhcp option with the specified tag.
 *   This allows convenient conversion from string representation to packet
 *   representation.
 */
- (boolean_t) addOption:(int)tag FromString:(unsigned char *)str
{
    int 		len;
    tag_info_t * 	tag_info = [self tagInfo:tag];
    type_info_t *	type_info;


    if (end_tag_present) {
	strcpy(errString, "end tag present, can't add more options");
	return (FALSE);
    }
    if (tag_info == NULL) {
	sprintf(errString, "can't determine type for conversion, tag %d",
		tag);
	return (FALSE);
    }
    type_info = [self typeInfo:tag_info->type];
    if (tag_info->type == dhcptype_none_e) {
	sprintf(errString, "%s: not supported", type_info->name);
	return (FALSE);
    }

    len = [self freeSpace];
    if (len < OPTION_OFFSET) {
	sprintf(errString, "no space left for option %s", tag_info->name);
	return (FALSE);
    }
    len -= OPTION_OFFSET; /* leave room for the <tag,len> bytes */
    if ([self str:str ToType:tag_info->type Buffer:
	 (((u_char *)buffer) + options_end + OPTION_OFFSET)
         Length:&len] == FALSE)
	return (FALSE);
    if (len > DHCP_OPTION_MAX) {
	sprintf(errString, "option too long: %d > %d", len, DHCP_OPTION_MAX);
	return (FALSE);
    }
    ((u_char *)buffer)[options_end + TAG_OFFSET] = tag;
    ((u_char *)buffer)[options_end + LEN_OFFSET] = len;
    options_end += len + OPTION_OFFSET;
    return (TRUE);
    
}

- (int) bufferUsed
{
    return (options_end);
}

- (int) freeSpace
{
    return (buffer_size - options_end);
}

@end

/**
 ** Private methods
 **/
@implementation dhcpOptions(Private)
+ (tag_info_t *) tagInfo:(int)tag
{
#define LAST_TAG 127
    if (tag > LAST_TAG || dhcptag_info[tag].name == NULL)
	return (NULL);
    return dhcptag_info + tag;
}

+ (type_info_t *) typeInfo:(int)type
{
    if (type > dhcptype_last_e)
	return (NULL);
    return dhcptype_info + type;
}

- (tag_info_t *) tagInfo:(int)tag
{
    return [[self class] tagInfo:tag];
}

- (type_info_t *) typeInfo:(int)type
{
    return [[self class] typeInfo:type];
}

/*
 * Method: str:ToType:Buffer:Length:ErrorString
 *
 * Purpose:
 *   Convert from a string to the appropriate internal representation
 *   for the given type.  Calls the appropriate strto<type> function.
 */
+ (boolean_t) str:(unsigned char *)str ToType:(int)type Buffer:(void *)buf
 Length:(int *)len_p ErrorString:(unsigned char *)err
{
    type_info_t * 	type_info = [self typeInfo:type];

    if (*len_p < type_info->size) {
	if (err)
	    sprintf(err, "%s: buffer size too small (%d < %d)",
		    type_info->name, *len_p, type_info->size);
	return (FALSE);
    }

    switch (type) {
      case dhcptype_bool_e: {
	  long l = strtol(str, 0, 0);
	  *len_p = type_info->size;
	  *((unsigned char *)buf) = ((l == 0) ? 0 : 1);
	  break;
      }
      case dhcptype_uint8_e: {
	  unsigned long ul = strtoul(str, 0, 0);
	  *len_p = type_info->size;
	  if (ul > 255) {
	      if (err)
		  sprintf(err, "%s: value %lu too large", type_info->name, ul);
	      return (FALSE);
	  }
	  *((unsigned char *)buf) = ul;
	  break;
      }
      case dhcptype_uint16_e: {
	  unsigned long ul = strtoul(str, 0, 0);
	  unsigned short us = ul;

	  if (ul > 65535) {
	      if (err)
		  sprintf(err, "%s: value %lu too large", type_info->name, ul);
	      return (FALSE);
	  }
	  *((unsigned short *)buf) = htons(us);
	  *len_p = type_info->size;
	  break;
      }
      case dhcptype_int32_e: {
	  long l = strtol(str, 0, 0);
	  *((long *)buf) = htonl(l);
	  *len_p = type_info->size;
	  break;
      }
      case dhcptype_uint32_e: {
	  unsigned long ul = strtoul(str, 0, 0);
	  *((unsigned long *)buf) = htonl(ul);
	  *len_p = type_info->size;
	  break;
      }
      case dhcptype_ip_e: {
	  long l;
	  l = inet_addr(str);
	  if (l == -1) {
	      if (err)
		  sprintf(err, "%s: invalid address", type_info->name);
	      return (FALSE);
	  }
	  *((unsigned long *)buf) = l;
	  *len_p = type_info->size;
	  break;
      }
      case dhcptype_string_e: {
	  int len = strlen(str);
	  if (*len_p < len) {
	      if (err)
		  sprintf(err, "%s: buffer size less than strlen (%d < %d)",
			  type_info->name, *len_p, len);
	      return (FALSE);
	  }
	  if (len)
	      bcopy(str, buf, len);
	  *len_p = len;
	  break;
      }
      default:
	if (err)
	    sprintf(err, "%s: not supported", type_info->name);
	return (FALSE);
	break;
    }
    return (TRUE);
}
- (boolean_t) str:(unsigned char *)str ToType:(int)type Buffer:(void *)buf
 Length:(int *)len_p
{
    return [[self class] str:str ToType:type Buffer:buf Length:len_p
	    ErrorString:[self errString]];
}


/*
 * Method: strFromOption:Length:Type:ErrorString:
 *
 * Purpose:
 *   Give a string representation to the given type.
 */
+ (boolean_t) str:(u_char *)tmp FromOption:(void *)opt Length:(int)len 
 Type:(int)type ErrorString:(u_char *)err
{
    switch (type) {
      case dhcptype_bool_e:
	sprintf(tmp, "%d", *((boolean_t *)opt));
	break;
      case dhcptype_uint8_e:
	sprintf(tmp, "%d", *((u_char *)opt));
	break;
      case dhcptype_uint16_e:
	sprintf(tmp, "%d", *((u_int16_t *)opt));
	break;
      case dhcptype_int32_e:
	sprintf(tmp, "%d", *((int32_t *)opt));
	break;
      case dhcptype_uint32_e:
	sprintf(tmp, "%u", *((u_int32_t *)opt));
	break;
      case dhcptype_ip_e:
	strcpy(tmp, inet_ntoa(*((struct in_addr *)opt)));
	break;
      case dhcptype_string_e:
	strncpy(tmp, opt, len);
	tmp[len] = '\0';
	break;
      default: {
	  type_info_t * type_info = [self typeInfo:type];
	  if (err)
	      sprintf(err, "%s: not supported", type_info->name);
	  return (FALSE);
	  break;
      }
    }
    return (TRUE);
}

/*
 * Method: strList:Number:Tag:Buffer:Length:ErrorString
 *
 * Purpose:
 *   Convert from a string list to the given type using the appropriate
 *   type conversion for the base type.  The type table stores enough
 *   information to convert types that are simply multiples of some
 *   base type ie. a list of ip addresses, or a list of u_short's.
 */
+ (boolean_t) strList:(unsigned char * *)slist Number:(int)num
 Tag:(int)tag Buffer:(void *)buf Length:(int *)len_p 
 ErrorString:(unsigned char *)err
{
    int			i;
    int			n_per_type;
    tag_info_t *	tag_info = [self tagInfo:tag];
    type_info_t * 	type_info = [self typeInfo:tag_info->type];
    type_info_t * 	base_type_info;

    if (type_info->multiple_of == dhcptype_none_e)
	return ([self str:slist[0] ToType:tag_info->type 
	         Buffer:buf Length:len_p ErrorString:err]);

    base_type_info = [self typeInfo:type_info->multiple_of];
    n_per_type = type_info->size / base_type_info->size;
    if (num & (n_per_type - 1)) {
	if (err)
	    sprintf(err, "%s: must be a multiple of %d", type_info->name,
		    n_per_type);
	return (FALSE);
    }
    if ((num * base_type_info->size) > *len_p) /* truncate if necessary */
	num = *len_p / base_type_info->size;
    for (i = 0, *len_p = 0; i < num; i++) {
	int l;

	l = base_type_info->size;
	if ([self str:slist[i] ToType:type_info->multiple_of
	     Buffer:buf Length:&l ErrorString:err] == FALSE)
	    return (FALSE);
	buf += l;
	*len_p += l;
    }
    return (TRUE);
}

- (boolean_t) strList:(unsigned char * *)slist Number:(int)num
 Tag:(int)tag Buffer:(void *)buf Length:(int *)len_p
{
    return ([[self class] strList:slist Number:num Tag:tag Buffer:buf 
	      Length:len_p ErrorString:[self errString]]);
}


- (void) printType:(dhcptype_t)type Option:(void *)opt Length:(int)option_len
{
    u_char *		option = opt;
    type_info_t * 	type_info = [self typeInfo:type];

    if (type_info && type_info->multiple_of != dhcptype_none_e) {
	int 		i;
	int 		number;
	u_char *	offset;
	type_info_t * 	subtype_info = [self typeInfo:type_info->multiple_of];
	int 		size = subtype_info->size;

	number = option_len / size;
	printf("{");
	for (i = 0, offset = option; i < number; i++) {
	    if (i != 0)
		printf(", ");
	    [self printType:type_info->multiple_of Option:offset Length:size];
	    offset += size;
	}
	printf("}");
    }
    else switch (type) {
      case dhcptype_bool_e:
	printf("%s", *option ? "TRUE" : "FALSE");
	break;
	
      case dhcptype_ip_e:
	printf("%s", inet_ntoa(*((struct in_addr *)option)));
	break;
	
      case dhcptype_string_e: {
	  char 		buf[256];
	  strncpy(buf, option, option_len);
	  buf[option_len] = '\0';
	  printf("%s", buf);
	  break;
      }
	
      case dhcptype_opaque_e:
	printf("\n");
	[[self class] printData:option Length:option_len];
	break;

      case dhcptype_uint8_e:
	printf("0x%x", *option);
	break;

      case dhcptype_uint16_e:
	printf("0x%x", ntohs(*((unsigned short *)option)));
	break;

      case dhcptype_uint32_e:
	printf("0x%lx", ntohl(*((unsigned long *)option)));
	break;

      case dhcptype_none_e:
      default:
	break;
    }
    return;
}

- (boolean_t) printOption:(void *)vopt
{
    u_char *    opt = vopt;
    u_char 	tag = opt[TAG_OFFSET];
    u_char 	option_len = opt[LEN_OFFSET];
    u_char * 	option = opt + OPTION_OFFSET;
    tag_info_t * entry;

    entry = [self tagInfo:tag];
    if (entry == NULL)
	return (FALSE);
    {	
	type_info_t * type = [self typeInfo:entry->type];
	
	if (type == NULL) {
	    printf("unknown type %d\n", entry->type);
	    return (FALSE);
	}
	printf("%s (%s): ", entry->name, type->name);
	[self printType:entry->type Option:option Length:option_len];
	printf("\n");
    }
    return (TRUE);
}

- (void) print
{
    int 		i;

    printf("Options count is %d\n", option_count);
    for (i = 0; i < option_count; i++) {
	unsigned char * option = options[i];
	if ([self printOption:option] == FALSE)
	    printf("undefined tag %d len %d\n", option[TAG_OFFSET], 
		   option[LEN_OFFSET]);
    }
}

#import <ctype.h>

+ (void) printData:(void *) d_p Length:(int)n_bytes
{
#define CHARS_PER_LINE 	16
    unsigned char *	data_p = (unsigned char *)d_p;
    char		line_buf[CHARS_PER_LINE + 1];
    int			line_pos;
    int			offset;

    for (line_pos = 0, offset = 0; offset < n_bytes; offset++, data_p++) {
	if (line_pos == 0)
	    printf("%04d  ", offset);

	line_buf[line_pos] = isprint(*data_p) ? *data_p : '.';
	printf("%s %02x", (line_pos == 8) ? "  " : "", *data_p);
	line_pos++;
	if (line_pos == CHARS_PER_LINE) {
	    line_buf[CHARS_PER_LINE] = '\0';
	    printf("    %s\n", line_buf);
	    line_pos = 0;
	}
    }
    if (line_pos) { /* need to finish up the line */
	line_buf[line_pos] = '\0';
	for (; line_pos < CHARS_PER_LINE; line_pos++) {
	    printf("   "); /* 3 chars: space + %02x */
	}
	printf("      %s\n", line_buf);
    }
}

@end
