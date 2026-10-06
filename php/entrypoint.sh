#!/bin/sh
set -e

# One image, several roles. The role is the first argument:
#   web        serve HTTP (default)
#   worker     process the queue
#   scheduler  run the scheduler once, for a cron trigger
#   anything else is passed to the application's console

cd /app

if [ -f artisan ]; then
    # Configuration comes from the environment of this container, so it can
    # only be cached here, not at build time.
    php artisan config:cache --no-interaction >/dev/null
    php artisan route:cache --no-interaction >/dev/null
    php artisan view:cache --no-interaction >/dev/null
fi

case "${1:-web}" in
    web)
        exec frankenphp run --config /etc/frankenphp/Caddyfile
        ;;
    worker)
        shift
        exec php artisan queue:work --no-interaction --tries=3 --max-time=3300 "$@"
        ;;
    scheduler)
        exec php artisan schedule:run --no-interaction
        ;;
    *)
        exec php artisan "$@"
        ;;
esac
