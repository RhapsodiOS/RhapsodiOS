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
	Copyright (c) 1987-98 Apple Computer, Inc.
	All Rights Reserved.
		
	About cd9660.util.m:
	Contains code to implement ISO cdrom utility used by the WorkSpace to mount ISO 9660 CDs.
	
	To do:
	look for "PPD" for unresolved issues
	
	Change History:
        07/30/98 chw Changed Do Verify Args to only display proper usage if 0 args are specified.
	07/24/98 chw Changed open of device file to include the no delay option
	01/13/98 jwc first cut (derived from old NextStep macfs.util code and cdrom.util code).
*/

/* ************************************** I N C L U D E S ***************************************** */

#import <Foundation/Foundation.h>
#import <kernserv/loadable_fs.h>
#import	<bsd/libc.h>
#import <bsd/dev/disk.h>

// PPD - is this still needed????

#define DEBUG 0
/* **************************************** L O C A L S ******************************************* */

#define RAW_DEVICE_PREFIX 		"/private/dev/r"
#define DEVICE_PREFIX 			"/private/dev/"
#define DEVICE_SUFFFIX 			"a"
#define	CDROM_BLOCK_SIZE		2048
#define MAX_BLOCK_TO_SCAN		100
#define ISO_STANDARD_ID 		"CD001"
#define ISO_VD_PRIMARY 			0x01  // for ISOVolumeDescriptor.type when it's a primary descriptor
#define ISO_FS_NAME				"cd9660"
#define ISO_FS_NAME_NAME		"CDROM (ISO 9660)"
#define DEFAULT_MOUNT_POINT		"/isoCD"
#define	MOUNT_COMMAND			"/sbin/mount"
#define	UMOUNT_COMMAND			"/sbin/umount"
#define MOUNT_FS_TYPE			"cd9660"

typedef struct ISOVolumeDescriptor
{
	char		type[1];
	char		id[5];			// should be "CD001"
	char		version[1];
	char		filler[33];
	char		volumeID[32];
	char		filler2[1976];
} ISOVolumeDescriptor, *ISOVolumeDescriptorPtr;


/* ************************************ P R O T O T Y P E S *************************************** */

static void 			DoDisplayUsage( const char *argv[] );
static void 			DoFileSystemFile( char *theFileNameSuffixPtr, char *theContentsPtr );
static int 			DoMount( char *theDeviceNamePtr, const char *theMountPointPtr );
static int 			DoProbe( char *theDeviceNamePtr );
static int 			DoUnmount( char *theDeviceNamePtr );
static int 			DoVerifyArgs( int argc, const char *argv[] );


/* ******************************************** main ************************************************
Purpose -
	This our main entry point to this utility.  We get called by the WorkSpace.  See DoVerifyArgs 
	for detail info on input arguments.
Input - 
	argc - the number of arguments in argv.
	argv - array of arguments.
Output -
	returns FSUR_IO_SUCCESS if OK else one of the other FSUR_xxxx errors in loadable_fs.h.
*************************************************************************************************** */

int main( int argc, const char *argv[] )
{
	NSAutoreleasePool 	*pool = [[NSAutoreleasePool alloc] init];
	const char			*myActionPtr;
	int					myError = FSUR_IO_SUCCESS;
	char				myRawDeviceName[256];
	char				myDeviceName[256];

#if DEBUG
{
	int		i;
	printf("\n cd9660.util - entering with argc of %d \n", argc );
	
	for ( i = 0; i < argc; i++ )
	{
		printf("argv[%d] is \"%s\" \n", i, argv[i] );
	}
}
#endif //

   	/* Verify our arguments */
   	if ( (myError = DoVerifyArgs( argc, argv )) != 0 )
   		goto AllDone;
   		
   	/* Build our device name (full path), should end up with something like: */
   	/* /dev/sd2a */
   	strcpy( &myDeviceName[0], DEVICE_PREFIX );
    strcat( &myDeviceName[0], argv[2] );
    strcat( &myDeviceName[0], DEVICE_SUFFFIX );	// PPD - is this always correct????
   	strcpy( &myRawDeviceName[0], RAW_DEVICE_PREFIX );
    strcat( &myRawDeviceName[0], argv[2] );
    strcat( &myRawDeviceName[0], DEVICE_SUFFFIX );	// PPD - is this always correct????
   
	/* call the appropriate routine to handle the given action argument after becoming root */
	myActionPtr = &argv[1][1];
	myError = seteuid( 0 );
#if DEBUG
                printf ("Error setting uid\n");
                printf ("Error %d was from seteuid call %s\n",errno,strerror(errno));
#endif

	myError = setegid( 0 );	// PPD - is this necessary?

#if DEBUG
                printf ("Error setting gid\n");
                printf ("Error %d was from setegid call %s\n",errno,strerror(errno));
#endif

#if DEBUG
	printf ("Entering the switch with myaction = %s\n",myActionPtr);
#endif
    switch( *myActionPtr ) 
    {
	case FSUC_PROBE:
#if DEBUG
	    printf ("Calling DoProbe \n");
#endif
	    myError = DoProbe( &myRawDeviceName[0] );
	    break;
	    
	case FSUC_MOUNT:
	case FSUC_MOUNT_FORCE:
	    myError = DoMount( &myDeviceName[0], argv[3] );
	    break;
	    
	case FSUC_UNMOUNT:
        myError = DoUnmount( argv[3] );
	    break;
	    
	default:
		/* should never get here since DoVerifyArgs should handle this situation */
	    myError = FSUR_INVAL;
	    break;
    }

AllDone:

#if DEBUG
	printf("\n cd9660.util - leaving with result of %d \n", myError );
#endif //

   [pool release];
   exit	(myError);
   return myError; /* and make main fit the ANSI spec. */
   
} /* main */


