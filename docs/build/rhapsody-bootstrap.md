# Rhapsody / Mac OS X Server PPC/Intel bootstrap

Status: host SSH setup procedure for a native Rhapsody DR2 / Mac OS X Server
1.0–1.2v3 machine (PowerPC or Intel). Stock Rhapsody does not ship this
OpenSSH stack; build zlib 1.1.4, OpenSSL 0.9.8, and OpenSSH 3.2.3p1 from
source, then start `sshd` at boot. This is access prep for using the box as a
remote build host.

You need Apple's Developer Tools already installed (`cc`, `make`). Do the
download and compile steps as root (`su` after the wheel membership step).

`wget` is part of the native Rhapsody command set, but it only speaks HTTP and
FTP. Do not use HTTPS URLs.

## Host prerequisites

Do these on the console before you try to work over the network:

1. Add your local user to `wheel` so `su` works.
2. Enable remote telnet and remote login.
3. Set up machine networking (address, netmask, router, name service as
   needed).
4. Telnet into the machine.
5. Download the packages below and build the SSH server daemon.
6. Build and install SSH.
7. Have SSH start on system startup.

After step 4, the rest of this document is the remote session.

## SSH build steps

Pick a writable directory (for example `/tmp`) and work as root.

### zlib install

Grab zlib 1.1.4 from http://zlib.net/fossils

```sh
wget http://zlib.net/fossils/zlib-1.1.4.tar.gz
tar -xzvf zlib-1.1.4.tar.gz
cd zlib-1.1.4
./configure
make install
```

### OpenSSL install

Grab OpenSSL 0.9.8 from
http://mirror.math.princeton.edu/pub/openssl/source/old/0.9.x/

```sh
wget http://mirror.math.princeton.edu/pub/openssl/source/old/0.9.x/openssl-0.9.8.tar.gz
tar -xzvf openssl-0.9.8.tar.gz
cd openssl-0.9.8
```

If using Rhapsody DR2 on x86, run this perl command to add the correct rhapsody-i386-cc compiler flag

```sh
perl -pi -e 'print "\"rhapsody-i386-cc\",\"cc:-O3 -DL_ENDIAN::(unknown):MACOSX_RHAPSODY::BN_LLONG \${x86_gcc_des} \${x86_gcc_opts}:\${no_asm}::\",\n" if /^"rhapsody-ppc-cc"/' Configure
```

Disable hardware acceleration and SHA512, and set the compiler target to
`rhapsody-ppc-cc` (or `rhapsody-i386-cc` on Intel).

PowerPC:

```sh
./Configure no-hw no-sha512 rhapsody-ppc-cc
make depend; make install
```

Intel: same commands, but configure with `rhapsody-i386-cc` instead of
`rhapsody-ppc-cc`:

```sh
./Configure no-hw no-sha512 rhapsody-i386-cc
make depend; make install
```

### OpenSSH install

Grab OpenSSH 3.2.3p1 from
http://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable

```sh
wget http://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-3.2.3p1.tar.gz
tar -xzvf openssh-3.2.3p1.tar.gz
cd openssh-3.2.3p1
./configure
make install
```

This installs `sshd` at `/usr/local/sbin/sshd`.

## Load SSH on boot

Modify `/private/etc/startup/1700_IPServices` and add the following to the
end of it:

```sh
##
# Start up secure login server
##

if [ "${SSHSERVER:=-NO-}" = "-YES-" ]; then
    ConsoleMessage "Starting Secure Login Server"

    if [ ! -f /usr/local/etc/ssh_host_key ]; then
        echo "Generating ssh host RSA1 key..."
        /usr/local/bin/ssh-keygen -t rsa1 -f /usr/local/etc/ssh_host_key -N "" -C "$(hostname)"
    fi
    if [ ! -f /usr/local/etc/ssh_host_rsa_key ]; then
        echo "Generating ssh host RSA key..."
        /usr/local/bin/ssh-keygen -t rsa -f /usr/local/etc/ssh_host_rsa_key -N ""
    fi
    if [ ! -f /usr/local/etc/ssh_host_dsa_key ]; then
        echo "Generating ssh host DSA key..."
        /usr/local/bin/ssh-keygen -t dsa -f /usr/local/etc/ssh_host_dsa_key -N ""
    fi

    /usr/local/sbin/sshd &
fi
```

`make install` puts `sshd_config` and the host keys in `/usr/local/etc`,
which is where this `sshd` looks for them, so the block checks that directory
rather than `/etc`. It names `ssh-keygen` by full path because
`/usr/local/bin` is not on the startup scripts' `PATH`.

