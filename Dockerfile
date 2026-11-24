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

# uv: the event loop a realtime server (Laravel Reverb) holds its connections with. Without it PHP falls
# back to stream_select, which stops at 1,024 open files: about a thousand connections.
#
# redis: the released extension (6.3.0) does not compile on PHP 8.6. Until phpredis releases one that
# does, the 8.6 image builds it from the commit of phpredis's development branch that phpredis itself
# tests on PHP 8.6, with the options the release is built with; the older versions keep the release.
#
# mbstring: PHP's own 8.6 image, which FrankenPHP's is built on, no longer has it compiled in, and
# Laravel does not start without it. On the older versions it is there already and nothing is done.
# What is downloaded is checked against its SHA-256 before it is unpacked: the commit and the
# checksum are changed together.
ARG PHPREDIS_FOR_PHP_86=a6ce1e60b3e81ce3b25174aa5aaefd5590dc64fd
ARG PHPREDIS_FOR_PHP_86_SHA256=79288312706263ad0744391752fd9a62273d5a73c4e6e6a42ff2819e76363533
RUN if [ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" = "8.6" ]; then \
        install-php-extensions pdo_pgsql pdo_mysql mbstring intl bcmath pcntl zip gd exif opcache uv \
        && curl -fsSL -o /tmp/phpredis.tar.gz "https://github.com/phpredis/phpredis/archive/${PHPREDIS_FOR_PHP_86}.tar.gz" \
        && echo "${PHPREDIS_FOR_PHP_86_SHA256}  /tmp/phpredis.tar.gz" | sha256sum -c - \
        && tar xzf /tmp/phpredis.tar.gz -C /tmp && rm /tmp/phpredis.tar.gz \
        && cd "/tmp/phpredis-${PHPREDIS_FOR_PHP_86}" && phpize && ./configure --enable-redis && make -j"$(nproc)" && make install \
        && docker-php-ext-enable redis && cd / && rm -rf "/tmp/phpredis-${PHPREDIS_FOR_PHP_86}"; \
    else \
        install-php-extensions pdo_pgsql pdo_mysql mbstring redis intl bcmath pcntl zip gd exif opcache uv; \
    fi \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && php -m | grep -qx uv && php -m | grep -qx redis && php -m | grep -qx mbstring

# Two command-line tools an application may shell out to: pg_dump and pg_restore for its own logical
# back-ups (Serverless SQL backs up one database per resource, not the databases an application
# creates next to it), and pdftotext for the text layer of a PDF. Both from Debian, no recommends.
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client poppler-utils \
    && rm -rf /var/lib/apt/lists/* \
    && pg_dump --version && pdftotext -v 2>&1 | head -1

# Security fixes of the Debian packages that are out since the FrankenPHP image was made: a rebuild
# picks them up, which is what the scheduled scan relies on (runtime-updates.yml, BL-303).
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Refuse a PHP without the fixes of the 19 November 2026 security release
# (CVE-2026-115560 among them), which also carries the PHP2Shell fix. For PHP
# 8.6 that is its first release, 8.6.0, of the same day.
# runtime-updates.yml rewrites this line when a PHP release or a new minor is out (BL-305): keep
# it on one line, in this form, with the newest version as the fallback after ??.
RUN php -r '$min = ["8.3" => "8.3.37", "8.4" => "8.4.28", "8.5" => "8.5.13"][PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION] ?? "8.6.0"; if (version_compare(PHP_VERSION, $min, "<")) { fwrite(STDERR, "PHP ".PHP_VERSION." is older than ".$min.PHP_EOL); exit(1); }'

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

# Composer, Node (the Debian build: the base is Debian too), crane, which
# pushes a layer on top of an image through the registry API, and rclone, which
# copies the files of an existing S3 bucket into the application's own bucket.
# For copying an existing database in (brewless db:import): the newest
# PostgreSQL client from the PostgreSQL project's own Debian repository, so
# pg_dump reads every server up to that version (Debian itself only carries one),
# the MariaDB client, whose mariadb-dump also reads MySQL, and pgloader for MySQL
# to PostgreSQL. pgloader is the build of its author: the one Debian and the
# PostgreSQL repository carry cannot sign in to MySQL 8 (caching_sha2_password)
# nor read its collations. It reads /etc/mysql/my.cnf and stops at an
# !includedir line, so that file holds no more than the client needs.
# The tools are copied from images taken by digest, as pgloader already was: a tag can be moved to
# other content, and these run in a build that holds a key of the customer's registry. Dependabot
# proposes a new digest when one of them is released (.github/dependabot.yml). The FrankenPHP image
# the base starts from is the exception, on purpose: it follows its tag, so a rebuild picks up a
# patched PHP the day it is published, and the build refuses a PHP that is too old.
COPY --from=composer:2@sha256:50ea4d33fdcde1adb0f045547295faa1548b33872e5f789dae5b02ce2fb5de93 /usr/bin/composer /usr/bin/composer
COPY --from=node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 /usr/local/bin/node /usr/local/bin/node
COPY --from=node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=gcr.io/go-containerregistry/crane:v0.22.1@sha256:1f968817b95790bed063f71175aa6b8ff879fa17064020415f3e18bb6e6a36e1 /ko-app/crane /usr/local/bin/crane
COPY --from=rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=ghcr.io/dimitri/pgloader@sha256:a1d4a78e78a64e46cd3fc7dfc57d24eb91ffb1a5520f2b1f55631815e3658d6e /usr/local/bin/pgloader /usr/local/bin/pgloader

# The key the PostgreSQL repository signs its packages with (fingerprint
# B97B 0AFC AA1A 47F0 44F2 44A0 7FCC 7D46 ACCC 4CF8) is checked against its SHA-256 before apt
# trusts it. When PostgreSQL extends the key the file changes and the build stops here: compare the
# fingerprint of the new file, then put its checksum below.
ARG PGDG_KEY_SHA256=0144068502a1eddd2a0280ede10ef607d1ec592ce819940991203941564e8e76
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && apt-get update && apt-get install -y --no-install-recommends unzip git openssh-client ca-certificates curl \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && echo "${PGDG_KEY_SHA256}  /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc" | sha256sum -c - \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo "$VERSION_CODENAME")-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends postgresql-client-18 mariadb-client \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/mysql/my.cnf && printf '[client]\n' > /etc/mysql/my.cnf \
    && php -v && composer --version && node --version && npm --version && crane version && rclone version && ssh -V \
    && pg_dump --version | grep -q " 18\." && psql --version && pgloader --version && mariadb-dump --version

ENTRYPOINT []
CMD ["sh"]
