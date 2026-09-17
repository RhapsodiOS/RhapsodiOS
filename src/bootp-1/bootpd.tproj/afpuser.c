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
 * afpuser.c
 * - routines to manipulate AFP machine "users" using the OAM API
 *
 * Modification History:
 *
 * December 2, 1997	Dieter Siegmund (dieter@apple)
 * - created
 */

#import <unistd.h>
#import <stdlib.h>
#import <string.h>
#import "afpuser.h"

/**
 ** Local routines
 **/

/*
 * Functions: convertStrToPascalStr, convertPascalStrToStr
 * Purpose:
 *   Convert between C-string and Pascal string.
 *   A C-string is a NULL-terminated character array.
 *   A Pascal string is a character array whose first element indicates
 *   the size of the string.  It may or may not contain a NULL at the end.
 */
static __inline__ StringPtr
convertStrToPascalStr(unsigned char * str, StringPtr p_str)
{
    *p_str = strlen(str);
    strncpy(p_str + 1, str, *p_str);
    return(p_str);
}
static __inline__ unsigned char *
convertPascalStrToStr(StringPtr p_str, unsigned char * str)
{
    strncpy(str, p_str + 1, *p_str);
    str[*p_str] = '\0';
    return(str);
}

/*
 * Functions: BuildObjectSpecByNameType, BuildObjectSpecByShortID
 * Purpose:
 *   Convenience routines to fill in the elements of the object spec
 *   struct.
 */
static __inline__ void 
BuildObjectSpecByNameType(OAMObjectSpec * spec, StringPtr name, 
			  OAMType type)
{
    memset(spec, 0, sizeof(*spec));
    spec->specType = kOAMObjectSpecByNameType;
    spec->objectType = type;
    memcpy(&spec->u.name, name, *name + 1);
    return;
}
static __inline__ void
BuildObjectSpecByShortID(OAMObjectSpec * spec, OAMShortObjectSpec id)
{
    memset(spec, 0, sizeof(*spec));
    spec->specType = kOAMObjectSpecByShortID;
    spec->u.shortID = id;
}

/**
 ** External Routines
 **/

/*
 * Function: openOAMSession
 *
 * Purpose:
 *   Open an OAM session, returning the session id.
 *
 * Returns:
 *   noErr if session opened, returns appropriate OAMStatus otherwise
 */
OAMStatus
openOAMSession(OAMSessionID * session_p)
{
    static int		initdone = 0;
    OAMStatus 		status;

    if (initdone == 0) { /* one-time initialization */
	status = OAMInitialize(1, 1, NULL, NULL);
	if (status != noErr)
	    return (status);
	initdone = 1;
    }
    status = OAMOpenSession(NULL, session_p, NULL);
    if (status != noErr)
	return (status);
    return (noErr);
}

/*
 * Function: closeOAMSession
 *
 * Purpose:
 *   Closes the given session.
 *
 * Returns:
 *   noErr if session closed, returns appropriate OAMStatus otherwise
 */
OAMStatus
closeOAMSession(OAMSessionID sessionID)
{
    return (OAMCloseSession(sessionID, NULL));
}

/*
 * Function: createOAMUser
 *
 * Purpose:
 *   Creates a new OAM User with the given name, internet name, and password.
 *
 * Returns:
 *   noErr if user created, returns appropriate OAMStatus otherwise
 */
