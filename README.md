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

Published from this repository for PHP 8.3, 8.4 and 8.5, as
`ghcr.io/brewless/brewless-base:php8.4` and `ghcr.io/brewless/brewless-builder:php8.4`
(and likewise for the other versions). To build them yourself:

```bash
docker build --platform linux/amd64 --build-arg PHP_VERSION=8.4 --target base    -t <registry>/brewless-base:php8.4 .
docker build --platform linux/amd64 --build-arg PHP_VERSION=8.4 --target builder -t <registry>/brewless-builder:php8.4 .
```

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
(`brewless-realtime:1.1.0`) to get exactly that image, or follow `:1.0` or `:1`.
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
docker build --platform linux/amd64 --build-arg VERSION=1.1.0 -t <registry>/brewless-realtime:1.1.0 realtime
```

The build stops when a package in `composer.lock` is not under a permissive
licence (MIT, BSD, Apache-2.0, ISC).

## Licence

MIT. See [LICENSE](LICENSE).
