# syntax=docker/dockerfile:1

# The two images a Brewless build needs. They hold no code of Brewless and no
# secret: build them yourself and you can keep deploying without us.
#
#   base     what an application runs on: FrankenPHP with the usual extensions
#   builder  the base plus the tools a build needs; the build job runs in it
#
#   docker build --platform linux/amd64 --target base    -t <registry>/brewless-base:php8.4 .
#   docker build --platform linux/amd64 --target builder -t <registry>/brewless-builder:php8.4 .

ARG PHP_VERSION=8.4

FROM dunglas/frankenphp:1-php${PHP_VERSION} AS base

RUN install-php-extensions pdo_pgsql pdo_mysql redis intl bcmath pcntl zip gd exif opcache \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Refuse a PHP without the PHP2Shell fix (CVE-2026-109618, CVE-2026-109619).
RUN php -r '$min = ["8.3" => "8.3.36", "8.4" => "8.4.27"][PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION] ?? "8.5.12"; if (version_compare(PHP_VERSION, $min, "<")) { fwrite(STDERR, "PHP ".PHP_VERSION." is older than ".$min.PHP_EOL); exit(1); }'

# Defaults. An application that brings docker/Caddyfile, docker/entrypoint.sh
# or docker/php.ini replaces the one it brings.
COPY php/php.ini "$PHP_INI_DIR/conf.d/zz-brewless.ini"
COPY php/Caddyfile /etc/frankenphp/Caddyfile
COPY --chmod=755 php/entrypoint.sh /usr/local/bin/brewless-entrypoint

# Serverless containers send traffic to $PORT; logs go to the provider.
ENV PORT=8080 \
    APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    XDG_CONFIG_HOME=/tmp/caddy-config \
    XDG_DATA_HOME=/tmp/caddy-data

WORKDIR /app
EXPOSE 8080

ENTRYPOINT ["brewless-entrypoint"]
CMD ["web"]

FROM base AS builder

# Composer, Node (the Debian build: the base is Debian too) and crane, which
# pushes a layer on top of an image through the registry API.
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY --from=node:24-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:24-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=gcr.io/go-containerregistry/crane:latest /ko-app/crane /usr/local/bin/crane

RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && apt-get update && apt-get install -y --no-install-recommends unzip git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && php -v && composer --version && node --version && npm --version && crane version

ENTRYPOINT []
CMD ["sh"]
