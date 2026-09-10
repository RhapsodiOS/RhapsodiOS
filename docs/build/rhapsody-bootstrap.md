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

Disable hardware acceleration and SHA512, and set the compiler target to
`rhapsody-ppc-cc` (or `rhapsody-intel-cc` on Intel).

PowerPC:

```sh
./Configure no-hw no-sha512 rhapsody-ppc-cc
make depend; make install
```

Intel: same commands, but configure with `rhapsody-intel-cc` instead of
`rhapsody-ppc-cc`:

```sh
./Configure no-hw no-sha512 rhapsody-intel-cc
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

    if [ ! -f /etc/ssh_host_key ]; then
        echo "Generating ssh host RSA key..."
        ssh-keygen -f /etc/ssh_host_key -N "" -C "$(hostname)"
    fi
    if [ ! -f /etc/ssh_host_dsa_key ]; then
        echo "Generating ssh host DSA key..."
        ssh-keygen -d -f /etc/ssh_host_dsa_key -N "" -C "$(hostname)"
    fi

    /usr/local/sbin/sshd &
fi
```

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