/* ******************************************* DoMount **********************************************
Purpose -
	This routine will fire off a system command to mount the given device at the given mountpoint.
	NOTE - Workspace will make sure the mountpoint exists and will remove it at Unmount time.
Input - 
	theDeviceNamePtr - pointer to the device name (full path, like /dev/rsd2a).
	theMountPointPtr - pointer to the mount point.
Output -
	returns FSUR_IO_SUCCESS everything is cool else one of several other FSUR_xxx error codes.
*************************************************************************************************** */

static int DoMount( char *theDeviceNamePtr, const char *theMountPointPtr )
{
    int		myError;
    union wait  status;
    int    	pid;
	
    if ( theMountPointPtr == NULL || *theMountPointPtr == 0x00 )
    {
	myError = FSUR_IO_FAIL;
	goto ExitThisRoutine;
    }
	
    /* ISO 9660 CDs use the system mount command */
    pid = fork();
    if (pid == 0) {
        myError = execl(MOUNT_COMMAND, MOUNT_COMMAND, "-t", MOUNT_FS_TYPE, theDeviceNamePtr, theMountPointPtr, NULL);

        /* IF WE ARE HERE, WE WERE UNSUCCESFULL */
#if DEBUG
        printf ("Error %d from system command %s\n",myError,strerror(myError));
#endif
        myError = FSUR_IO_FAIL;
        goto ExitThisRoutine;
    }

    if (pid == -1) {
        myError = FSUR_IO_FAIL;
        goto ExitThisRoutine;
    }

    /* Success! */
    if ((wait4(pid, (int *)&status, 0, NULL) == pid) && (WIFEXITED(status))) {
        myError = status.w_retcode;
    }
    else {
        myError = -1;
    }

    if ( myError != 0 )
        myError = FSUR_IO_FAIL;
    else
        myError = FSUR_IO_SUCCESS;
	 
ExitThisRoutine:
	return myError;
		
} /* DoMount */


/* ****************************************** DoUnmount *********************************************
Purpose -
	This routine will fire off a system command to unmount the given device.
Input - 
	theDeviceNamePtr - pointer to the device name (full path, like /dev/sd2a).
Output -
	returns FSUR_IO_SUCCESS everything is cool else FSUR_IO_FAIL.
*************************************************************************************************** */

static int DoUnmount( char *theDeviceNamePtr )
{
	int						myError;
    int						mountflags = 0; /* for future stuff */

    myError = unmount(theDeviceNamePtr, mountflags);

#if DEBUG
        if (myError != 0)
                {
                printf ("Error %d from system command in DoUnmount %s\n",myError,strerror(myError));
                }
#endif

	if ( myError != 0 )
		myError = FSUR_IO_FAIL;
	else
		myError = FSUR_IO_SUCCESS;
		
	return myError;
		
} /* DoUnmount */


/* ******************************************* DoProbe **********************************************
Purpose -
	This routine will open the given raw device and check to make sure there is media that looks
	like an ISO 9660 CD.
Input - 
	theDeviceNamePtr - pointer to the device name (full path, like /dev/rsd2a).
Output -
	returns FSUR_RECOGNIZED if we can handle the media else one of the FSUR_xxx error codes.
*************************************************************************************************** */

