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

require_operand()
{
    option=$1
    operand=${2-}
    if [ -z "$operand" ]; then
	echo "mig: $option requires a nonempty operand" >&2
	exit 1
    fi
    case $operand in
	-* ) echo "mig: $option operand may not be another option: $operand" >&2; exit 1;;
    esac
    reject_newline "$operand"
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
	-user   ) require_operand "$1" "${2-}"; append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-server ) require_operand "$1" "${2-}"; append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-header ) require_operand "$1" "${2-}"; append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-sheader ) require_operand "$1" "${2-}"; append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-handler ) require_operand "$1" "${2-}"; append_migflag "$1"; append_migflag "$2"; shift; shift;;
	-i ) append_migflag "$1"; shift;
		if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
		    append_migflag "$1"; shift
		fi;;
	-arch ) require_operand "$1" "${2-}"; arch=$2; shift; shift;;
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
mig_tmp_dir=
mig_tmp=
mig_sequence=x
cleanup()
{
    if [ -n "$mig_tmp_dir" ]; then
	rm -f "$mig_tmp_dir/input"
	rmdir "$mig_tmp_dir" 2>/dev/null || :
	mig_tmp_dir=
	mig_tmp=
    fi
}
finish()
{
    mig_status=$?
    trap - 0
    cleanup
    exit $mig_status
}
trap finish 0
trap 'exit 1' 1 2 3 15
umask 077
for file in $files
do
    base=${file##*/}
    base=${base%.defs}
    rm -f "$base".d "$base".d~
    mig_tmp_candidate="./.${base}.migcpp.$$.$mig_sequence.d"
    mig_sequence=${mig_sequence}x
    if mkdir "$mig_tmp_candidate"
    then
	mig_tmp_dir=$mig_tmp_candidate
	mig_tmp="$mig_tmp_dir/input"
    else
	echo "mig: could not create private preprocessor staging directory: $mig_tmp_candidate" >&2
	exit 1
    fi
    if [ "${MIGCC-}" ]
    then
	if "$MIGCC" -E -x c -traditional-cpp $cppflags "$file" > "$mig_tmp"
	then
	    :
	else
	    mig_status=$?
	    echo "mig: configured preprocessor failed for $file" >&2
	    exit $mig_status
	fi
    else
	# MIGCPP is an optional compatibility override.  When it is unset,
	# preserve the architecture-specific compiler-suite cpp location.
	if [ "${MIGCPP-}" ]; then
	    CPP=$MIGCPP
	else
	    CPP="/usr/libexec/${arch-`/usr/bin/arch`}/2.7.2.1/cpp"
	fi
	if "$CPP" $cppflags "$file" - ${sawMD+"$base".d~} > "$mig_tmp"
	then
	    :
	else
	    mig_status=$?
	    echo "mig: default preprocessor failed for $file" >&2
	    exit $mig_status
	fi
    fi
    if "$migcom" $migflags < "$mig_tmp"
    then
	:
    else
	mig_status=$?
	echo "mig: backend failed for $file" >&2
	exit $mig_status
    fi
    cleanup
    if [ $sawMD ]
    then
	sed 's/^'"$base"'.o/'"$base"'.h '"$base"'User.c '"$base"'Server.c/' \
		< "$base".d~ > "$base".d
	rm -f "$base".d~
    fi
done
IFS=$old_ifs

exit 0
