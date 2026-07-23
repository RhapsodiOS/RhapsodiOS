/* Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved.
 *
 * stblocksize.c
 *
 * Read and set the native block size for a SCSI tape device.
 *
 * HISTORY
 * 18-Oct-93	Phillip Dibner at NeXT
 *	Created.
 */

#include <errno.h>
#include <sys/types.h>
#include <sys/file.h>
#include <bsd/dev/scsireg.h>
#include "stblocksize.h" /* XXX merge this file with scsireg.h */
#include <bsd/libc.h>
#include <bsd/sys/fcntl.h>
#include <ctype.h>
#include <objc/objc.h>

int	fd;
int	read_block_limits(), do_ioc();
void	usage();

int
main(int argc, char **argv)
{
    int		i, j, len;
    int		maxblocksize, minblocksize, blocksize;
    BOOL	verbose = NO, manualsize = NO;
    int		last = argc - 1;

    /*
     * Check argument count
     */
    if (argc < 2 || argc > 5) {
	usage();
	return -1;
    }

    for (i = 1; i < argc-1; i++) {

	/*
	 * See if we have been asked to print the device's blocksize...
	 */
	if (strcmp (argv [i], "-v") == 0) {
	    verbose = YES;
	}

	/*
	 * ... or if we are setting the blocksize from the command line.
	 */
	else if ((strcmp (argv[i], "-s")) == 0) {
	    manualsize = YES;

	    /*
	     * Check that next argument is a number, and convert it.
	     */
	    i++;
	    len = strlen (argv [i]);
	    for (j=0; j<len; j++) {
		if (!isdigit(argv[i][j])) {
		    usage();
		    return -1;
		}
	    }
	    blocksize = atoi (argv[i]);
	}

	else {
	    usage();
	    return -1;
	}
    }

    /*
     * Open the tape device, which should be the last argument
     */
    if ((fd = open(argv[last], O_RDWR, 777)) < 0) {
	printf ("Cannot open %s\n", argv[last]);
	return -1;
    }

    /*
     * Read block size.
     *
     * We don't read it if we're setting it manually.   This may allow us to
     * use a device that implements the READ_BLOCK_LIMITS command improperly.
     */
    if (!manualsize) {
	if (read_block_limits(&maxblocksize, &minblocksize)) {
	    printf ("Error reading block size parameters for %s\n",
		argv[last]);
	    return -1;
	}

	/*
	 * Equal max and min blocksize mean the device requires transfers
	 * with a fixed block size.
	 */
	if (maxblocksize == minblocksize) {
	    blocksize = minblocksize;
	}
	else {
	    blocksize = 0;
	}
    }

    if (verbose) {
	if (!manualsize)
	    printf ("Tape device %s block limits: min = %d, max = %d\n",
		argv[last], minblocksize, maxblocksize);
	printf ("Setting %s blocksize to %d.\n", argv[last], blocksize);
    }

    /*
     * Set the block size that the device will use for data transfers.
     */
    if (ioctl(fd, MTIOCFIXBLK, &blocksize))
    {
	printf ("Cannot set block size 0x%x for %s\n",
	    blocksize, argv[last]);
	return -1;
    }
    close (fd);
    return 0;
} /* main() */

int
read_block_limits (int *maxp, int *minp)
{
    struct scsi_req sr;
    struct cdb_6 *cdbp = &sr.sr_cdb.cdb_c6;
    struct read_blk_sz_reply rbsr;

    bzero ((char *) cdbp, sizeof (union cdb));
    cdbp->c6_opcode = C6OP_RDBLKLIMS;

    /*
     * NB: The lun is set by the driver, since we don't know what
     * it is from the user level.
     */

    sr.sr_dma_dir = SR_DMA_RD;
    sr.sr_addr = (caddr_t) &rbsr;
    sr.sr_dma_max = sizeof (struct read_blk_sz_reply);
    sr.sr_ioto = 10;
    if (do_ioc(&sr)) {
	return -1;
    }
    else {

#if	__BIG_ENDIAN__
	*maxp = rbsr.rsbr_max_bll;
	*minp = rbsr.rsbr_min_bll;
#elif	__LITTLE_ENDIAN__
	*maxp = (rbsr.rbsr_max_bll2 << 16) + (rbsr.rbsr_max_bll1 << 8) +
	    rbsr.rbsr_max_bll0;
	*minp = (rbsr.rbsr_min_bll1 << 8) + (rbsr.rbsr_min_bll0);
#else
#error	byte order?
#endif

    }
    return 0;
} /* read_block_limits() */

int
do_ioc(srp)
struct scsi_req *srp;
{

    if (ioctl(fd,MTIOCSRQ,srp) < 0) {
	printf("..Error executing ioctl\n");
	printf("errno = %d\n",errno);
	perror("ioctl (MTIOCSRQ)");
	return 1;
    }
    if(srp->sr_io_status) {
	printf("sr_io_status = 0x%X\n",srp->sr_io_status);
	if(srp->sr_io_status == SR_IOST_CHKSV) {
	    printf("   sense key = %02XH   sense code = %02XH\n",
		srp->sr_esense.er_sensekey,
		srp->sr_esense.er_addsensecode);
	}
	printf("SCSI status = %02XH\n", srp->sr_scsi_status);
	return 1;
    }
    return 0;
} /* do_ioc() */


void
usage()
{
	printf ("Usage: stblocksize [-v] [-s <blocksize>] "
		"<dev-full-pathname>\n");
	return;
}
