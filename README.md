# Brewless images

The two container images a [Brewless](https://brewless.eu) build uses. They
contain no code of Brewless and no secret. Build them yourself and you can
keep building and running your application without us.

| Image | What it is |
| --- | --- |
| `brewless-base:php8.4` | What an application runs on: FrankenPHP, the usual PHP extensions, a default server configuration and entrypoint |
| `brewless-builder:php8.4` | The base plus Composer, Node 24 and `crane`; the build job in your project runs in it |

Published from this repository as `ghcr.io/brewless/brewless-base:php8.4` and
`ghcr.io/brewless/brewless-builder:php8.4`. To build them yourself:

```bash
docker build --platform linux/amd64 --target base    -t <registry>/brewless-base:php8.4 .
docker build --platform linux/amd64 --target builder -t <registry>/brewless-builder:php8.4 .
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

## Licence

MIT. See [LICENSE](LICENSE).
