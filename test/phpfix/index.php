<?php

use PhpFix\Services\Greeter;
use PhpFix\Support\Style;

function describe(?Greeter $greeter, array $names, Style $style): string
{
    $out = '';
    if ($greeter === null) {
        $greeter = new Greeter();
    }
    foreach ($names as $name) {
        $out .= match ($style) {
            Style::Plain => $name,
            Style::Loud => $greeter?->greet(),
            default => '',
        };
    }
    while (strlen($out) > 64 && $out !== '') {
        $out = substr($out, 0, 64);
    }
    return $out;
}
