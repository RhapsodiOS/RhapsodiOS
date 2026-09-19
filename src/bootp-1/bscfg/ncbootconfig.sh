#!/bin/sh
#
# bscfg.sh
# - NC boot server configuration script

#
# copy the default configuration file
# 
cp bootptab.example /etc/bootptab
cp bootpd /usr/sbin

#
# configure the NC IP ranges: the format is one ip address per line, the start and end ip addresses
# appear on two consecutive lines
#
( cat << EOT 
17.202.40.1
17.202.40.10
17.202.42.1
17.202.42.10
EOT
) | ./ncipranges /dev/stdin

niutil -create . /config/MacNC/BootServer || exit 2
niload -r /config/MacNC/BootServer . << EOT
{
  "name" = ( "BootServer" );
  "oam_group_name" = ( "Mac NC Group" );
  "oam_user_format" = ( "Mac NC #%d" );
  "hostname_format" = ( "macnc%03d" );
  "default_bootfile" = ( "Mac OS ROM" );
  "default_bootdir" = ( "/private/tftpboot" );
  "disk_volumes" = ( "uw1", "uw2", "uw3" );
  "shared_system_file" = ( "Shared" );
  "shared_system_volume" = ( "uw1" );
  "private_system_file" = ( "Private" );
  "private_system_volume" = ( "uw1" );
  "shadow_both" = ( "_shadow_both" );
}
EOT
