#!/bin/sh
#
# HISTORY
# 17-Oct-90  Gregg Kellogg (gk) at NeXT
#	Added -P and -p arguments.
#
# 27-May-87  Richard Draves (rpd) at Carnegie-Mellon University
#	Created.
#

MIGCOM_ROOT=${MIGCOM_DIR-/usr/libexec}
migcom=$MIGCOM_ROOT/migcom
cppflags="-DTYPED='T' -DUNTYPED='U'"
migflags=
files=

until [ $# -eq 0 ]
do
    case $1 in
	-[qQvVtTrRsSiPp] ) migflags="$migflags $1"; shift;;
	-user   ) migflags="$migflags $1 $2"; shift; shift;;
	-server ) migflags="$migflags $1 $2"; shift; shift;;
	-header ) migflags="$migflags $1 $2"; shift; shift;;
	-sheader ) migflags="$migflags $1 $2"; shift; shift;;
	-handler ) migflags="$migflags $1 $2"; shift; shift;;
	-i ) migflags="$migflags $1"; shift;
		if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
		    migflags="$migflags $1"; shift
		fi;;
	-arch ) arch=$2; shift; shift;;
	-typed ) migcom=$MIGCOM_ROOT/migcom_typd; 	\
		cppflags="$cppflags -DMACH_IPC_FLAVOR=TYPED"; shift;;
	-untyped ) migcom=$MIGCOM_ROOT/migcom_untypd; 	\
		cppflags="$cppflags -DMACH_IPC_FLAVOR=UNTYPED"; shift;;
#	-MD ) sawMD=1; cppflags="$cppflags $1"; shift;;
	-MD ) shift;;
	-* ) cppflags="$cppflags $1"; shift;;
	* ) files="$files $1"; shift;;
    esac
done

for file in $files
do
    base="`/usr/bin/basename "$file" .defs`"
    rm -f "$base".d "$base".d~
    if [ "${MIGCC-}" ]
    then
	"$MIGCC" -E -traditional-cpp $cppflags "$file"
    else
	CPP="/usr/libexec/${arch-`/usr/bin/arch`}/2.7.2.1/cpp"
	$CPP $cppflags "$file" - ${sawMD+"$base".d~}
    fi | "$migcom" $migflags || exit
    if [ $sawMD ]
    then
	sed 's/^'"$base"'.o/'"$base"'.h '"$base"'User.c '"$base"'Server.c/' \
		< "$base".d~ > "$base".d
	rm -f "$base".d~
    fi
done

exit 0
