# Patch review: 5.4.45 backport → Ubuntu php5 5.4.6-1ubuntu1.8

Source tree: `apt-get source php5=5.4.6-1ubuntu1.8` with all 74 Ubuntu quilt patches applied
(last one: `CVE-2014-2270.patch`). The backport is added as the last patch in the series.

## How the upstream patch applied (`patch -p1 --dry-run`)

| File | Result |
|---|---|
| `ext/session/session.c` | 1 hunk OK (offset −85) |
| `main/main.c` | 4 hunks OK (offsets −5 / −27) |
| `main/rfc1867.c` | 4 OK, **hunk #2 FAILED** — rewritten by hand (below) |
| `main/SAPI.c` | OK (offset −7) |
| `Zend/zend_alloc.c` | OK; hunk #3 fuzz 2, hunk #4 fuzz 1 |
| `Zend/zend_alloc.h`, `Zend/zend_execute_API.c`, `Zend/zend_llist.c` | OK |

### Fuzzed hunks in `zend_alloc.c`
Fuzz only relaxes *context* lines; the removed lines must still match exactly. After applying,
all four `safe_address()` variants call `zend_mm_safe_error_ex(...)` and no
`zend_error_noreturn(E_ERROR, "Possible integer overflow ...")` call remains (checked with grep:
0 left).

## `main/rfc1867.c` — manual rewrite

PHP 5.4.45 parses part headers with a `smart_str buf_value` accumulator. PHP 5.4.6 still uses
the older algorithm: each `Key: value` line is added to the list immediately, and a
continuation line (leading whitespace) replaces the list tail via `prev_entry` +
`zend_llist_remove_tail()`. The upstream hunk therefore cannot apply.

Same intent, implemented for the 5.4.6 algorithm:

```c
int skip_continuation = 0; /* previous header was dropped */
...
if (value) {
    *value = 0;
    /* keep only headers we use, and ignore duplicates */
    if (!php_mime_should_save_hdr(key) || php_mime_get_hdr_value(*header, key)) {
        skip_continuation = 1;
        continue;
    }
    skip_continuation = 0;
    do { value++; } while (isspace((unsigned char)*value));
    entry.value = estrdup(value);
    entry.key = estrdup(key);
} else if (skip_continuation) {       /* continuation of a dropped header */
    continue;
} else if (zend_llist_count(header)) { /* unchanged 5.4.6 continuation logic */
```

Why this is safe for applications: in 5.4.6 the only callers of `php_mime_get_hdr_value()`
read `Content-Disposition` (`rfc1867.c:791`) and `Content-Type` (`rfc1867.c:1152`)
(line numbers in the unpatched Ubuntu 5.4.6 tree). Other
part headers were never used. `php_mime_get_hdr_value()` compares with `strcasecmp`, so the
duplicate check is case-insensitive like the header lookup itself. A dropped header's
continuation lines are dropped too, so they can never be appended to the previous kept header.

## `Zend/zend_execute_API.c` — no per-request leak

The patch zeroes the handler stacks and sets `EG(in_autoload) = NULL` at the end of
`shutdown_executor()`. In 5.4.6 those structures are destroyed earlier in the same function
(`zend_stack_destroy` / `zend_ptr_stack_destroy` at lines 327–329, `in_autoload` freed at
331–333) and re-initialised by `init_executor()` for every request (lines 175–177). So zeroing
them afterwards only removes stale pointers; it does not leak memory per request.

## Behaviour changes (intended)

1. OOM: message to stderr + `_exit(1)` instead of a PHP fatal page. Under mod_php the Apache
   child exits and the parent starts a new one.
2. `max_multipart_body_parts` (default `-1` → `max_input_vars + max_file_uploads`).
3. Session upload progress always off.