OAMStatus 
createOAMUser(OAMSessionID session, u_char * name, u_char * inet_p,
	      u_char * passwd_p)
{
    OAMObjectSpec		user;
    OAMAttributeDescriptor	attr[4];
    Str31			inet_name;
    Str31			pname;
    char 			password[AFP_PASSWORD_LEN];
    short			userFlags;

    /* zero all fields */
    memset(pname, 0, sizeof(pname));
    memset(inet_name, 0, sizeof(inet_name));
    memset(&attr[0], 0, sizeof(attr));
    memset(password, 0, sizeof(password));

    /* make sure password is <= 8 chars long, zero-padded */
    strncpy(password, passwd_p, sizeof(password));

    /* convert C-strings to Pascal strings */
    convertStrToPascalStr(name, pname);
    convertStrToPascalStr(inet_p, inet_name);
    
    /* password */
    attr[0].attributeSignature = kUser;
    attr[0].attributeType = kPasswordAttribute; /* password */
    attr[0].bufferDescriptor.buffer = password;
    attr[0].bufferDescriptor.bufferLen = 8;
    attr[0].bufferDescriptor.actCount = 0;

    /* internet alias */
    attr[1].attributeSignature = kUser;
    attr[1].attributeType = kInternetName;
    attr[1].bufferDescriptor.buffer = inet_name;
    attr[1].bufferDescriptor.bufferLen = sizeof(inet_name);
    attr[1].bufferDescriptor.actCount = 0;

    /* AFP user flags */
    /* allow logins but no password changing */
    userFlags = bmLoginEnabled | bmDisableChangePwd;
    attr[2].attributeSignature = kBasic;
    attr[2].attributeType = kUserFlags;
    attr[2].bufferDescriptor.buffer = &userFlags;
    attr[2].bufferDescriptor.bufferLen = sizeof(short);

    /* NULL terminate the list */
    attr[3].attributeSignature = 0;

    /* create the object */
    BuildObjectSpecByNameType(&user, pname, kUser);
    return(OAMCreateObject(session, &user, &attr[0], NULL));
}

/*
 * Function: deleteOAMUser
 *
 * Purpose:
 *   Deletes an OAM User with the given name.
 *
 * Returns:
 *   noErr if user deleted, returns appropriate OAMStatus otherwise
 */
OAMStatus
deleteOAMUser(OAMSessionID session, u_char * name)
{
    OAMObjectSpec		user;
    Str31			pname;

    /* zero all fields */
    memset(pname, 0, sizeof(pname));

    /* convert C-strings to Pascal strings */
    convertStrToPascalStr(name, pname);
    
    /* delete the object */
    BuildObjectSpecByNameType(&user, pname, kUser);
    return(OAMDeleteObject(session, &user, NULL));
}

/*
 * Function: isOAMUser
 *
 * Purpose:
 *   Searches for a user with the give name.
 *
 * Returns:
 *   noErr if user exists, appropriate OAMStatus otherwise
 */
OAMStatus
isOAMUser(OAMSessionID session, u_char * name)
{
    OAMObjectSpec		user;
    OAMAttributeDescriptor	attr[2];
    Str31			pname;
    Str31			inet_name;

    /* zero all fields */
    memset(&attr[0], 0, sizeof(attr));
    memset(inet_name, 0, sizeof(inet_name));

    /* convert C string to Pascal string */
    convertStrToPascalStr(name, pname);
    
    attr[0].attributeSignature = kUser;
    attr[0].attributeType = kInternetName;
    attr[0].bufferDescriptor.buffer = inet_name;
    attr[0].bufferDescriptor.bufferLen = sizeof(inet_name);
    attr[0].bufferDescriptor.actCount = 0;

    attr[1].attributeSignature = NULL;		/* mark end of list */

    /* lookup the object */
    BuildObjectSpecByNameType(&user, pname, kUser);
    return(OAMGetAttribute(session, &user, &attr[0], NULL));
}

/*
 * Function: setOAMUserPassword
 *
 * Purpose:
 *   Sets a user's password.
 *
 * Returns:
 *   noErr if password changed, appropriate OAMStatus otherwise
 */
