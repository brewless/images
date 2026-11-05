<?php

use Illuminate\Foundation\Application;

// No routes, no middleware, no database: Reverb runs its own server.
return Application::configure(basePath: dirname(__DIR__))->create();
