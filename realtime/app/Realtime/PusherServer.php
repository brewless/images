<?php

declare(strict_types=1);

namespace App\Realtime;

use Laravel\Reverb\Contracts\Connection;
use Laravel\Reverb\Contracts\WebSocketConnection;
use Laravel\Reverb\Protocols\Pusher\Exceptions\ConnectionLimitExceeded;
use Laravel\Reverb\Protocols\Pusher\Exceptions\InvalidOrigin;
use Laravel\Reverb\Protocols\Pusher\Server;

/**
 * Reverb's Pusher server, with three changes.
 *
 * It keeps a list of the open connections. Reverb itself only knows the
 * connections that joined a channel, and on a stop it drops them without a
 * close frame. This one closes every connection with Pusher code 4200
 * ("reconnect immediately"), which pusher-js and Laravel Echo answer by
 * connecting again straight away.
 *
 * It closes a connection from an Origin that is not allowed. Reverb sends the
 * error but leaves the socket open, and a client that ignores the error can
 * still subscribe to public channels.
 *
 * It counts every open connection against the ceiling (REVERB_APP_MAX_CONNECTIONS)
 * and closes the one that is too many with Pusher code 4004. Reverb counts
 * only the connections that joined a channel, so a browser that connects and
 * subscribes to nothing would never be one too many, and it leaves the socket
 * of a refused one open, where it still takes memory and keeps a serverless
 * container awake.
 */
final class PusherServer extends Server
{
    public const int RECONNECT_IMMEDIATELY = 4200;

    public const int ORIGIN_NOT_ALLOWED = 4009;

    public const int OVER_CAPACITY = 4004;

    /** @var array<string, Connection> */
    private array $connections = [];

    private bool $stopping = false;

    public function open(Connection $connection): void
    {
        if ($this->stopping) {
            $this->closeWithReconnect($connection);

            return;
        }

        try {
            $this->verifyOrigin($connection);
        } catch (InvalidOrigin $exception) {
            $connection->send((string) json_encode($exception->payload()));
            $this->socket($connection)->close(pack('n', self::ORIGIN_NOT_ALLOWED).'Origin not allowed');

            return;
        }

        if ($connection->app()->hasMaxConnectionLimit() && count($this->connections) >= $connection->app()->maxConnections()) {
            $connection->send((string) json_encode((new ConnectionLimitExceeded)->payload()));
            $this->socket($connection)->close(pack('n', self::OVER_CAPACITY).'Over connection quota');

            return;
        }

        $this->connections[$connection->identifier()] = $connection;

        parent::open($connection);
    }

    public function close(Connection $connection): void
    {
        unset($this->connections[$connection->identifier()]);

        parent::close($connection);
    }

    /**
     * Close every open connection with 4200 and refuse new ones. Returns how many were open.
     */
    public function closeAll(): int
    {
        $this->stopping = true;

        foreach ($this->connections as $connection) {
            $this->closeWithReconnect($connection);
        }

        return count($this->connections);
    }

    public function hasOpenConnections(): bool
    {
        return $this->connections !== [];
    }

    private function closeWithReconnect(Connection $connection): void
    {
        $this->socket($connection)->close(pack('n', self::RECONNECT_IMMEDIATELY).'Server is restarting');
    }

    private function socket(Connection $connection): WebSocketConnection
    {
        // Reverb keeps the WebSocket of a connection to itself; read it from inside.
        return (fn (): WebSocketConnection => $this->connection)->call($connection);
    }
}
