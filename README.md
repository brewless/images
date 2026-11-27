# Brewless images

The container images a [Brewless](https://brewless.eu) build uses, and the
one that serves Realtime. They contain no code of Brewless and no secret.
Build them yourself and you can keep building and running your application
without us.

| Image | What it is |
| --- | --- |
| `brewless-base:php<version>` | What an application runs on: FrankenPHP, the usual PHP extensions and `uv` (the event loop of a realtime server), `pg_dump` and `pdftotext`, a default server configuration and entrypoint |
| `brewless-builder:php<version>` | The base plus Composer, Node 24, `crane`, `rclone`, the PostgreSQL 18 client, `pgloader` and the MariaDB client; the build job in your project runs in it, and so do a file import from another S3 bucket and a database import |
| `brewless-realtime:<version>` | Laravel Reverb on its own, for the WebSockets of one application; see [Realtime](#realtime) |
| `brewless-malware:<version>` | ClamAV and the runner of Malware Protection, which scans Object Storage buckets in the customer's own Scaleway account; see [Malware Protection](#malware-protection) |

Published from this repository for every PHP version in `php-versions`, one
per line (today 8.3, 8.4, 8.5 and 8.6), as
`ghcr.io/brewless/brewless-base:php8.4` and `ghcr.io/brewless/brewless-builder:php8.4`
(and likewise for the other versions). A new PHP minor comes in by itself; see
[below](#security-updates-by-themselves). To build them yourself:

```bash
docker build --platform linux/amd64 --build-arg PHP_VERSION=8.4 --target base    -t <registry>/brewless-base:php8.4 .
docker build --platform linux/amd64 --build-arg PHP_VERSION=8.4 --target builder -t <registry>/brewless-builder:php8.4 .
```

## Security updates, by themselves

`.github/workflows/runtime-updates.yml` runs every hour, at 17 minutes past. It compares the newest FrankenPHP release per PHP
version with the one in `brewless-base` (`scripts/php-releases.sh`) and scans
every published image with Trivy for CRITICAL and HIGH vulnerabilities
(`scripts/scan-images.sh`). A newer PHP release, or a finding with a fix that
no rebuild was made for yet (`security/rebuilt.json`), raises the minimum in the
Dockerfile, updates the Composer packages of `brewless-realtime` and its version
where needed, commits that and starts `publish.yml`. The images upgrade their
Debian and Alpine packages when they are built, so a rebuild takes those fixes.

A new PHP minor comes in the same way (`scripts/new-php-minor.sh`). After the
newest line of `php-versions`, say 8.6, the run looks for 8.7 and for 9.0. Once
FrankenPHP has a stable release of one (`dunglas/frankenphp:1-php8.7.0`, so no
alpha, beta or RC), it is added to `php-versions`, the Dockerfile's minimum for
it is set to that release, and the images for it are built and published. The
build matrix, the release watch and the scan all read `php-versions`, so no
other list needs changing.

Once published, `publish.yml` tells Brewless through a signed webhook, with the
realtime version and the vulnerabilities it fixed, and Brewless puts the new
images under every application that runs on them. Every run also reports its
scan, so a finding without a fix shows in Brewless's admin panel. The
repository needs `BREWLESS_IMAGES_WEBHOOK_URL` and `BREWLESS_IMAGES_WEBHOOK_SECRET`,
both as repository secrets so this public repository's logs never show them;
without them nothing is called.

## How a build uses them

A serverless job runs without privileges, so it cannot execute a Dockerfile.
The build job runs in the builder image, installs your dependencies, builds
your frontend, packs the result as one layer and puts that layer on top of the
base image through the registry API. The same commit gives the same image.

## Your own server configuration

An application that has `docker/Caddyfile`, `docker/entrypoint.sh` or
`docker/php.ini` in its repository replaces the default of that name. The
entrypoint takes a role as its first argument: `web` (default), `worker`,
`scheduler`, or anything else for the application's console.

## Realtime

`ghcr.io/brewless/brewless-realtime` is a bare Laravel application (PHP 8.4,
Alpine) that runs [Laravel Reverb](https://reverb.laravel.com), a WebSocket
server that speaks the Pusher protocol, for one application. It holds no code
of that application and needs no database, cache server or queue: the
application broadcasts to it through the Pusher HTTP API, and browsers connect
to it with Laravel Echo or pusher-js. Brewless starts it as the `realtime`
container of an environment with `image: brewless`; you can run it anywhere
else as well.

"Laravel" and "Reverb" are trademarks of Laravel. This image is not made,
endorsed or supported by Laravel; it only runs their MIT-licensed software,
whose licence files travel along in `/app/vendor`.

| Variable | Default | |
| --- | --- | --- |
| `REVERB_APP_ID` | none, required | The application ID your application broadcasts with |
| `REVERB_APP_KEY` | none, required | The public key the browser connects with |
| `REVERB_APP_SECRET` | none, required | Signs the HTTP API calls and the private and presence channel authorisations |
| `REVERB_ALLOWED_ORIGINS` | `*` | Comma-separated hostnames whose pages may connect, such as `example.com,www.example.com` or `*.example.com`. Compared with the host of the `Origin` header (no scheme, no port); a connection from another origin, or without one, is closed with Pusher code 4009 |
| `PORT` | `8080` | The port Reverb listens on, on `0.0.0.0` |
| `APP_KEY` | random at start | Nothing is encrypted; Laravel only wants a key |
| `REVERB_APP_PING_INTERVAL`, `REVERB_APP_ACTIVITY_TIMEOUT`, `REVERB_APP_MAX_MESSAGE_SIZE`, `REVERB_MAX_REQUEST_SIZE` | Reverb's defaults (60, 30, 10000, 10000) | Passed to Reverb as they are |
| `REVERB_APP_MAX_CONNECTIONS` | none | How many connections the server holds at once, counting every open one. The next is closed with Pusher code 4004 and the ones connected stay. Brewless sets it from the container's memory |

The container refuses to start, with a message on stderr, when one of the three
required variables is missing. It runs as `www-data`, logs to stderr, answers
`GET /up` with 200 and runs one server: scaling over Redis is off. Without
arguments it starts `reverb:start --host=0.0.0.0 --port=$PORT`; arguments go to
`php artisan`, so `reverb:start --host=0.0.0.0 --port=8080` starts it the same
way an application's own image would.

On SIGTERM (a deploy, `docker stop`) the server closes every connection with
Pusher code 4200, "reconnect immediately", and stops within a few seconds.
Laravel Echo and pusher-js reconnect by themselves at once; when nothing
listens at that moment (a container that restarts rather than one replaced by
a running successor), pusher-js tries again after about 15 seconds. Clients
should fetch the current state when they are connected again: messages sent in
between are not replayed. Reverb itself drops the connections without a close code, and leaves
a connection from a refused origin open; this image closes both explicitly.

The image carries the `uv` extension, so the server holds its connections with
libuv. Without it PHP uses `stream_select`, which stops at 1,024 open files:
the server of 1.0.0 stopped at connection 1,018.

Each version is published once and never replaced: pin the full version
(`brewless-realtime:1.2.0`) to get exactly that image, or follow `:1.2` or `:1`.
Brewless pins a full version and moves to a new one with a deploy. The version
is in [realtime/VERSION](realtime/VERSION).

To run it on your own machine:

```bash
docker run --rm -p 8080:8080 \
  -e REVERB_APP_ID=123456 \
  -e REVERB_APP_KEY=localkey \
  -e REVERB_APP_SECRET=localsecret \
  -e REVERB_ALLOWED_ORIGINS=localhost \
  ghcr.io/brewless/brewless-realtime:1
```

and point your application at it with `BROADCAST_CONNECTION=reverb`, the same
three `REVERB_APP_*` values, `REVERB_HOST=localhost`, `REVERB_PORT=8080` and
`REVERB_SCHEME=http`. To build it yourself:

```bash
docker build --platform linux/amd64 --build-arg VERSION=1.2.0 -t <registry>/brewless-realtime:1.2.0 realtime
```

The build stops when a package in `composer.lock` is not under a permissive
licence (MIT, BSD, Apache-2.0, ISC).

## Malware Protection

`ghcr.io/brewless/brewless-malware` is the official ClamAV image
(`clamav/clamav-debian:1.5_base`, taken by digest) with one program added:
`/usr/local/bin/brewless-malware`, a small runner written in Go with only its
standard library ([malware/](malware)). Brewless runs it as Scaleway Serverless
Jobs, and optionally as a Serverless Container, in the customer's own Scaleway
account, with a key that belongs to that account. It holds no signatures and no
secret; nothing in it calls Brewless except the signed reports below. The
agreement between this image, Brewless and the Laravel package is
`docs/malware-protection/contract.md` in brewless/app.

Scaleway Object Storage has no event notifications, but it writes one log line
per request to Cockpit. `watch` reads those lines, so a new object is queued
within minutes of its upload without anything in the application.

| Command | What it does |
| --- | --- |
| `watch` | Reads the Object Storage log lines from Cockpit since its cursor, queues every object written to a bucket that is scanned, notices new and deleted buckets, and starts `scan` (Serverless Jobs API) when an item is ready, no scan runs and the day's `scan_seconds_per_day` is not used up. Needs no ClamAV |
| `scan` | Copies the definitions from the private bucket, takes ready items from the queue, downloads each object to the scratch disk (with `If-Match`, so it scans exactly the ETag it saw), scans them in batches, checks with a HEAD that the ETag did not change, merges three tags into the object's own (`brewless-av`, `brewless-av-etag`, `brewless-av-at`; at most 10 tags, the customer's are never dropped), writes the register, releases or quarantines, and sends one `scan.completed` report |
| `update` | Runs the official `freshclam` on the definitions of the private bucket (so it downloads only differences, and keeps its cool-down) and writes them back; on a 429 or 403 from the ClamAV CDN it uses `MW_MIRROR_URL` |
| `reconcile` | Lists every scanned bucket against the register and queues objects that are new, changed or were missed by the logs; removes the register entries of objects that are gone; reports new, removed and unreadable buckets |
| `serve` | An HTTP interface around clamd: `POST /scan` with the file as body, or JSON `{"bucket","key","project"}`, answers `{"status","signature","clamav","definitions","ms"}`; `GET /health` is 200 once clamd is ready |
| `selftest` | Scans a generated EICAR file, a clean file and a file over a lowered limit with clamscan, clamdscan and clamd's INSTREAM, and exits non-zero on a wrong verdict |

A result is `clean`, `infected`, `unsupported` (ClamAV said
`Heuristics.Limits.Exceeded.*` or `Heuristics.Encrypted.*`, or the object is
larger than `max_file_bytes`, at most 2 GiB, which ClamAV cannot scan),
`failed` (tried again after 1, 4 and 16 minutes, then reported) or
`quarantined`. In a bucket in protection mode the application uploads to a
staging prefix (`incoming/`): a clean object is copied out of it and tagged with
the copy's own ETag, an infected one goes to quarantine, and anything else stays
where the application does not read it.

| Variable | |
| --- | --- |
| `MW_REGION`, `MW_PROJECT_ID`, `MW_BUCKET` | The region, the project and the private bucket that holds `config.json`, the queue, the register, the definitions and `status.json` |
| `MW_ACCESS_KEY`, `MW_SECRET_KEY` | The key of the protection's IAM application. S3 requests are signed with it (SigV4, `https://s3.<region>.scw.cloud`, `ACCESSKEY@<project>` for another project); Cockpit and the Jobs API get it as `X-Auth-Token` |
| `MW_WEBHOOK_URL`, `MW_WEBHOOK_SECRET` | Where reports go, signed with `X-Brewless-Signature: sha256=<HMAC-SHA256(secret, timestamp + "." + body)>` and `X-Brewless-Timestamp`. A report holds keys, sizes, ETags and signature names, never file contents |
| `MW_SCAN_JOB_ID` | (`watch`) The job definition of `scan` |
| `MW_MIRROR_URL` | (`update`) The fallback mirror |
| `MW_SCRATCH` | Default `/var/lib/brewless-malware`: downloads and definitions, on disk because `/tmp` is memory in a Serverless Job |
| `MW_DB_DIR` | Use the definitions in this directory instead of the bucket's (`selftest`, and `update` without `MW_BUCKET`, locally and in CI) |
| `PORT`, `MW_STREAM_MAX`, `MW_THREADS` | (`serve`) Port (8080), the largest body (`100M`) and clamd's threads (the CPUs) |

The image runs as the `clamav` user (1000) and works as root too, which a
Serverless Job may use; it switches no users. Its entrypoint is the runner, so
the ClamAV image's own entrypoint, which would start freshclam and clamd, never
runs. Measurements of memory and CPU are in
[malware/BENCHMARK.md](malware/BENCHMARK.md). To try it on your own machine,
fetch the signatures once into a volume and run the selftest:

```bash
docker build --platform linux/amd64 --build-arg VERSION=1.0.0 -t brewless-malware:local malware
docker volume create clamav-db
docker run --rm --user 0 -v clamav-db:/db -e MW_DB_DIR=/db brewless-malware:local update
docker run --rm -v clamav-db:/db:ro -e MW_DB_DIR=/db brewless-malware:local selftest
```

`.github/workflows/malware.yml` builds it (the Go tests run inside the build),
runs the selftest with signatures it caches and updates at most once a day,
and publishes from `main` once per version in `malware/VERSION`
(`1.0.0`, `1.0`, `1`; a published version is never replaced). Every Monday it
raises the version and publishes again when ClamAV published a new `1.5_base`
image or the Debian packages have fixes. `.github/workflows/signature-mirror.yml`
keeps Brewless's mirror of the signatures with
[cvdupdate](https://github.com/Cisco-Talos/cvdupdate) every four hours, in the
bucket that the repository secrets `MIRROR_S3_ENDPOINT`, `MIRROR_REGION`,
`MIRROR_BUCKET`, `MIRROR_ACCESS_KEY` and `MIRROR_SECRET_KEY` name.

ClamAV is licensed under the GNU GPL, version 2, and is not changed here; the
image's `/usr/share/doc/brewless-malware/NOTICE` says where its exact source
is. The runner is MIT, like the rest of this repository. "ClamAV" is a
trademark of Cisco; this image is not made, endorsed or supported by Cisco.

## Licence

MIT. See [LICENSE](LICENSE).
