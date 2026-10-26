#!/bin/bash
# Create a rollback set from the PHP packages CURRENTLY installed on this host:
# rebuilds each installed package into a .deb from the files on disk
# (same idea as dpkg-repack, which old hosts often do not have), plus a tar
# snapshot of the PHP/Apache configuration and a ROLLBACK.sh.
#
# Usage (as root): backup/repack-installed.sh [/root/php-rollback-<timestamp>]
set -euo pipefail
B=${1:-/root/php-rollback-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$B/debs"; cd "$B"
PKGS=$(dpkg -l | awk '/^ii/ && ($2 ~ /^php5/ || $2 ~ /^libapache2-mod-php5/) {print $2}')
dpkg -l | awk '/^ii/' | grep -E " (php5|libapache2-mod-php5)" > dpkg-versions.txt

for P in $PKGS; do
  W=$B/work/$P; mkdir -p "$W/DEBIAN"
  awk -v p="$P" 'BEGIN{RS="";FS="\n"} {for(i=1;i<=NF;i++) if($i=="Package: " p){print; exit}}' /var/lib/dpkg/status \
    | grep -vE "^(Status|Config-Version):" > "$W/DEBIAN/control"
  for s in preinst postinst prerm postrm config templates conffiles; do
    [ -f "/var/lib/dpkg/info/$P.$s" ] && cp -a "/var/lib/dpkg/info/$P.$s" "$W/DEBIAN/$s"
  done
  dpkg -L "$P" | while read -r f; do [ -e "$f" ] && { [ ! -d "$f" ] || [ -L "$f" ]; } && echo "${f#/}"; done > "$W.list"
  (cd / && tar cf - -T "$W.list" --no-recursion 2>/dev/null) | (cd "$W" && tar xf -)
  dpkg-deb -b "$W" debs/ >/dev/null 2>&1 && echo "repacked $P"
done
rm -rf work

tar czf files-snapshot.tgz /etc/php5 /etc/apache2 /usr/lib/php5 /usr/lib/apache2/modules/libphp5.so /usr/bin/php5 2>/dev/null || true

cat > ROLLBACK.sh <<'R'
#!/bin/sh
# Restore the PHP packages and config exactly as they were when this backup was made.
cd "$(dirname "$0")"
export UCF_FORCE_CONFFOLD=1 DEBIAN_FRONTEND=noninteractive
dpkg -i debs/*.deb
tar xzf files-snapshot.tgz -C /
apache2ctl configtest && apache2ctl graceful
php -v | head -1
R
chmod +x ROLLBACK.sh
sha256sum debs/*.deb files-snapshot.tgz > SHA256SUMS

# sanity check: the repacked mod_php must be byte-identical to the running one
T=$(mktemp -d); dpkg-deb -x debs/libapache2-mod-php5_*.deb "$T"
cmp -s "$T/usr/lib/apache2/modules/libphp5.so" /usr/lib/apache2/modules/libphp5.so \
  && echo "OK: repacked libphp5.so is identical to the installed one" \
  || echo "WARNING: repacked libphp5.so differs from the installed one"
rm -rf "$T"
echo "BACKUP=$B   (copy this directory off the host as well)"
