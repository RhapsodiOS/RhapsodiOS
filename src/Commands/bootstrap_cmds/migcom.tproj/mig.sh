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
newline='
'
cppflags=
migflags=
files=

reject_newline()
{
    case $1 in
	*"$newline"* ) echo "mig: argument contains a newline" >&2; exit 1;;
    esac
}

append_cppflag()
{
    reject_newline "$1"
    if [ -n "$cppflags" ]; then
	cppflags="${cppflags}${newline}$1"
    else
	cppflags=$1
    fi
}

append_migflag()
{
    reject_newline "$1"
    if [ -n "$migflags" ]; then
	migflags="${migflags}${newline}$1"
    else
	migflags=$1
    fi
}

append_file()
{
    reject_newline "$1"
    if [ -n "$files" ]; then
	files="${files}${newline}$1"
    else
	files=$1
    fi
}

append_cppflag "-DTYPED='T'"
append_cppflag "-DUNTYPED='U'"

until [ $# -eq 0 ]
do
    case $1 in
	-[qQvVtTrRsSPp] ) append_migflag "$1"; shift;;
	-user   ) append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-server ) append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-header ) append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-sheader ) append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-handler ) append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-i ) append_migflag "$1"; shift;
		if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
		    append_migflag "$1"; shift
		fi;;
	-arch ) reject_newline "$2"; arch=$2; shift; shift;;
	-typed ) migcom=$MIGCOM_ROOT/migcom_typd; 	\
		append_cppflag '-DMACH_IPC_FLAVOR=TYPED'; shift;;
	-untyped ) migcom=$MIGCOM_ROOT/migcom_untypd; 	\
		append_cppflag '-DMACH_IPC_FLAVOR=UNTYPED'; shift;;
#	-MD ) sawMD=1; append_cppflag "$1"; shift;;
	-MD ) shift;;
	-* ) append_cppflag "$1"; shift;;
	* ) append_file "$1"; shift;;
    esac
done

old_ifs=$IFS
IFS=$newline
set -f
for file in $files
do
    base=${file##*/}
    base=${base%.defs}
    rm -f "$base".d "$base".d~
    if [ "${MIGCC-}" ]
    then
	"$MIGCC" -E -x c -traditional-cpp $cppflags "$file"
    else
	CPP="/usr/libexec/${arch-`/usr/bin/arch`}/2.7.2.1/cpp"
	"$CPP" $cppflags "$file" - ${sawMD+"$base".d~}
    fi | "$migcom" $migflags || exit
    if [ $sawMD ]
    then
	sed 's/^'"$base"'.o/'"$base"'.h '"$base"'User.c '"$base"'Server.c/' \
		< "$base".d~ > "$base".d
	rm -f "$base".d~
    fi
done
IFS=$old_ifs

exit 0
