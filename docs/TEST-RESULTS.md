# Test results (reference run, 2026-10-26)

Ubuntu 12.10 i386, build in a debootstrap chroot at `nice 19` / `ionice idle`.
"Original" = the stock `5.4.6-1ubuntu1.8` binary, repacked from an installed system and
verified byte-identical to the installed `/usr/bin/php5`. "Patched" = `5.4.6-1ubuntu1.8+cve2026.1`.

## PHP test suite

`run-tests.php` on `Zend/tests`, `tests/`, `ext/session/tests`, `ext/standard/tests`,
run sequentially, each in its own copy of the test tree.

| | Original | Patched |
|---|---|---|
| Tests | 5,609 | 5,609 |
| Passed | 5,046 | 5,038 |
| Failed | 5 | 13 |
| Skipped | 544 | 544 |
| Expected fail | 14 | 14 |

Failing in both (environment, not the patch): `general_functions/proc_nice_basic`,
`network/http-stream`, `php_ini_loaded_file`, `tests/security/open_basedir_readlink`.

New failures in the patched build, all intended:
- `ext/session/tests/rfc1867.phpt`, `rfc1867_inter`, `rfc1867_sid_cookie`, `rfc1867_sid_get`,
  `rfc1867_sid_get_2`, `rfc1867_sid_invalid`, `rfc1867_sid_only_cookie`, `rfc1867_sid_post`:
  these set `session.upload_progress.enabled=1` and expect a progress array; the patch disables
  the feature, so the result is `NULL`.
- `tests/lang/bug45392.phpt`: deliberately exhausts `memory_limit`; the message is identical
  but preceded by one extra blank line because OOM now exits through the new path.

Failing only in the original: `ext/standard/tests/http/bug60570.phpt` (network test, flaky).

> A first attempt ran both suites at the same time in the same tree. Because `run-tests.php`
> writes `.php/.out/.diff` files next to each test and shares `/tmp`, the results were
> corrupted (hundreds of random differences). Always run them sequentially in separate copies.

## Targeted tests (`tests/targeted.sh`, `tests/fcgi_seq.sh`)

| Test | Original | Patched |
|---|---|---|
| Normal upload: 2 fields + file + extra header | `POST={"a":"1","b":"hello world"}`, file md5 | identical |
| 300-field form | all fields | identical |
| 12 parts, `max_multipart_body_parts=7` | 12 fields accepted | 7 fields + warning `Multipart body parts limit exceeded 7` |
| `session.upload_progress.enabled=1` | progress key in `$_SESSION` | empty |
| OOM, `memory_limit=8M` | message on stdout, exit 255 | message on stderr, exit 1 |
| `memory_limit=-1`, allocate 64 MB | OK | OK |
| 200 FastCGI requests in one process, half ending in a fatal error | 100/100 clean, process alive | 100/100 clean, process alive |

## Notes for deployment

- `deploy/20-verify.sh` proves the patched module is loaded by Apache: the INI entry
  `max_multipart_body_parts` only exists in the patched build.
- One `apr_socket_accept: Bad file descriptor` line in the error log at a graceful restart is
  normal on Apache 2.2 and is not caused by the patch.
