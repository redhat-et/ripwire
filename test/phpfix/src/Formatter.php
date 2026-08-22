<?php

namespace PhpFix\Support;

enum Style: string
{
    case Plain = 'plain';
    case Loud = 'loud';
}

function shout(string $text): string
{
    return strtoupper($text);
}

class Formatter
{
    public static function wrap(string $who): string
    {
        return shout($who);
    }
}
