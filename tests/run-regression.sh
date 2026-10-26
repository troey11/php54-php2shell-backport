#!/bin/bash
# Run PHP's own test suite against the ORIGINAL and the PATCHED binaries and diff the results.
# Run on the build host (as root) after build/build.sh.
#
# IMPORTANT: the two runs must be SEQUENTIAL and each must use its own copy of the test
# tree and its own TMPDIR. run-tests.php writes .php/.out/.diff files next to every .phpt
# and shares /tmp session files; running both at once in one tree corrupts the results.
#
# Needs: ORIG_DEBS = dir with original php5-cli/php5-common(/php5-cgi) .debs
#        (e.g. the rollback set from backup/repack-installed.sh; php5-cgi can be fetched
#         from old-releases.ubuntu.com if it is not installed on the host)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${BASE:-/srv/php-build}; R=$BASE/root
ORIG_DEBS=${ORIG_DEBS:?set ORIG_DEBS to the directory with the original .debs}
NEWVER=5.4.6-1ubuntu1.8+cve2026.1; ARCH=${ARCH:-i386}
export CHROOT_DIR=$R; CH="$HERE/../build/chroot.sh"

mkdir -p "$R/t/orig" "$R/t/patched"
for d in "$ORIG_DEBS"/php5-cli_*.deb "$ORIG_DEBS"/php5-common_*.deb "$ORIG_DEBS"/php5-cgi_*.deb; do
  [ -f "$d" ] && dpkg-deb -x "$d" "$R/t/orig"; done
for p in php5-cli php5-common php5-cgi; do dpkg-deb -x "$R/build/${p}_${NEWVER}_${ARCH}.deb" "$R/t/patched"; done
cp "$HERE/targeted.sh" "$HERE/fcgi_seq.sh" "$R/t/"

for v in orig patched; do
  rm -rf "$R/build/tt-$v"; mkdir -p "$R/build/tt-$v/ext"
  ( cd "$R/build/php5-5.4.6" && cp -a run-tests.php Zend tests "$R/build/tt-$v/" && cp -a ext/session ext/standard "$R/build/tt-$v/ext/" )
done

for v in orig patched; do   # sequential on purpose
  "$CH" "mkdir -p /tmp/tt-$v && cd /build/tt-$v && TMPDIR=/tmp/tt-$v NO_INTERACTION=1 REPORT_EXIT_STATUS=0 \
    TEST_PHP_EXECUTABLE=/t/$v/usr/bin/php5 TEST_PHP_CGI_EXECUTABLE=/t/$v/usr/bin/php5-cgi \
    /t/orig/usr/bin/php5 -n run-tests.php -q --set-timeout 60 -s /t/result-$v.txt \
    Zend/tests tests ext/session/tests ext/standard/tests > /t/run-$v.log 2>&1" || true
done

cd "$R/t"
for v in orig patched; do
  echo "== $v"; grep -E "^(Number of tests|Tests (skipped|failed|passed)|Expected fail)" "result-$v.txt"
  sed -n "/^FAILED TEST SUMMARY/,/^====/p" "result-$v.txt" | grep -oE "\[[^]]+\]" | sort -u > "fail-$v.txt"
done
echo "== FAIL in both (pre-existing / environment)"; comm -12 fail-orig.txt fail-patched.txt
echo "== NEW FAIL only in patched";                  comm -13 fail-orig.txt fail-patched.txt
echo "== FAIL only in orig";                         comm -23 fail-orig.txt fail-patched.txt

echo "== targeted tests"
"$CH" "apt-get install -y -q libfcgi0ldbl >/dev/null 2>&1; for v in orig patched; do bash /t/targeted.sh \$v; bash /t/fcgi_seq.sh \$v; done"
