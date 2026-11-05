<?php

/*
 * Fails the build when a package that ships in the image is not under a
 * permissive licence. Reads `composer licenses --no-dev --format=json` on
 * stdin. A package with several licences (an "or") passes when one is allowed.
 */

$allowed = ['MIT', 'MIT-0', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', 'ISC', '0BSD'];

$report = json_decode((string) stream_get_contents(STDIN), true, flags: JSON_THROW_ON_ERROR);
$refused = [];

foreach ($report['dependencies'] ?? [] as $package => $details) {
    $licences = $details['license'] ?? [];

    if (array_intersect($licences, $allowed) === []) {
        $refused[] = $package.' ('.($licences === [] ? 'no licence' : implode(', ', $licences)).')';
    }
}

if (count($report['dependencies'] ?? []) === 0) {
    fwrite(STDERR, "No packages in the licence report.\n");
    exit(1);
}

if ($refused !== []) {
    fwrite(STDERR, "Not under a permissive licence:\n  ".implode("\n  ", $refused)."\n");
    exit(1);
}

echo count($report['dependencies'])." packages, all under a permissive licence.\n";
