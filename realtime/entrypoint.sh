#!/bin/sh
set -e

# Runs Laravel Reverb for one application. The three REVERB_APP_* variables
# are required; everything else has a default.

missing=""
for name in REVERB_APP_ID REVERB_APP_KEY REVERB_APP_SECRET; do
    eval "value=\${$name:-}"
    if [ -z "$value" ]; then
        missing="$missing $name"
    fi
done

if [ -n "$missing" ]; then
    echo "brewless-realtime: missing required variable(s):$missing" >&2
    echo "brewless-realtime: set REVERB_APP_ID, REVERB_APP_KEY and REVERB_APP_SECRET to the keys your application broadcasts with." >&2
    exit 1
fi

# Nothing here is encrypted, but Laravel expects a key.
if [ -z "${APP_KEY:-}" ]; then
    APP_KEY="base64:$(head -c 32 /dev/urandom | base64)"
    export APP_KEY
fi

cd /app

# Without arguments the image starts Reverb; with arguments they go to
# artisan, so `reverb:start --host=0.0.0.0 --port=8080` works as well (the
# same arguments start Reverb from an application's own image).
# exec: PHP becomes PID 1 and gets SIGTERM itself, so a stop closes every connection with 4200.
if [ "$#" -eq 0 ]; then
    exec php artisan reverb:start --host=0.0.0.0 --port="${PORT:-8080}" --no-interaction
fi

exec php artisan "$@"
