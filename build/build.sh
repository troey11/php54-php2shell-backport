#!/bin/bash
# Build patched php5 .deb packages for Ubuntu 12.10 (quantal) inside an isolated chroot.
#
# Nothing outside $BASE is modified. The host's own PHP/Apache are not touched.
# Tested on: Ubuntu 12.10 i386 host (kernel 3.5), php5 5.4.6-1ubuntu1.8.
#
# Usage (as root):  build/build.sh
# Env:  BASE=/srv/php-build  ARCH=i386  PARALLEL=2
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH=$(cd "$HERE/../patches" && pwd)/CVE-2026-109618-109619-backport-5.4.6.patch
BASE=${BASE:-/srv/php-build}
ARCH=${ARCH:-i386}
PARALLEL=${PARALLEL:-2}
MIRROR=http://old-releases.ubuntu.com/ubuntu/
SRCVER=5.4.6-1ubuntu1.8
NEWVER=${SRCVER}+cve2026.1
R=$BASE/root
export CHROOT_DIR=$R
CH="$HERE/chroot.sh"

mkdir -p "$BASE/tools" "$BASE/dl"

echo "== 1. debootstrap (extracted locally, not installed on the host)"
if [ ! -x "$BASE/tools/usr/sbin/debootstrap" ]; then
  cd "$BASE/dl"
  F=$(wget -q -O - "$MIRROR/pool/main/d/debootstrap/" | grep -oE 'debootstrap_1\.0\.4[0-9][^"]*_all\.deb' | sort -uV | tail -1)
  wget -q "$MIRROR/pool/main/d/debootstrap/$F"
  dpkg-deb -x "$F" "$BASE/tools"
fi

echo "== 2. Ubuntu 12.10 $ARCH chroot at $R"
if [ ! -f "$R/etc/lsb-release" ]; then
  DEBOOTSTRAP_DIR=$BASE/tools/usr/share/debootstrap nice -n 19 ionice -c3 \
    "$BASE/tools/usr/sbin/debootstrap" --arch="$ARCH" --variant=buildd --extractor=dpkg-deb \
    quantal "$R" "$MIRROR" > "$BASE/debootstrap.log" 2>&1
fi
cat > "$R/etc/apt/sources.list" <<S
deb $MIRROR quantal main restricted universe
deb $MIRROR quantal-updates main restricted universe
deb $MIRROR quantal-security main restricted universe
deb-src $MIRROR quantal main restricted universe
deb-src $MIRROR quantal-updates main restricted universe
deb-src $MIRROR quantal-security main restricted universe
S
# never start services inside the chroot
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod +x "$R/usr/sbin/policy-rc.d"

echo "== 3. build dependencies + source php5=$SRCVER"
"$CH" "apt-get update -q && apt-get install -y -q --no-install-recommends quilt fakeroot devscripts dpkg-dev \
  && apt-get build-dep -y -q php5=$SRCVER && mkdir -p /build && cd /build \
  && ( [ -d php5-5.4.6 ] || apt-get source -q php5=$SRCVER )" > "$BASE/deps.log" 2>&1

echo "== 4. add patch as the last quilt patch + bump version"
cp "$PATCH" "$R/build/php5-5.4.6/debian/patches/"
grep -qx "$(basename "$PATCH")" "$R/build/php5-5.4.6/debian/patches/series" \
  || echo "$(basename "$PATCH")" >> "$R/build/php5-5.4.6/debian/patches/series"
"$CH" "cd /build/php5-5.4.6 && export QUILT_PATCHES=debian/patches && quilt push -a -q && quilt pop -a -q \
  && ( head -1 debian/changelog | grep -q '$NEWVER' || DEBEMAIL=builder@localhost DEBFULLNAME=builder \
       dch -v $NEWVER -D quantal-security 'Backport fixes for CVE-2026-109618 / CVE-2026-109619 (php2shell).' )"

echo "== 5. dpkg-buildpackage (tests skipped here; see tests/run-regression.sh)"
"$CH" "cd /build/php5-5.4.6 && DEB_BUILD_OPTIONS='nocheck parallel=$PARALLEL' dpkg-buildpackage -b -uc -us" \
  > "$BASE/build.log" 2>&1
ls -1 "$R/build/"*"_${NEWVER}_"*.deb
echo "Done. Packages are in $R/build/"
