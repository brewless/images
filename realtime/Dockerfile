# syntax=docker/dockerfile:1

# brewless-realtime: a bare Laravel application that runs Laravel Reverb on
# its own, for one customer application at a time. No database, no cache
# server, no code of that application: only the keys it broadcasts with.
#
#   docker build --platform linux/amd64 -t <registry>/brewless-realtime:1.0.0 realtime

ARG PHP_VERSION=8.4

FROM php:${PHP_VERSION}-cli-alpine AS php

# pcntl, so that PHP handles SIGTERM itself and can close every connection first.
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && docker-php-ext-install -j"$(nproc)" pcntl \
    && apk del .build-deps \
    && php -m | grep -qx pcntl

# Refuse a PHP without the PHP2Shell fix (CVE-2026-109618, CVE-2026-109619).
RUN php -r '$min = ["8.3" => "8.3.36", "8.4" => "8.4.27"][PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION] ?? "8.5.12"; if (version_compare(PHP_VERSION, $min, "<")) { fwrite(STDERR, "PHP ".PHP_VERSION." is older than ".$min.PHP_EOL); exit(1); }'

FROM php AS vendor

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY . .

# The packages from composer.lock, without development packages; the build
# stops when one of them is not under a permissive licence.
RUN composer install --no-dev --no-interaction --no-progress --classmap-authoritative \
    && composer licenses --no-dev --format=json | php check-licenses.php \
    && test -f vendor/laravel/framework/LICENSE.md && test -f vendor/laravel/reverb/LICENSE.md

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
