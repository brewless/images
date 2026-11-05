<?php

declare(strict_types=1);

namespace App\Console;

use App\Realtime\PusherServer;
use Laravel\Reverb\Protocols\Pusher\Server;
use Laravel\Reverb\Servers\Reverb\Console\Commands\StartServer as ReverbStartServer;
use React\EventLoop\Loop;
use Symfony\Component\Console\Attribute\AsCommand;

/**
 * reverb:start, with a stop that lets the clients reconnect at once.
 *
 * It takes the name of Reverb's own command, so `php artisan reverb:start`
 * runs this one. On SIGTERM or SIGINT Reverb drops its connections and exits
 * on the spot. This command closes them with Pusher code 4200 instead, waits
 * (at most a few seconds) until the close frames are out, and then ends the
 * event loop.
 */
#[AsCommand(name: 'reverb:start')]
final class StartServer extends ReverbStartServer
{
    private const float DRAIN_SECONDS = 3.0;

    /**
     * @var string
     */
    protected $signature = 'reverb:start
                {--host= : The IP address the server should bind to}
                {--port= : The port the server should listen on}
                {--path= : The path the server should prefix to all routes}
                {--hostname= : The hostname the server is accessible from}
                {--debug : Indicates whether debug messages should be displayed in the terminal}';

    /**
     * @var string
     */
    protected $description = 'Start the Reverb server; a stop closes every connection with 4200';

    public function handleSignal(int $signal = 0, int|false $previousExitCode = 0): int|false
    {
        $server = $this->laravel->make(Server::class);

        if (! $server instanceof PusherServer) {
            return parent::handleSignal($signal, $previousExitCode);
        }

        $count = $server->closeAll();

        $this->components->info("Stopping: closing {$count} connection(s) with code 4200.");

        $loop = Loop::get();
        $deadline = microtime(true) + self::DRAIN_SECONDS;

        $loop->addPeriodicTimer(0.05, function () use ($server, $loop, $deadline): void {
            if (! $server->hasOpenConnections() || microtime(true) >= $deadline) {
                $loop->stop();
            }
        });

        // Do not exit here: the loop ends once the close frames are out, and the command returns.
        return false;
    }
}
