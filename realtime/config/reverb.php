<?php

/*
 * One Reverb server with one application, configured from the environment of
 * the container. The entrypoint refuses to start without REVERB_APP_ID,
 * REVERB_APP_KEY and REVERB_APP_SECRET. Scaling is off: one container serves
 * every connection.
 */

/*
 * REVERB_ALLOWED_ORIGINS is a comma-separated list of hostnames, such as
 * "example.com,www.example.com" or "*.example.com". Reverb compares each one
 * (a * matches anything) with the host of the Origin header, without scheme
 * or port, so a URL or a port in the list is reduced to its host.
 */
$allowedOrigins = array_values(array_filter(array_map(
    fn (string $origin): string => strtolower((string) parse_url(str_contains($origin, '://') ? $origin : '//'.$origin, PHP_URL_HOST)),
    array_map('trim', explode(',', (string) env('REVERB_ALLOWED_ORIGINS', '*'))),
)));

return [

    'default' => 'reverb',

    'servers' => [

        'reverb' => [
            'host' => '0.0.0.0',
            'port' => env('PORT', 8080),
            'path' => '',
            'hostname' => env('REVERB_HOST'),
            'options' => [
                'tls' => [],
            ],
            'max_request_size' => env('REVERB_MAX_REQUEST_SIZE', 10_000),
            'scaling' => [
                'enabled' => false,
                'channel' => 'reverb',
                'server' => [],
            ],
            'pulse_ingest_interval' => 15,
            'telescope_ingest_interval' => 15,
        ],

    ],

    'apps' => [

        'provider' => 'config',

        'apps' => [
            [
                'key' => env('REVERB_APP_KEY'),
                'secret' => env('REVERB_APP_SECRET'),
                'app_id' => env('REVERB_APP_ID'),
                'options' => [
                    'host' => env('REVERB_HOST'),
                    'port' => env('REVERB_PORT', 443),
                    'scheme' => env('REVERB_SCHEME', 'https'),
                    'useTLS' => env('REVERB_SCHEME', 'https') === 'https',
                ],
                'allowed_origins' => $allowedOrigins === [] ? ['*'] : $allowedOrigins,
                'ping_interval' => env('REVERB_APP_PING_INTERVAL', 60),
                'activity_timeout' => env('REVERB_APP_ACTIVITY_TIMEOUT', 30),
                'max_connections' => env('REVERB_APP_MAX_CONNECTIONS'),
                'max_message_size' => env('REVERB_APP_MAX_MESSAGE_SIZE', 10_000),
                'accept_client_events_from' => env('REVERB_APP_ACCEPT_CLIENT_EVENTS_FROM', 'members'),
                'rate_limiting' => [
                    'enabled' => false,
                    'max_attempts' => 60,
                    'decay_seconds' => 60,
                    'terminate_on_limit' => false,
                ],
            ],
        ],

    ],

];
