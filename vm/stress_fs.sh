#!/bin/sh
# The guest side of `ffsbench stress --fs`.
#   stress_fs.sh build TAR            unpack the file systems' tool sources, build the tools
#   stress_fs.sh run FS CATS SEED     make FS on its target, mount it, run the suite there,
#                                     unmount and fsck it; the last line is
#                                     STRESSFS <fs> status=ran|unsup reason="..." fsck="..."
# Targets: ext2 = hd2a (made on the host), hfs = hd2b, msdos = hd2c, nfs = a loopback
# export of /mnt1/nfsexp on the UFS scratch disk.  hfs and ext2 are fscked on the host.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
FS=/var/fs; T=$FS/bin; STRESS=/usr/local/stress

# run "$@" for at most $1 seconds (a kill gives status 137); a process stuck in an
# uninterruptible kernel sleep cannot be killed, so that wait never ends
lim() {
	s=$1; shift
	"$@" & p=$!
	( sleep $s; kill -9 $p 2>/dev/null ) & w=$!
	wait $p; r=$?
	kill $w 2>/dev/null
	return $r
}

out() { echo "STRESSFS $1 status=$2 reason=\"$3\" fsck=\"$4\""; }

build() {
	mkdir -p $FS $T && cd $FS && rm -rf src && tar xf "$1" 2>/dev/null || return 1
	S=$FS/src; K=$S/kernel-7/bsd; DL=$S/Commands/diskdev_cmds/disklib
	b() { n=$1; shift; cc -O "$@" -o $T/$n > $FS/$n.log 2>&1 && echo "BUILD $n ok" || echo "BUILD $n failed"; }
	cd $S/ext2fs-1 && b mount_ext2fs -I$K -I$K/ext2fs -Iext2_tools/include -Icommon ext2_mount/mount_ext2fs.c
	H=$K/hfs/hfscommon/headers
	printf 'int optreset;\n#include "hfs_mount/mount_hfs.c"\n' > $FS/mh.c
	cd $S/hfs-1 && b mount_hfs -Wno-precomp -Dtv_sec=ts_sec -I. -Ihfs_mount -I$H -I$H/system -I$DL $FS/mh.c $DL/getmntopts.c
	b newfs_hfs -Wno-precomp -I$S/kernel-7 -I. -Ihfs_newfs -I$H -I$H/system hfs_newfs/newfs_hfs.c hfs_newfs/HFSVolumeInit.c
	cd $S/msdosfs-1 && b newfs_msdos -I$S/kernel-7 msdos_newfs/newfs_msdos.c
	b mount_msdos -I$K -Imsdos_mount -I$DL msdos_mount/mount_msdos.c $DL/getmntopts.c
	b fsck_msdos -Imsdos_fsck msdos_fsck/*.c
}

# mount FS on $mnt; on failure print why and return 1
mountfs() {
	case $1 in
	ext2)	lim 120 $T/mount_ext2fs /dev/hd2a $mnt ;;
	hfs)	test -b /dev/hd2b_hfs_ || mknod /dev/hd2b_hfs_ b 3 17	# newfs_hfs wants an *_hfs_* block node
		lim 300 $T/newfs_hfs /dev/hd2b_hfs_ > /dev/null && lim 120 $T/mount_hfs /dev/hd2b $mnt ;;
	msdos)	lim 300 $T/newfs_msdos /dev/rhd2c > /dev/null && lim 120 $T/mount_msdos /dev/hd2c $mnt ;;
	nfs)	mkdir -p /mnt1/nfsexp && chmod 777 /mnt1/nfsexp || return 1
		# this mountd reads its exports from NetInfo, not /etc/exports
		niutil -read . /exports/stressnfs > /dev/null 2>&1 || {
			niutil -create . /exports/stressnfs &&
			niutil -createprop . /exports/stressnfs opts maproot=root &&
			niutil -createprop . /exports/stressnfs name /mnt1/nfsexp; } || return 1
		ps -ax | grep -v grep | grep -q mountd || /usr/sbin/mountd
		ps -ax | grep -v grep | grep -q nfsd || /sbin/nfsd -tu -n 4
		kill -HUP `ps -ax | grep -v grep | grep mountd | awk '{print $1}'` 2>/dev/null
		sleep 2
		# 127.0.0.1 does not resolve in this libc's RPC lookups; localhost does
		lim 120 mount_nfs localhost:/mnt1/nfsexp $mnt ;;
	*)	return 1 ;;
	esac
}

run() {
	fs=$1; cats=$2; seed=$3; mnt=/mnt/$fs
	mkdir -p $mnt
	err=`mountfs $fs 2>&1` || { out $fs unsup "mount: `echo $err | tr '\"' "'" | cut -c1-200`" ""; return; }
	# an nfs line ends at the mount point, a local one goes on with "(local)"
	mount | awk -v m=$mnt '$3 == m { f = 1 } END { exit !f }' || { out $fs unsup "not mounted" ""; return; }
	rm -rf $STRESS/Report.$fs
	(cd $STRESS && sh ./run -s $seed -d $mnt 1 $cats) > $FS/run.$fs.log 2>&1
	cp -r $STRESS/Report $STRESS/Report.$fs
	um=""
	lim 300 umount $mnt || lim 120 umount -f $mnt || um="umount failed; "
	case $fs in
	msdos)	f=`lim 600 $T/fsck_msdos -n /dev/rhd2c 2>&1`
		case $? in 0) f=clean ;; *) f=`echo $f | tr '\"' "'" | tail -c 200` ;; esac ;;
	nfs)	f="n/a" ;;	# the export lives on hd1 (UFS)
	*)	f=host ;;	# ext2 and hfs are checked from the disk image after the guest stops
	esac
	out $fs ran "" "$um$f"
}

case $1 in
build)	build "$2" ;;
run)	run "$2" "$3" "$4" ;;
*)	echo "usage: stress_fs.sh build TAR | run FS CATS SEED" >&2; exit 2 ;;
esac