OAMStatus
setOAMUserPassword(OAMSessionID session, u_char * name, u_char * passwd)
{
    OAMObjectSpec		user;
    OAMAttributeDescriptor	attr[2];
    Str31			pname;
    char 			password[AFP_PASSWORD_LEN];

    memset(&attr[0], 0, sizeof(attr));
    memset(password, 0, sizeof(password));

    /* user name must be a pascal string */
    convertStrToPascalStr(name, pname);

    /* make sure password is <= 8 chars long, zero-padded */
    strncpy(password, passwd, sizeof(password));

    attr[0].attributeSignature = kUser;
    attr[0].attributeType = kPasswordAttribute; /* password */
    attr[0].bufferDescriptor.buffer = password;
    attr[0].bufferDescriptor.bufferLen = 8;
    attr[0].bufferDescriptor.actCount = 0;

    attr[1].attributeSignature = NULL;		/* mark end of list */

    /* create the object */
    BuildObjectSpecByNameType(&user, pname, kUser);
    return(OAMSetAttribute(session, &user, &attr[0], NULL));
}


/*
 * Function: createOAMGroup
 *
 * Purpose:
 *   Creates a new OAM Group with the given name.
 *
 * Returns:
 *   noErr if group created, returns appropriate OAMStatus otherwise
 */
OAMStatus 
createOAMGroup(OAMSessionID session, unsigned char * name)
{
    OAMObjectSpec		group;
    Str31			pname;

    memset(&group, 0, sizeof(group));
    convertStrToPascalStr(name, pname);
    
    BuildObjectSpecByNameType(&group, pname, kGroup);
    return(OAMCreateObject(session, &group, NULL, NULL));
}



/*
 * Function: addOAMGroupMember
 *
 * Purpose:
 *   Adds the given user to the specified group.
 *
 * Returns:
 *   noErr if user added, returns appropriate OAMStatus otherwise
 */
OAMStatus
addOAMGroupMember(OAMSessionID session, StringPtr g, StringPtr u)
{
    Str31			group;
    OAMObjectSpec		group_spec;
    Str31			user;
    OAMObjectSpec		user_spec;

    convertStrToPascalStr(g, group);
    convertStrToPascalStr(u, user);
    BuildObjectSpecByNameType(&group_spec, group, kGroup);
    BuildObjectSpecByNameType(&user_spec, user, kUser);
    return (OAMAddGroupMember(session, &group_spec, &user_spec, NULL));
}

OAMStatus 
removeOAMGroupMember(OAMSessionID session, StringPtr g, StringPtr u)
{
    Str31			group;
    OAMObjectSpec		group_spec;
    Str31			user;
    OAMObjectSpec		user_spec;

    convertStrToPascalStr(g, group);
    convertStrToPascalStr(u, user);
    BuildObjectSpecByNameType(&group_spec, group, kGroup);
    BuildObjectSpecByNameType(&user_spec, user, kUser);
    return (OAMRemoveGroupMember(session, &group_spec, &user_spec, NULL));
}

/**
 ** Test Harness
 **/

#ifdef TEST_AFPUSER
OAMStatus
getOAMMachineName(OAMSessionID session, StringPtr name)
{
    OAMStatus			err = noErr;
    OAMObjectSpec		machine;
    OAMAttributeDescriptor	attr[2];

    memset(&attr, 0, sizeof(attr));
    attr[0].attributeSignature = kMachine;
    attr[0].attributeType = kServerName;
    attr[0].bufferDescriptor.buffer = name;
    attr[0].bufferDescriptor.bufferLen = sizeof(Str31);
    attr[0].bufferDescriptor.actCount = 0;
    /* null-terminate the list */
    attr[1].attributeSignature = NULL;
    
    BuildObjectSpecByShortID(&machine, kMachineShortID);
    return (OAMGetAttribute(session, &machine, attr, NULL));

}

