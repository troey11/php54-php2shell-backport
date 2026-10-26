#!/bin/bash
# Many sequential requests in ONE PHP process (FastCGI over a unix socket, no network port).
# Alternates normal requests with requests that end in a fatal error and checks that the
# normal requests start with clean state. Needs cgi-fcgi (package libfcgi0ldbl) in the chroot.
V=$1; B=/t/$V/usr/bin; W=/t/www; S=/tmp/fcgi-$V.sock
cat > $W/fatal.php <<'P'
<?php set_error_handler(function($n,$s){ echo "H:$s\n"; return true; });
set_exception_handler(function($e){ echo "EX\n"; });
undefined_function_xyz();
P
cat > $W/normal.php <<'P'
<?php $prev = set_error_handler(function(){ return true; });
$prevEx = set_exception_handler(function(){});
echo "prev_err=", var_export($prev, true), " prev_ex=", var_export($prevEx, true), " get=", json_encode($_GET), " ok\n";
P
rm -f $S
PHP_FCGI_CHILDREN=0 PHP_FCGI_MAX_REQUESTS=10000 $B/php5-cgi -n -d display_errors=1 -d html_errors=0 -b $S >/tmp/fcgi-$V.err 2>&1 &
PID=$!; sleep 1
req() { REQUEST_METHOD=GET SCRIPT_FILENAME=$W/$1 QUERY_STRING="$2" REDIRECT_STATUS=1 GATEWAY_INTERFACE=CGI/1.1 SERVER_PROTOCOL=HTTP/1.1 \
        cgi-fcgi -bind -connect $S 2>&1 | sed '1,/^\r\?$/d'; }
okN=0; badN=0; fatalN=0
for i in $(seq 1 200); do
  if [ $((i % 2)) -eq 0 ]; then
    out=$(req fatal.php "i=$i"); echo "$out" | grep -q "Fatal error" && fatalN=$((fatalN+1))
  else
    out=$(req normal.php "i=$i")
    if [ "$out" = "prev_err=NULL prev_ex=NULL get={\"i\":\"$i\"} ok" ]; then okN=$((okN+1)); else badN=$((badN+1)); [ $badN -le 3 ] && echo "  NOT CLEAN #$i: $(echo "$out" | tr '\n' '|' | cut -c1-160)"; fi
  fi
done
alive=$(kill -0 $PID 2>/dev/null && echo alive || echo DEAD)
echo "[$V] normal_ok=$okN  not_clean=$badN  fatal_seen=$fatalN/100  php_process=$alive"
kill $PID 2>/dev/null; wait $PID 2>/dev/null; rm -f $S
