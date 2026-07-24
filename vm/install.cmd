@echo off
REM Legacy install/boot helper. Prefer:
REM   1) start-hecnet.cmd
REM   2) start-vm.cmd
REM This file kept for CD/floppy install workflows.
qemu -L pc-bios -m 128 ^
-k en-us ^
-rhapsodymouse ^
-hda rhapsody.vmdk ^
-cdrom rhapsody_dr2_x86.iso ^
-fda rhapsody_dr2_x86_InstallationFloppy.img ^
-net nic,model=ne2k_pci,vlan=5 ^
-net socket,udp=0.0.0.0:5001,remote=127.0.0.1:5000 ^
-boot a