static int DoProbe( char *theDeviceNamePtr )
{
	int						myError;
	int 					myFD = 0;
	int						isFormated = 0;
	long					myBlockNum;
	ISOVolumeDescriptorPtr	myISOVolDescPtr;
	char 					myBuffer[CDROM_BLOCK_SIZE];
	char 					*myBufferPtr = &myBuffer[0];
	
	myFD = open( theDeviceNamePtr, O_RDONLY | O_NDELAY , 0 );
	if( myFD <= 0 )
	{
		
#if DEBUG
		printf ("Error opening the device name from DoProbe, Device was %s\n",theDeviceNamePtr);
		printf ("Error %d was from an open call %s\n",errno,strerror(errno));
#endif
		myError = FSUR_IO_FAIL;
		goto ExitThisRoutine;
	}
	
	/* Make sure the device is formatted.  If not, bail immediately. */
	if ( ioctl( myFD, DKIOCGFORMAT, &isFormated ) != 0 )  
	{
		myError = FSUR_IO_FAIL;
		goto ExitThisRoutine;
	}
	
	if ( isFormated == 0 )
	{
		myError = FSUR_UNRECOGNIZED;
		goto ExitThisRoutine;
	}

	/* Scan for the ISO Volume Descriptor.  It should be at block 16 on the CD but may be past */
	/* block 16.  We'll scan a few blocks looking for it. */
	myISOVolDescPtr = (ISOVolumeDescriptorPtr) myBufferPtr;
	lseek( myFD, (16 * CDROM_BLOCK_SIZE), 0 );
	for ( myBlockNum = 16; myBlockNum < MAX_BLOCK_TO_SCAN; myBlockNum++ )
	{
		if ( read( myFD, myBufferPtr, CDROM_BLOCK_SIZE ) != CDROM_BLOCK_SIZE )
		{
			myError = FSUR_IO_FAIL;
			goto ExitThisRoutine;
		}
				
		if ( memcmp( &myISOVolDescPtr->id[0], ISO_STANDARD_ID, sizeof(myISOVolDescPtr->id) ) == 0 )
		{
			/* We found a match on id "CD001".  Now make sure type is for the primary descriptor */
			if ( myISOVolDescPtr->type[0] == ISO_VD_PRIMARY )
			{
				DoFileSystemFile( FS_NAME_SUFFIX, ISO_FS_NAME_NAME );
				myISOVolDescPtr->filler2[0] = 0x00; // make sure volume ID is null terminated
				DoFileSystemFile( FS_LABEL_SUFFIX, &myISOVolDescPtr->volumeID[0] );
				break;
			}
		}
	} /* end of for loop */

	if ( myBlockNum >= MAX_BLOCK_TO_SCAN )
	{
		/* Didn't find the ISO volume descriptor */
		myError = FSUR_UNRECOGNIZED;
		goto ExitThisRoutine;
	}
	 
	myError = FSUR_RECOGNIZED;
	
ExitThisRoutine:
	if ( myFD > 0 )
		close( myFD );
		
	return myError;
		
} /* DoProbe */


/* **************************************** DoVerifyArgs ********************************************
Purpose -
	This routine will make sure the arguments passed in to us are cool.
	Here is how this utility is used:
	
	usage: ISO-cdrom.util actionArg deviceArg [mountPointArg] [flagsArg]
	actionArg:
		-p (Probe for mounting)
       	-P (Probe for initializing - not supported) 
       	-m (Mount)
		-r (Repair - not supported)
		-u (Unmount)
		-M (Force Mount)
		-i (Initialize - not supported)

	deviceArg:
		sd2 (for example)

	mountPointArg:
		/foo/bar/ (required for Mount and Force Mount actions)

	flagsArg:
		(these are ignored for CDROMs)
		either "readonly" OR "writable"
		either "removable" OR "fixed"
		
	examples:
		cd9660.util -p sd2
		cd9660.util -m sd2 /cd9660MountPoint
		
Input - 
	argc - the number of arguments in argv.
	argv - array of arguments.
Output -
	returns FSUR_INVAL if we find a bad argument else 0.
*************************************************************************************************** */

