# Changelog

## Not released yet

- PHP 8.3.36, 8.4.27 and 8.5.12 (FrankenPHP images of 2026-10-21), which fix PHP2Shell; the build refuses an older PHP. `memory_limit` is back to 256M.
- `session.upload_progress.enabled` is off, `session.use_strict_mode` on and `fatal_error_backtraces` off by default, as a mitigation for PHP2Shell (CVE-2026-109618 and CVE-2026-109619).
- `brewless-base` and `brewless-builder` for PHP 8.3, 8.4 and 8.5 on FrankenPHP 1.
