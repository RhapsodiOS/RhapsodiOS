@echo off
REM Legacy boot-with-nic.flp helper. Prefer start-hecnet.cmd then start-vm.cmd.
REM Use this if the guest needs nic.flp once for NE2k drivers.
qemu -L pc-bios -m 128 ^
-k en-us ^
-rhapsodymouse ^
-hda rhapsody.vmdk ^
-cdrom rhapsody_dr2_x86.iso ^
-fda nic.flp ^
-boot c
