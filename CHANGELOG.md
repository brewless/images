# Changelog

## Not released yet

- `brewless-base` (and so `brewless-builder`) carries the `uv` extension. A realtime server on an application's own image (Laravel Reverb) holds its connections with libuv instead of `stream_select`, which stops at 1,024 open files. Measured on a Scaleway Serverless Container: without `uv` the server stopped at connection 1,018 and every browser was cut.
- `brewless-realtime` 1.1.0 carries the `uv` extension (0.3.1) for the same reason. With it a 256 MB container at Scaleway held about 1,300 connections that only listened. `REVERB_APP_MAX_CONNECTIONS` now counts every open connection, not only the ones that joined a channel, and the connection that is one too many is closed with Pusher code 4004 instead of being left open after the error. Brewless sets that ceiling from the container's memory.
- `brewless-base` (and so `brewless-builder`): a static file under `public/` asked for with its version in the query string (`/img/logo.svg?v=1a2b3c`, as an application's asset helper writes it) gets `Cache-Control: public, max-age=31536000, immutable`, like `/build/*` already did. A page with `?v=` and a file that does not exist are left alone. Before this, such files had no `Cache-Control` at all on the container's own address and on the test address, and PageSpeed flagged them.
- `brewless-realtime` 1.0.0, a new image: a bare Laravel 13 application on PHP 8.4 (Alpine) that runs Laravel Reverb 1.12 on its own for one application, configured with `REVERB_APP_ID`, `REVERB_APP_KEY`, `REVERB_APP_SECRET` and `REVERB_ALLOWED_ORIGINS`. A stop closes every connection with Pusher code 4200 so clients reconnect at once, and a connection from a refused origin is closed with 4009. Published as `brewless-realtime:1.0.0`, `:1.0` and `:1`; a published version is never replaced. The build refuses a package that is not under a permissive licence.

## 1.0.0 (4 November 2026)

First tagged release. The images have been building and running Brewless's own
site and its customers' applications since October; this gives that state a
version to point at. What is in it:


- `brewless-builder` carries the PostgreSQL 18 client from apt.postgresql.org (its `pg_dump` reads every server up to 18), the MariaDB client (`mariadb-dump`, which also reads MySQL) and `pgloader` from `ghcr.io/dimitri/pgloader` (the Debian build cannot sign in to MySQL 8), for `brewless db:import`. Its `/etc/mysql/my.cnf` holds only `[client]`: pgloader cannot read `!includedir`.
- `brewless-builder` carries `rclone` 1.75.2, for `brewless storage:import` (copying an existing S3 bucket into the application's bucket).
- `brewless-base` (and so `brewless-builder`) carries `postgresql-client` (`pg_dump`, `pg_restore`) and `poppler-utils` (`pdftotext`) from Debian.
- PHP 8.3.36, 8.4.27 and 8.5.12 (FrankenPHP images of 2026-10-21), which fix PHP2Shell; the build refuses an older PHP. `memory_limit` is back to 256M.
- `session.upload_progress.enabled` is off, `session.use_strict_mode` on and `fatal_error_backtraces` off by default, as a mitigation for PHP2Shell (CVE-2026-109618 and CVE-2026-109619).
- `brewless-base` and `brewless-builder` for PHP 8.3, 8.4 and 8.5 on FrankenPHP 1.
