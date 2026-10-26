#!/bin/bash
# STEP 3 — Verify after install. Read-only (a temporary probe file is removed immediately).
set -u
. "$(dirname "$0")/config.sh"
BL=$WORK/baseline; ok=1; fail(){ echo "  [FAIL] $*"; ok=0; }

echo "== 1. PHP version loaded by Apache (mod_php)"
T=$DOCROOT/zz_cve_verify_$$.php
echo '<?php echo PHP_VERSION," | upload_progress=",var_export(ini_get("session.upload_progress.enabled"),1)," | memory_limit=",ini_get("memory_limit")," | max_multipart_body_parts=",var_export(ini_get("max_multipart_body_parts"),1);' > "$T"
R=$(curl -s -m 20 "$BASE_URL/$(basename "$T")"); rm -f "$T"
echo "  $R"
# The INI entry max_multipart_body_parts only exists in the patched build.
echo "$R" | grep -q "max_multipart_body_parts='-1'" && echo "  OK patched module is active" || fail "patched module not active in Apache"

echo "== 2. App HTTP status vs baseline"
while read -r u before; do
  now=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$BASE_URL/$u/")
  [ "$now" = "$before" ] && echo "  OK   $u $now" || { echo "  DIFF $u before=$before now=$now"; ok=0; }
done < "$BL/http.txt"

echo "== 3. New error.log lines since install"
start=$(cat "$BL/errorlog.lines")
tail -n +$((start+1)) "$APACHE_ERROR_LOG" | grep -iE "PHP (Fatal|Parse)|segfault|exit signal|Multipart body parts limit|exhausted" | tail -15
n=$(tail -n +$((start+1)) "$APACHE_ERROR_LOG" | grep -ciE "segfault|exit signal")
[ "$n" -eq 0 ] && echo "  OK no segfault / exit signal" || fail "$n segfault/exit signal lines"
echo "  note: one 'apr_socket_accept: Bad file descriptor' line at graceful restart is normal on Apache 2.2"

[ $ok = 1 ] && echo "VERIFY: OK — keep watching error.log for 15-30 minutes" || echo "VERIFY: PROBLEMS — consider 90-rollback.sh now"
