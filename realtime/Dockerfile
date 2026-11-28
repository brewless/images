# syntax=docker/dockerfile:1

# brewless-realtime: a bare Laravel application that runs Laravel Reverb on
# its own, for one customer application at a time. No database, no cache
# server, no code of that application: only the keys it broadcasts with.
#
#   docker build --platform linux/amd64 -t <registry>/brewless-realtime:1.2.4 realtime

ARG PHP_VERSION=8.4

FROM php:${PHP_VERSION}-cli-alpine AS php

# pcntl, so that PHP handles SIGTERM itself and can close every connection first.
# uv, the event loop Reverb holds its connections with: without it PHP falls back to
# stream_select, which stops at 1,024 open files, so at about a thousand connections.
# By version: PECL lists every release of uv as beta, so its name alone installs nothing.
RUN apk add --no-cache libuv \
    && apk add --no-cache --virtual .build-deps $PHPIZE_DEPS libuv-dev \
    && docker-php-ext-install -j"$(nproc)" pcntl \
    && pecl install uv-0.3.1 \
    && docker-php-ext-enable uv \
    && apk del .build-deps \
    && rm -rf /tmp/pear \
    && php -m | grep -qx pcntl && php -m | grep -qx uv

# Security fixes of the Alpine packages that are out since the PHP image was made: a rebuild picks
# them up, which is what the scheduled scan relies on (runtime-updates.yml, BL-303).
RUN apk upgrade --no-cache

# Refuse a PHP without the fixes of the 19 November 2026 security release
# (CVE-2026-115560 among them), which also carries the PHP2Shell fix.
# runtime-updates.yml rewrites this line when a PHP release or a new minor is out (BL-305): keep
# it on one line, in this form, with the newest version as the fallback after ??.
RUN php -r '$min = ["8.3" => "8.3.37", "8.4" => "8.4.28", "8.5" => "8.5.13"][PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION] ?? "8.6.0"; if (version_compare(PHP_VERSION, $min, "<")) { fwrite(STDERR, "PHP ".PHP_VERSION." is older than ".$min.PHP_EOL); exit(1); }'

FROM php AS vendor

COPY --from=composer:2@sha256:50ea4d33fdcde1adb0f045547295faa1548b33872e5f789dae5b02ce2fb5de93 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY . .

# The packages from composer.lock, without development packages; the build
# stops when one of them is not under a permissive licence. They are installed
# without running anything of theirs (no scripts, no plugins), so no code of a
# package runs before its licence was looked at; what Laravel does after an
# install, finding its packages, is run by name afterwards.
RUN composer install --no-dev --no-interaction --no-progress --classmap-authoritative --no-scripts --no-plugins \
    && composer licenses --no-dev --no-plugins --format=json | php check-licenses.php \
    && test -f vendor/laravel/framework/LICENSE.md && test -f vendor/laravel/reverb/LICENSE.md \
    && php artisan package:discover --ansi

FROM php

ARG VERSION=dev

LABEL org.opencontainers.image.title="brewless-realtime" \
      org.opencontainers.image.description="Runs Laravel Reverb on its own for one application, configured from the environment" \
      org.opencontainers.image.source="https://github.com/brewless/images" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}"

WORKDIR /app

# The licence files of every package travel along in vendor/.
COPY --from=vendor /app/artisan /app/composer.json /app/composer.lock ./
COPY --from=vendor /app/app ./app
COPY --from=vendor /app/bootstrap ./bootstrap
COPY --from=vendor /app/config ./config
COPY --from=vendor /app/vendor ./vendor
COPY --chmod=755 entrypoint.sh /usr/local/bin/brewless-realtime

RUN mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs \
    && chown -R www-data:www-data storage bootstrap/cache

# Nothing to store: the state of the connections lives in memory, logs go to the provider.
ENV PORT=8080 \
    APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    CACHE_STORE=array \
    SESSION_DRIVER=array \
    QUEUE_CONNECTION=sync \
    BROADCAST_CONNECTION=reverb \
    REVERB_ALLOWED_ORIGINS=*

USER www-data
EXPOSE 8080

ENTRYPOINT ["brewless-realtime"]
CMD []
