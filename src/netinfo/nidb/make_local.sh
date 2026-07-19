#!/bin/sh

if [ $# != 4 ]; then
	echo "usage: make_local dirname netinfod niutil niload"
	exit 1
fi

if [ `whoami` != "root" ]; then
	echo "Must be root to run make_local"
	exit 1
fi

set -x
TMP="tmp"
TMPDIR=$TMP.nidb
DOMAIN=localhost/$TMP

DSTDIR=$1
NETINFOD=$2
NIUTIL=$3
NILOAD=$4

#
# Kill previous "netinofd tmp" if one exists
# (this shouldn't happen normally)
#
PID=`ps ax | grep "netinfod $TMP" | grep -v grep | awk '{print $1}'`
if [ ${PID}X != "X" ]; then
    kill -TERM $PID
fi

#
# Create an empty /tmp/tmp.nidb directory,
# and start a netinfo server for it.
#
savedir=`pwd`
cd /tmp
rm -rf $TMPDIR
mkdir $TMPDIR
$NETINFOD $TMP &
PID=$!
cd $savedir

#
# Wait for the server to start
#
sleep 5
WAIT=1
while (test $WAIT -eq 1) do
    sleep 2
    $NIUTIL -read -t $DOMAIN /
    WAIT=$?
done

#
# Create root directory information
#
$NIUTIL -createprop -t $DOMAIN / master localhost/local

#
# Create machines directory and populate
#
$NIUTIL -create -t $DOMAIN /machines 

#
# /machines/localhost
#
HOST=localhost
ADDRESS=127.0.0.1
SERVES=./local
$NIUTIL -create -t $DOMAIN /machines/$HOST
$NIUTIL -createprop -t $DOMAIN /machines/$HOST ip_address $ADDRESS
$NIUTIL -createprop -t $DOMAIN /machines/$HOST serves $SERVES

#
# /machines/broadcasthost
#
HOST=broadcasthost
ADDRESS=255.255.255.255
SERVES=../network
$NIUTIL -create -t $DOMAIN /machines/$HOST
$NIUTIL -createprop -t $DOMAIN /machines/$HOST ip_address $ADDRESS
$NIUTIL -createprop -t $DOMAIN /machines/$HOST serves $SERVES

#
# /localconfig
#
$NIUTIL -create -t $DOMAIN /localconfig

#
# Create niloadable directories
# XXX This assumes that the build environment's flat files are correct
#
$NILOAD -t aliases $DOMAIN < /etc/sendmail/aliases
$NILOAD -t group $DOMAIN < /etc/group
$NILOAD -t fstab $DOMAIN < /etc/fstab
$NILOAD -t passwd $DOMAIN < /etc/passwd
$NILOAD -t networks $DOMAIN < /etc/networks
$NILOAD -t protocols $DOMAIN < /etc/protocols
$NILOAD -t rpc $DOMAIN < /etc/rpc
$NILOAD -t services $DOMAIN < /etc/services

#
# Create other directories
#
$NIUTIL -create -t $DOMAIN /mounts
for DIR in printers locations fax_modems localconfig/ISDN localconfig/screens locations/renderers; do
	$NIUTIL -create -t $DOMAIN /$DIR
done

# Add /localconfig/screens _writers *
$NIUTIL -createprop -t $DOMAIN /localconfig/screens _writers '*'

#
# Create default renderer on localhost
#
$NIUTIL -create -t $DOMAIN /locations/renderers/localhost
$NIUTIL -createprop -t $DOMAIN /locations/renderers/localhost note 'Local Renderer'
$NIUTIL -createprop -t $DOMAIN /locations/renderers/localhost _writers '*'

#
# Copy database to destination directory
# 
cp -r /tmp/$TMPDIR $DSTDIR

#
# Clean up
# 
kill -TERM $PID
rm -rf /tmp/$TMPDIR
