#!/bin/sh
# Run a command inside the build chroot at low CPU/IO priority.
# /proc and /dev/pts are mounted only while the command runs.
# Usage: build/chroot.sh "<command>"
R=${CHROOT_DIR:-/srv/php-build/root}
mountpoint -q "$R/proc"    || mount -t proc proc "$R/proc"
mountpoint -q "$R/dev/pts" || mount -t devpts devpts "$R/dev/pts"
nice -n 19 ionice -c3 chroot "$R" /usr/bin/env -i HOME=/root \
  PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C DEBIAN_FRONTEND=noninteractive \
  /bin/bash -c "$*"
RC=$?
umount "$R/dev/pts" 2>/dev/null; umount "$R/proc" 2>/dev/null
exit $RC
