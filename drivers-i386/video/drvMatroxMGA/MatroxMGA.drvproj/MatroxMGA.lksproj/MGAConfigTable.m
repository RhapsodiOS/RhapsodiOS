/*
 * Copyright © 1998-2007 Mirko Viviani. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. The name of the author may not be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Created by Mirko Viviani: 16 Dec 1998
*/

#import <string.h>
#import "MGA.h"

/* The `ConfigTable' category of `MGA'. */

@implementation MatroxMGA (ConfigTable)

- (const char *)valueForStringKey:(const char *)key
{
	IOConfigTable *configTable;

	configTable = [[self deviceDescription] configTable];
	if (configTable == nil)
		return 0;
	
	return [configTable valueForStringKey:key];
}

static inline int 
isWhiteSpace(int c)
{
	return (c == ' ' || c == '\t' || c == '\n' || c == '\r');
}

static int
readHexValue(const char **s)
{
	int c, value;
	const char *string;

	string = *s;
	while ((c = *string) != '\0' && isWhiteSpace(c))
		string++;

	if (c == '\0') {
		*s = string;
		return -1;
	}
	value = 0;

	while ((c = *string) != '\0' && !isWhiteSpace(c)) {
		if (c >= '0' && c <= '9')
			value = (value << 4) | (c - '0');
		else if (c >= 'A' && c <= 'F')
			value = (value << 4) | (c - 'A' + 10);
		else if (c >= 'a' && c <= 'f')
			value = (value << 4) | (c - 'a' + 10);
		else
			break;
		string++;
	}

	*s = string;

	return (value & 0xFF);
}

static int _atoi(const char *ip)
{
	unsigned rtn = 0;
	int c;
	
	while ((c = *ip) != '\0' && isWhiteSpace(c))
		ip++;

	while(*ip) {
		if((*ip < '0') || (*ip > '9')) {
			return rtn;	
		}
		rtn *= 10;
		rtn += (*ip - '0');
		ip++;
	}

	return rtn;
}

- (int)parametersForMode:(const char *)modeName
	forStringKey:(const char *)key
	parameters:(char *)parameters
	count:(int)count
{
	int k, value;
	const char *s;
	char modeKey[strlen(modeName) + 1 + strlen(key) + 1];

	strcpy(modeKey, modeName);
	strcat(modeKey, " ");
	strcat(modeKey, key);
	s = [self valueForStringKey:modeKey];
	if (s == 0)
		return -1;

	k = 0;
	for (k = 0; k < count; k++) {
		value = readHexValue(&s);
		if (value == -1)
			break;

		parameters[k] = value;
	}

	return k;
}

- (BOOL)booleanForStringKey:(const char *)key withDefault:(BOOL)defaultValue
{
	const char *value;

	value = [self valueForStringKey:key];

	if(value) {
		if (value[0] == 'Y' || value[0] == 'y') {

			if (value[1] == '\0'
			|| ((value[1] == 'E' || value[1] == 'e')
			&& (value[2] == 'S' || value[2] == 's')
			&& value[3] == '\0')) {
				return YES;
			}
		}
		else if (value[0] == 'N' || value[0] == 'n') {

			if (value[1] == '\0'
			|| ((value[1] == 'O' || value[1] == 'o')
			&& value[2] == '\0'))
			{
				return NO;
			}
		}
	}

//	IOLog("%s: Unrecognized value for key `%s': `%s'.\n",
//		[self name], key, value);

	return defaultValue;
}

- (unsigned int)integerForStringKey:(const char *)key
                        withDefault:(unsigned)defaultValue
{
	const char *value;

	value = [self valueForStringKey:key];

	if(value) {
		return _atoi(value);
	}

	return defaultValue;
}

@end
