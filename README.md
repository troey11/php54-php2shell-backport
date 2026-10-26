# php2shell backport for PHP 5.4 on Ubuntu 12.10

Unofficial backport of the fixes for **CVE-2026-109618** and **CVE-2026-109619** ("php2shell")
to the Ubuntu 12.10 (quantal) package **php5 5.4.6-1ubuntu1.8**, plus the scripts used to
build, test, deploy and roll it back on an Apache 2.2 + mod_php host.

> **This is not an official PHP or Ubuntu release.** PHP 5.4 has been end-of-life since 2015
> and Ubuntu 12.10 since 16 May 2014. This patch closes only these two CVEs; every other
> vulnerability found since then is still present. The only complete fix is to move to a
> supported PHP version on a supported OS. Use this to buy time, not as a destination.

## The vulnerabilities

| CVE | CVSS | Summary |
|---|---|---|
| CVE-2026-109618 ([GHSA-w8hw-w9fx-j79w](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)) | 9.2 | Memory corruption when an out-of-memory error `longjmp()`s out of a partially initialised request (e.g. multipart upload parsing) |
| CVE-2026-109619 ([GHSA-6wmf-4rv5-p3rp](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)) | 9.2 | Request-owned global state survives a fatal error and is reused by the next request in the same worker |

Fixed upstream in PHP 8.5.12, 8.4.27, 8.3.36 and 8.2.35; the PHP team published minimal
backports for 7.4, 8.0 and 8.1. Advisory summary:
[CERT-EU 2026-018](https://cert.europa.eu/publications/security-advisories/2026-018).

## What the patch changes

| File | Change |
|---|---|
| `Zend/zend_alloc.c`, `.h` | Memory-limit / integer-overflow fatals no longer `longjmp()`; error is printed to stderr and the process exits with `_exit(1)` |
| `Zend/zend_execute_API.c` | Reset error/exception handlers, autoload state, error handling mode at executor shutdown |
| `main/main.c` | Superglobal pointers and `modules_activated` reset at shutdown; new INI `max_multipart_body_parts` (default `-1` = `max_input_vars + max_file_uploads`) |
| `main/SAPI.c` | Request strings set to `NULL` after being freed |
| `main/rfc1867.c` | Multipart: keep only `Content-Disposition`/`Content-Type` headers, ignore duplicates, enforce the part limit |
| `ext/session/session.c` | Session upload progress disabled in code |
| `Zend/zend_llist.c` | List head/tail reset on clean |

Derived from the [vperetti 5.4.45 backport](https://github.com/vperetti/php-cve-2026-109618-109619-backports),
adapted to Ubuntu's 5.4.6 source (74 Ubuntu patches applied first). 26 of 27 hunks applied
as-is; the `rfc1867.c` header-parsing hunk was **rewritten by hand** because 5.4.6 uses an
older algorithm. See [docs/REVIEW.md](docs/REVIEW.md).

### Behaviour changes your applications may notice
1. A request that really exhausts memory now ends with a dropped connection (the Apache
   child exits; the message goes to the Apache error log) instead of a PHP error page.
2. A multipart request with more than `max_input_vars + max_file_uploads` parts is cut at
   that limit and logs `Multipart body parts limit exceeded`.
3. `session.upload_progress` no longer works, even if enabled in php.ini.

## Repository layout

```
patches/    the quilt patch (DEP-3 header) for php5 5.4.6-1ubuntu1.8
build/      build.sh: Ubuntu 12.10 chroot via debootstrap -> apt-get source -> patch -> .debs
backup/     repack-installed.sh: rollback set from the packages currently installed
deploy/     config.sh + 00-precheck / 10-install / 20-verify / 90-rollback
mitigation/ Apache config to apply immediately (memory_limit / upload_progress)
tests/      run-regression.sh (PHP test suite, original vs patched), targeted tests
docs/       REVIEW.md (patch review), TEST-RESULTS.md (results of the reference run)
```

## Usage

All steps run as root on the target host (Ubuntu 12.10, Apache 2.2 + `libapache2-mod-php5`).
Read every script before running it.

```bash
# 0. Immediate mitigation (no package change)
cp mitigation/php-cve-2026-109618-109619.conf /etc/apache2/conf.d/
apache2ctl configtest && apache2ctl graceful

# 1. Rollback set of what is installed now (copy it off the host too)
backup/repack-installed.sh /root/php-rollback-$(date +%Y%m%d)

# 2. Build in an isolated chroot (host PHP/Apache untouched)
build/build.sh

# 3. Regression + targeted tests, original vs patched
ORIG_DEBS=/root/php-rollback-YYYYMMDD/debs tests/run-regression.sh

# 4. Deploy (edit deploy/config.sh first: PACKAGES, APPS, ROLLBACK_DIR, BASE_URL)
deploy/00-precheck.sh      # read-only; must end with ALL OK
deploy/10-install.sh       # dpkg -i, checks, then one apache2ctl graceful
deploy/20-verify.sh        # module version via Apache, app HTTP status vs baseline, error.log
# if anything is wrong:
deploy/90-rollback.sh
```

Only install the packages that are already installed on the host. Extensions built from
other source packages (e.g. `php5-imap`, `php5-mcrypt`) keep working: they depend only on
`phpapi-20100525+lfs`, which the patched build still provides.

## Reference results

Built and tested for Ubuntu 12.10 i386 with Apache 2.2 prefork + mod_php.

- PHP test suite (5,609 tests): original 5 FAIL, patched 13 FAIL. The 8 extra are the
  `ext/session/tests/rfc1867*` upload-progress tests (feature disabled on purpose) plus
  `tests/lang/bug45392.phpt` (OOM message has one extra blank line). Details in
  [docs/TEST-RESULTS.md](docs/TEST-RESULTS.md).
- Targeted tests: normal uploads and a 300-field form give byte-identical `$_POST`/`$_FILES`;
  200 sequential FastCGI requests (half ending in a fatal error) stay clean.

Only i386 was built and tested. amd64 should work with `ARCH=amd64` but has not been tested.

## Limitations

- Tested with CLI and CGI in a chroot, and under Apache mod_php. No public exploit was
  run against it.
- The patch is a minimal backport. It does not include the VM-level integer-overflow
  hardening from upstream (DoS hardening, not the RCE path).
- No warranty. Review the diff in `patches/` before building.

## Licensing

- Scripts and documentation: MIT, see [LICENSE](LICENSE).
- The patch modifies PHP source and is distributed under the PHP License v3.01, the license
  of the code it changes. It is derived from the upstream PHP security fixes and from the
  vperetti backport, which does not state a license; see [NOTICE](NOTICE).

## Ringkasan (Bahasa Indonesia)

Backport tidak resmi untuk menutup CVE-2026-109618 dan CVE-2026-109619 di PHP 5.4.6
(paket Ubuntu 12.10), lengkap dengan script build di chroot, uji regresi, deploy bertahap
(precheck → install → verify) dan rollback. Ini hanya tambalan sementara: PHP 5.4 dan
Ubuntu 12.10 sudah lama tidak didukung, jadi rencanakan migrasi ke PHP yang masih didukung.
