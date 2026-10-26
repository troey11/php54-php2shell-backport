#!/bin/bash
# Targeted tests for the behaviour changed by the CVE-2026-109618/109619 backport.
# Run INSIDE the build chroot. Argument: name of a directory under /t holding an
# extracted package set, e.g. /t/orig and /t/patched (see tests/README.md).
V=$1; B=/t/$V/usr/bin; W=/t/www; mkdir -p $W
CLI="$B/php5 -n"; CGI="$B/php5-cgi -n"

echo "##### [$V] 1. OOM (memory_limit=8M, allocate 64MB)"
$CLI -d memory_limit=8M -d display_errors=1 -r 'echo "start\n"; $x = str_repeat("x", 64*1024*1024); echo "end\n";' > /tmp/o 2>/tmp/e; rc=$?
echo "exit=$rc"; echo "stdout: $(tr '\n' '|' < /tmp/o)"; echo "stderr: $(tr '\n' '|' < /tmp/e | cut -c1-160)"

echo "##### [$V] 1b. memory_limit=-1, allocate 64MB (must work)"
$CLI -d memory_limit=-1 -r '$x = str_repeat("x", 64*1024*1024); echo strlen($x), "\n";'; echo "exit=$?"

cat > $W/dump.php <<'P'
<?php
ksort($_POST); echo "POST=", json_encode($_POST), "\n";
foreach ($_FILES as $k => $f) { echo "FILE $k name=", $f['name'], " type=", $f['type'], " size=", $f['size'], " err=", $f['error'], " md5=", md5_file($f['tmp_name']), "\n"; }
P
cgi_post() { # $1=body file  $2=extra -d options  $3=script (default dump.php)
  local len; len=$(stat -c %s "$1")
  REDIRECT_STATUS=1 GATEWAY_INTERFACE=CGI/1.1 REQUEST_METHOD=POST SCRIPT_FILENAME=$W/${3:-dump.php} \
  CONTENT_TYPE="multipart/form-data; boundary=XyZb" CONTENT_LENGTH=$len \
  $CGI -d display_errors=0 -d log_errors=1 -d error_log=/dev/stderr -d html_errors=0 $2 < "$1" 2>&1 \
    | grep -v -iE "^(X-Powered-By|Content-type|Set-Cookie|Expires|Cache-Control|Pragma):" | sed '/^\s*$/d'
}
mk() { printf -- "--XyZb\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" "$1" "$2"; }

echo "##### [$V] 2. Normal upload (fields + file + extra Content-Transfer-Encoding header)"
{ mk a 1; mk b "hello world"
  printf -- "--XyZb\r\nContent-Disposition: form-data; name=\"f\"; filename=\"test.txt\"\r\nContent-Type: text/plain\r\nContent-Transfer-Encoding: binary\r\n\r\ntest file content 12345\r\n"
  printf -- "--XyZb--\r\n"; } > /tmp/b2
cgi_post /tmp/b2 ""

echo "##### [$V] 3. Multipart part limit (max_input_vars=100, max_multipart_body_parts=7, send 12 parts)"
{ for i in $(seq 1 12); do mk "v$i" "$i"; done; printf -- "--XyZb--\r\n"; } > /tmp/b3
cgi_post /tmp/b3 "-d max_input_vars=100 -d max_multipart_body_parts=7"

echo "##### [$V] 3b. Large normal form (300 fields, max_input_vars=10000)"
{ for i in $(seq 1 300); do mk "v$i" "$i"; done; printf -- "--XyZb--\r\n"; } > /tmp/b3b
cgi_post /tmp/b3b "-d max_input_vars=10000 -d max_file_uploads=100" | sed -E 's/POST=(.{60}).*/POST=\1.../'

echo "##### [$V] 4. session.upload_progress.enabled=1 (forced on)"
cat > $W/prog.php <<'P'
<?php session_start(); echo "SESSION=", json_encode(array_keys($_SESSION)), "\n";
P
mkdir -p /tmp/sess; rm -f /tmp/sess/*
{ mk PHP_SESSION_UPLOAD_PROGRESS u1
  printf -- "--XyZb\r\nContent-Disposition: form-data; name=\"f\"; filename=\"p.txt\"\r\nContent-Type: text/plain\r\n\r\n%s\r\n" "$(head -c 20000 /dev/zero | tr '\0' a)"
  printf -- "--XyZb--\r\n"; } > /tmp/b4
HTTP_COOKIE="PHPSESSID=abc123" cgi_post /tmp/b4 "-d session.upload_progress.enabled=1 -d session.upload_progress.cleanup=0 -d session.save_path=/tmp/sess" prog.php
