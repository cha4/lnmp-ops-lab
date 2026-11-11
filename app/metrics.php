<?php
declare(strict_types=1);
header('Content-Type: text/plain; version=0.0.4; charset=utf-8');

$total = 0;
if (is_readable('/tmp/req_total')) {
    $total = (int)@file_get_contents('/tmp/req_total');
}

echo "# HELP app_requests_total Total HTTP requests handled by the app\n";
echo "# TYPE app_requests_total counter\n";
echo "app_requests_total {$total}\n";
