<?php

namespace PhpFix\Services;

use PhpFix\Support\Formatter;

trait Loggable
{
    public function logLine(string $message): string
    {
        return trim($message);
    }
}

class Greeter implements GreeterInterface
{
    use Loggable;

    public const DEFAULT_NAME = 'world';

    public function greet(): string
    {
        return $this->decorate(self::DEFAULT_NAME);
    }

    private function decorate(string $who): string
    {
        return Formatter::wrap($who);
    }
}
