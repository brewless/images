<?php

declare(strict_types=1);

namespace App\Providers;

use App\Console\StartServer;
use App\Realtime\PusherServer;
use Illuminate\Support\ServiceProvider;
use Laravel\Reverb\Protocols\Pusher\Server;

final class RealtimeServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // One instance that knows every open connection, so a stop can close them all.
        $this->app->singleton(Server::class, PusherServer::class);
    }

    public function boot(): void
    {
        $this->commands([StartServer::class]);
    }
}
