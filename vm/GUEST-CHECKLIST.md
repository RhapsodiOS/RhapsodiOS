# Guest checklist (Rhapsody console)

Use this after `start-vm.cmd` reaches a login prompt. Goal: SSH from the Windows host.

## 1. Network interface

- [ ] NE2000/PCI Ethernet is present (DriverKit / network prefs, or `ifconfig -a` if available).
- [ ] Interface has an address on the **VMnet8** subnet (same LAN as the host VMnet8 adapter).
- [ ] Default route / netmask look sane for that subnet.

If there is no NIC at all, shut down and try legacy `install2.cmd` with `nic.flp` once, then return to `start-vm.cmd`.

## 2. Connectivity

- [ ] Ping the host's VMnet8 address (or the VMnet gateway).
- [ ] From the host, ping the guest IP.

## 3. SSH server

OpenSSH is intended to start when `SSHSERVER=-YES-` in `/etc/hostconfig` (see `files-5` sources; startup script `1700_IPServices`).

- [ ] Confirm `/etc/hostconfig` has `SSHSERVER=-YES-`.
- [ ] Confirm `sshd` is running (or start `/usr/sbin/sshd` once for testing).
- [ ] If prompted, allow host key generation under `/etc/ssh_host_key` / `/etc/ssh_host_dsa_key`.

## 4. Login from host

- [ ] From Windows: `ssh <user>@<guest-ip>`
- [ ] Run a trivial remote command (`hostname`, `uname`, or `ls`).

## 5. Optional RSH (after SSH works)

- [ ] Uncomment `shell` / `login` in `/etc/inetd.conf` if you need RSH.
- [ ] Restart inetd.
- [ ] Test `rsh` / `rlogin` from the host.

Phase 1 success = steps 1–4. RSH is optional.