Modify `/private/etc/services` and add the following line after port 21 for
ftp:

```text
ssh         22/tcp                          # Secure Shell
```

The startup block only runs when `SSHSERVER` is `-YES-`. Add this to
`/private/etc/hostconfig` (or change it if the key is already present):

```sh
SSHSERVER=-YES-
```

To start the daemon now without rebooting:

```sh
/usr/local/sbin/sshd &
```

Confirm it is listening, then log in over SSH from another machine. A modern
OpenSSH client must offer the algorithms this guest negotiates; see
`vm/SSH CONNECTION.md`.

## Bootstrapping the tree on the guest

With SSH working, the box is ready to build RhapsodiOS. The three steps below
run from a Windows workstation holding the repository; `vm.conf` supplies the
host, credentials, and directory layout (copy `vm/vm.conf.example` first).

`RepoDir` (default `/build/repo`) can start empty: `rbuild bootstrap` builds
every package from the synced source, and a rerun resumes against the
validated packages it has already published.

### 1. Sync `src/` to the guest

```bat
powershell -NoProfile -File vm\sync-src.ps1 -All
```

Lands the whole tree under `RemoteRoot/src` (default `/build/src`) by streaming
a ustar archive over SSH — `scp` drops the connection against this guest. The
script restores execute bits afterwards, which Windows `tar` drops and
`./configure` needs. Re-sync one project later with
`-Path <dir>` (for example `-Path rbuild-1`).

### Rhapsody DR2 only: replace `/bin/pax`

DR2's stock `/bin/pax` (April 1998) sets times through each symlink it
extracts. When an archive stores a symlink ahead of its target — the
`file_cmds` APK ships `usr/bin/cpio -> ../../bin/pax` — that fails with
`Access/modification time set failed` and pax exits 1, although everything
extracted. rbuild extracts APKs with pax, so its tests and the bootstrap fail.
The tree's own pax returns before setting symlink times; build it on the guest
after step 1 and install it over the stock one:

```sh
rm -rf /tmp/paxb && cp -R /build/src/Commands/file_cmds/pax /tmp/paxb
cd /tmp/paxb && cc -O -o pax *.c
test -f /bin/pax.dr2 || cp -p /bin/pax /bin/pax.dr2
/usr/bin/install -c -o root -g wheel -m 555 pax /bin/pax
```

### 2. Build and install `rbuild`

```bat
powershell -NoProfile -File vm\build-src.ps1 -Rbuild
```

Runs `gnumake clean test all` in `/build/src/rbuild-1`, installs the binary to
`ToolsDir/bin/rbuild` (default `/build/tools/bin`), and builds the private
helpers the bootstrap needs: `relpath`, `decomment`, `config`, and the three
`migcom` variants plus the `mig` driver script. On the guest that is:

```sh
cd /build/src/rbuild-1
gnumake CC=/usr/bin/cc clean test all
/usr/bin/install -d /build/tools/bin
/usr/bin/install -c -m 755 rbuild /build/tools/bin/rbuild
```

The helper builds are long and order-sensitive; use `-Rbuild` rather than
reproducing them by hand.

### 3. Bootstrap

```bat
powershell -NoProfile -File vm\build-src.ps1 -Bootstrap
```

This is two passes over the same manifest — thin first, then universal. A
thin-only bootstrap is not enough for ordinary universal builds. On the guest:

```sh
/usr/bin/install -d /build/bootstrap-root /build/repo /build/state
cd /build/src
CONFIG_DIR=/build/tools/bin \
DECOMMENT=/build/tools/bin/decomment \
MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR=/build/tools/libexec \
BISON=/build/bootstrap-root/usr/bin/bison \
BISON_SIMPLE=/build/bootstrap-root/usr/share/bison.simple \
/build/tools/bin/rbuild bootstrap \
    --sysroot /build/bootstrap-root \
    --toolchain /build/src/rbuild-1/toolchains/gcc-darwin-ppc.conf \
    --state /build/state \
    /build/src/BootstrapManifest /build/repo /build/repo
```

Then repeat the identical command with `bootstrap-universal` in place of
`bootstrap`. Both passes write their packages back into `/build/repo`, so the
second pass sees the thin results of the first.

Per-project logs land in `/build/state/logs/<pkg>-<arch>-<target>.log`. The
architecture in those filenames comes from the toolchain profile, which is
`ppc` in the only profile the tree ships.

After this, `-Kernel`, `-KernelDrivers`, and `-World` build the rest; see
`vm/README.md` for the full flag table.