static int DoVerifyArgs( int argc, const char *argv[] )
{
	int			myError = FSUR_INVAL;
	int			myDeviceLength;

	/* If there are no arguments at all, we'll display useage.  Otherwise we'll just return    */
        /* with FSUR_INVAL.  It is set at the beginning so each of the various if statements below */
  	/* will just jump to the error exit and return myerror unchanged.			   */
	
	if (argc == 1)
	{
		DoDisplayUsage( argv );
		goto ExitThisRoutine;
	}
	
	
	/* Must have at least 3 arguments and the action argument must start with a '-' */
	if ( (argc < 3) || (argv[1][0] != '-') )
	{
		goto ExitThisRoutine;
	}

	/* we only support actions Probe, Mount, Force Mount, and Unmount */
    	if ( !((argv[1][1] == FSUC_PROBE) || (argv[1][1] == FSUC_MOUNT) ||
    	  (argv[1][1] == FSUC_UNMOUNT) || (argv[1][1] == FSUC_MOUNT_FORCE)) ) 
        {
		goto ExitThisRoutine;
	}

	/* action Mount and ForceMount require 4 arguments (need the mountpoint) */
     	if ( (argv[1][1] == FSUC_MOUNT) || (argv[1][1] == FSUC_MOUNT_FORCE) )
    	{
    		if ( argc < 4 ) 
    		{
			goto ExitThisRoutine;
		}
	}

	/* Make sure device (argv[2]) is something reasonable (we expect something like "sd2") */
	myDeviceLength = strlen( argv[2] );
    	if ( myDeviceLength < 2 || myDeviceLength > 6 )
    	{
		goto ExitThisRoutine;
	}
	
	myError = 0;

ExitThisRoutine:
	return myError;
	
} /* DoVerifyArgs */


/* *************************************** DoDisplayUsage ********************************************
Purpose -
	This routine will do a printf of the correct usage for this utility.
Input - 
	argv - array of arguments.
Output -
	NA.
*************************************************************************************************** */

static void DoDisplayUsage( const char *argv[] )
{
    printf("usage: %s action_arg device_arg [mount_point_arg] \n", argv[0]);
    printf("action_arg:\n");
    printf("       -%c (Probe for mounting)\n", FSUC_PROBE);
    printf("       -%c (Mount)\n", FSUC_MOUNT);
    printf("       -%c (Unmount)\n", FSUC_UNMOUNT);
    printf("       -%c (Force Mount)\n", FSUC_MOUNT_FORCE);
    printf("device_arg:\n");
    printf("       device we are acting upon (for example, \"sd2\")\n");
    printf("mount_point_arg:\n");
    printf("       required for Mount and Force Mount \n");
    printf("Examples:\n");
    printf("       %s -p sd2 \n", argv[0]);
    printf("       %s -m sd2 /my/cdrom \n", argv[0]);

	return;
		
} /* DoDisplayUsage */


/* ************************************** DoFileSystemFile *******************************************
Purpose -
	This routine will create a file system info file that is used by WorkSpace.  After creating the
	file it will write whatever theContentsPtr points to the new file.
	We end up with a file something like:
	/usr/filesystems/cd9660.fs/cd9660.name 
	when our file system name is "cd9660" and theFileNameSuffixPtr points to ".name"
Input - 
	theFileNameSuffixPtr - pointer to a suffix we add to the file name we're creating.
	theFileNameSuffixPtr - pointer to a suffix we add to the file name we're creating.
Output -
	NA.
*************************************************************************************************** */

static void DoFileSystemFile( char *theFileNameSuffixPtr, char *theContentsPtr )
{
    int    		myFD;
    char   		myFileName[MAXPATHLEN];

    /* Remove any trailing white space */
    if ( strlen(theContentsPtr) )
    {
    	char    	*myPtr;
    	
		myPtr = theContentsPtr + strlen( theContentsPtr ) - 1;
		while ( *myPtr == ' ' && myPtr >= theContentsPtr )
		{
	    	*myPtr = 0x00;
	    	myPtr--;
		}
    }
    sprintf( &myFileName[0], "%s/%s%s/%s", FS_DIR_LOCATION, ISO_FS_NAME, FS_DIR_SUFFIX, ISO_FS_NAME );
    strcat( &myFileName[0], theFileNameSuffixPtr );
    unlink( &myFileName[0] );		/* erase existing string */

    if ( strlen( theFileNameSuffixPtr ) )
    {
    	int myOldMask = umask(0);
    	
		myFD = open( &myFileName[0], O_CREAT | O_TRUNC | O_WRONLY, 0644 );
		umask( myOldMask );
		if ( myFD > 0 ) 
		{
	    	write( myFD, theContentsPtr, strlen( theContentsPtr ) );
	    	close( myFD );
		} 
		else 
		{
	    	perror( myFileName );
		}
    }
    
    return;
    
} /* DoFileSystemFile */
