#!/bin/bash
# STEP 1 — Pre-check. Read-only: changes nothing. Saves a baseline to $WORK/baseline.
set -u
. "$(dirname "$0")/config.sh"
BL=$WORK/baseline; mkdir -p "$BL"
ok=1; fail(){ echo "  [FAIL] $*"; ok=0; }

echo "== 1. Rollback set present and intact"
( cd "$ROLLBACK_DIR" && sha256sum -c --quiet SHA256SUMS ) && echo "  OK checksums" || fail "rollback checksums ($ROLLBACK_DIR)"
[ -x "$ROLLBACK_DIR/ROLLBACK.sh" ] && echo "  OK ROLLBACK.sh" || fail "ROLLBACK.sh missing"

echo "== 2. Patched packages present"
L=""; for p in $PACKAGES; do f=$DEBS/${p}_${NEWVER}_${ARCH}.deb; [ -f "$f" ] || fail "missing $f"; L="$L $f"; done

echo "== 3. Installed versions"
dpkg-query -W -f='  ${Package} ${Version}\n' $PACKAGES | tee "$BL/versions.txt"
grep -q "+cve2026" "$BL/versions.txt" && fail "patched version already installed?"

echo "== 4. dpkg simulation"
dpkg --dry-run -i $L >/dev/null 2>"$BL/dryrun.err" && echo "  OK dry-run" || { fail "dry-run"; cat "$BL/dryrun.err"; }

echo "== 5. Apache configtest"
apache2ctl configtest 2>&1 | grep -q "Syntax OK" && echo "  OK" || fail "configtest"

echo "== 6. Baseline PHP modules"
php -m > "$BL/php-m.txt"; echo "  $(grep -c . "$BL/php-m.txt") CLI modules"

echo "== 7. Baseline HTTP status of the apps"
: > "$BL/http.txt"
for u in $APPS; do echo "$u $(curl -s -o /dev/null -m 20 -w '%{http_code}' "$BASE_URL/$u/")" >> "$BL/http.txt"; done
sed 's/^/  /' "$BL/http.txt"

echo "== 8. error.log position"
wc -l < "$APACHE_ERROR_LOG" > "$BL/errorlog.lines"; echo "  lines: $(cat "$BL/errorlog.lines")"

echo "== 9. Disk and load"; df -h / | tail -1 | sed 's/^/  /'; uptime | sed 's/^/  /'

[ $ok = 1 ] && echo "PRECHECK: ALL OK — you may run 10-install.sh" || echo "PRECHECK: FAILED — do NOT continue"
