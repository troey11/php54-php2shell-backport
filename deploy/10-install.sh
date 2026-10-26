#!/bin/bash
# STEP 2 — Install the patched packages. Run only after 00-precheck.sh reported ALL OK.
# Package postinst would force-reload Apache; that is blocked temporarily (policy-rc.d)
# so exactly one graceful reload happens, after all checks pass.
set -u
. "$(dirname "$0")/config.sh"
BL=$WORK/baseline
[ -f "$BL/versions.txt" ] || { echo "Run 00-precheck.sh first"; exit 1; }
L=""; for p in $PACKAGES; do L="$L $DEBS/${p}_${NEWVER}_${ARCH}.deb"; done

echo "== 1. Block automatic service restarts"
[ -e /usr/sbin/policy-rc.d ] && { echo "/usr/sbin/policy-rc.d already exists — stop and check manually"; exit 1; }
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d

echo "== 2. dpkg -i (keep local php.ini)"
UCF_FORCE_CONFFOLD=1 DEBIAN_FRONTEND=noninteractive dpkg --force-confold -i $L 2>&1 \
  | tee "$WORK/dpkg-install.log" | grep -vE "^(Selecting|Preparing|Unpacking|\(Reading)"
RC=${PIPESTATUS[0]}
rm -f /usr/sbin/policy-rc.d
[ "$RC" -eq 0 ] || { echo "dpkg FAILED (rc=$RC). Apache still runs the old module from memory. Run 90-rollback.sh."; exit 1; }

echo "== 3. Checks before reload"
dpkg-query -W -f='  ${Package} ${Version}\n' $PACKAGES
php -v | head -1
php -m > "$WORK/php-m.after.txt"
diff -q "$BL/php-m.txt" "$WORK/php-m.after.txt" >/dev/null && echo "  OK same PHP modules as baseline" \
  || { diff "$BL/php-m.txt" "$WORK/php-m.after.txt"; echo "STOP — not reloaded. Run 90-rollback.sh."; exit 1; }
apache2ctl configtest 2>&1 | grep -q "Syntax OK" || { echo "configtest FAILED — not reloaded. Run 90-rollback.sh."; exit 1; }

echo "== 4. Graceful reload (in-flight requests are not cut)"
apache2ctl graceful && echo "  graceful OK"
sleep 3
echo "Next: 20-verify.sh"