#import <stdio.h>
main(int argc, char *argv[])
{
    OAMSessionID	sessionID;
    OAMStatus 		status;
    Str31		machineName;
    int			i;

    status = openOAMSession(&sessionID);
    if (status != noErr) {
	printf("openOAMSession failed with status %d\n", status);
	exit (1);
    }
    printf("session id is %d\n", sessionID);

#define USER	"user1"
#define EN_ADDR	"$080205FCD8FF"
#define PASSWD	"test"
#define GROUP	"Mac NC"

    {
	u_char * 	list[] = {USER, "user2", "", 0};
	u_char * * 	p;
	
	for (p = list; *p; p++) {
	    status = isOAMUser(sessionID, *p);
	    if (status == noErr)
		printf("user %s already exists\n", *p);
	    else
		printf("user %s doesn't exist, status %d\n", *p, status);
	}
    }

    status = createOAMUser(sessionID, USER, EN_ADDR, PASSWD);
    if (status != noErr) {
	if (kOAMErrDuplicateObject == status)
	    printf("user already present\n");
	else
	    fprintf(stderr, "createOAMUser %s failed, status %d\n", 
		    USER, status);
    }
    status = deleteOAMUser(sessionID, USER);
    if (status != noErr)
	fprintf(stderr, "deleteOAMUser %s failed, status %d\n", 
		USER, status);
    else
	printf("user %s deleted\n", USER);
    
    status = createOAMUser(sessionID, USER, EN_ADDR, PASSWD);
    if (status != noErr) {
	if (kOAMErrDuplicateObject == status)
	    printf("user already present\n");
	else
	    fprintf(stderr, "createOAMUser %s failed, status %d\n", 
		    USER, status);
    }
    else {
	printf("user %s created\n", USER);
    }
    status = createOAMGroup(sessionID, GROUP);
    if (status != noErr) {
	if (kOAMErrDuplicateObject == status)
	    printf("group %s already present\n", GROUP);
	else {
	    fprintf(stderr, "createOAMGroup %s failed %d\n", GROUP, status);
	}
    }
    status = addOAMGroupMember(sessionID, GROUP, USER);
    if (status == noErr) {
	printf("added user %s to group %s\n", USER, GROUP);
    }
    else {
	fprintf(stderr, "addOAMGroupMember failed, status %d\n", status);
    }

    status = setOAMUserPassword(sessionID, USER, "passwd");
    if (status == noErr) {
	printf("changed password for user %s to passwd\n", USER);
    }
    else {
	fprintf(stderr, "setOAMUserPassword failed, status %d\n", status);
    }

    machineName[0] = sizeof(machineName) - 1;
    status = getOAMMachineName(sessionID, (StringPtr)&machineName);
    if (status == noErr) {
	unsigned char m[32];
	printf("machine name is '%s'\n", 
	       convertPascalStrToStr(machineName, m));
    }
    else {
	fprintf(stderr, "status is %d\n", status);
    }

#if 0
    createOAMGroup(sessionID, "dieter_group");
    for (i = 0; i < 25; i++) {
	char name[32];
	sprintf(name, "name%d", i);
	status = deleteOAMUser(sessionID, name);
	if (status != noErr) {
	    fprintf(stderr, "deleteOAMUser %s failed, status %d\n", 
		    name, status);
	}
    }
    for (i = 0; i < 25; i++) {
	char name[32], inet_name[32];

	sprintf(name, "name%d", i);
	sprintf(inet_name, "iname%d", i);

	status = createOAMUser(sessionID, name, inet_name, "test");
	if (status != noErr) {
	    fprintf(stderr, "createOAMUser %s failed, status %d\n", 
		    name, status);
	}
	status = addOAMGroupMember(sessionID, "dieter_group", name);
	if (status != noErr) {
	    fprintf(stderr, "addOAMGroupMember %s to %s failed, status %d\n",
		    name, "dieter_group", status);
	}
    }
#endif
    printf("closing session %d\n", sessionID);
    status = closeOAMSession(sessionID);
    if (status != noErr)
	fprintf(stderr, "close session failed, status is %d\n");
    exit(0);
}
#endif TEST_AFPUSER
