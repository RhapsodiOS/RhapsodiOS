#!/bin/sh
set -eu
mode=$1
out=$2
arch=${3-i386}
case "$arch" in i386|ppc) ;; *) echo "unsupported architecture: $arch" >&2; exit 1 ;; esac
src=`pwd`
case "$mode" in
mach|host|exc|port|memory|default) dir=mach ;;
debug) dir=mach_debug ;;
kern|reply) dir=kernserv ;;
driver) dir=driverkit ;;
*) echo "unknown MIG recipe: $mode" >&2; exit 1 ;;
esac
mkdir -p "$out/$dir"
cd "$out/$dir"
common="-MD -I. -I.. -I$src -DKERNEL"
test "$arch" != ppc || common="-arch ppc $common"
rm -f "$mode.stamp" "$mode.raw"
run()
{
    cppflags=
    typed=
    skip=
    source=
    for arg do
        if test -n "$skip"; then skip=; continue; fi
        case "$arg" in
        -typed) typed=-DMACH_IPC_FLAVOR=TYPED ;;
        -untyped) typed=-DMACH_IPC_FLAVOR=UNTYPED ;;
        -D*|-I*) cppflags="$cppflags $arg" ;;
        -arch|-header|-user|-server|-sheader|-handler) skip=1 ;;
        -MD|-i) ;;
        *) source=$arg ;;
        esac
    done
    cc -M -arch "$arch" -x c -traditional-cpp "-DTYPED='T'" "-DUNTYPED='U'" $typed $cppflags "$source" >> "$mode.raw"
    mig "$@"
}
case "$mode" in
mach)
    run -typed $common -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_server.c "$src/mach/mach.defs"
    run -typed $common -header mach_kernloader.h -i -server /dev/null "$src/mach/mach.defs"
    run -typed $common -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_server.c "$src/mach/mach.defs"
    run $common -header mach_interface.h -i -server /dev/null "$src/mach/mach.defs"
    sed -n 's/.*Routine \([a-z_]*\).*/#define \1 \1_EXTERNAL/p' mach_interface.h > mach_user_internal.h
    ;;
host)
    run -typed $common -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_host_server.c "$src/mach/mach_host.defs"
    run $common -header mach_host.h -user /dev/null -server /dev/null "$src/mach/mach_host.defs"
    ;;
exc) run $common -header exc.h -user /dev/null -server exc_server.c "$src/mach/exc.defs" ;;
port) run -untyped $common -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_port_server.c "$src/mach/mach_port.defs" ;;
memory) run -typed $common -DKERNEL_USER -DSEQNOS -header memory_object_user.h -user memory_object_user.c -server /dev/null "$src/mach/memory_object.defs" ;;
default) run -typed $common -DKERNEL_USER -DSEQNOS -header memory_object_default.h -user memory_object_default_user.c -server /dev/null "$src/mach/memory_object_default.defs" ;;
debug) run -untyped $common -DKERNEL_SERVER -header mach_debug.h -user /dev/null -server mach_debug_server.c "$src/mach_debug/mach_debug.defs" ;;
kern) run $common -header kern_server.h -sheader kern_server_handler.h -user /dev/null -handler kern_server_handler.c "$src/kernserv/kern_server.defs" ;;
reply) run $common -header kern_server_reply.h -user kern_server_reply_user.c -server /dev/null "$src/kernserv/kern_server_reply.defs" ;;
driver) run -typed $common -arch "$arch" -DKERNEL_SERVER -header /dev/null -user /dev/null -server driverServerServer.c driverServer.defs ;;
esac
case "$mode" in
mach) target=$out/mach/mach_interface.h ;;
host) target=$out/mach/mach_host.h ;;
exc) target=$out/mach/exc.h ;;
port) target=$out/mach/mach_port_server.c ;;
memory) target=$out/mach/memory_object_user.h ;;
default) target=$out/mach/memory_object_default.h ;;
debug) target=$out/mach_debug/mach_debug.h ;;
kern) target=$out/kernserv/kern_server.h ;;
reply) target=$out/kernserv/kern_server_reply.h ;;
driver) target=$out/driverkit/driverServerServer.c ;;
esac
awk -v target="$target" -v base="$out/$dir" -f "$src/ninja/depfile.awk" "$mode.raw" > "$mode.nd"
date > "$mode.stamp"
