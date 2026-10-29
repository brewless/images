# Changelog

## Not released yet

- `brewless-builder` carries the PostgreSQL 18 client from apt.postgresql.org (its `pg_dump` reads every server up to 18), the MariaDB client (`mariadb-dump`, which also reads MySQL) and `pgloader` from `ghcr.io/dimitri/pgloader` (the Debian build cannot sign in to MySQL 8), for `brewless db:import`. Its `/etc/mysql/my.cnf` holds only `[client]`: pgloader cannot read `!includedir`.
- `brewless-builder` carries `rclone` 1.75.2, for `brewless storage:import` (copying an existing S3 bucket into the application's bucket).
- `brewless-base` (and so `brewless-builder`) carries `postgresql-client` (`pg_dump`, `pg_restore`) and `poppler-utils` (`pdftotext`) from Debian.
- PHP 8.3.36, 8.4.27 and 8.5.12 (FrankenPHP images of 2026-10-21), which fix PHP2Shell; the build refuses an older PHP. `memory_limit` is back to 256M.
- `session.upload_progress.enabled` is off, `session.use_strict_mode` on and `fatal_error_backtraces` off by default, as a mitigation for PHP2Shell (CVE-2026-109618 and CVE-2026-109619).
- `brewless-base` and `brewless-builder` for PHP 8.3, 8.4 and 8.5 on FrankenPHP 1.
