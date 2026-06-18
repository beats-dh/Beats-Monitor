<?php
declare(strict_types=1);

$logRoot = getenv('BEATS_MONITOR_LOG_ROOT') ?: '/home/penultima/Penultima-Server/logs';
$runtimeLogFile = getenv('BEATS_MONITOR_RUNTIME_LOG_FILE') ?: 'runtime.log';
$apiValidateUrl = getenv('BEATS_MONITOR_VALIDATE_URL') ?: 'http://127.0.0.1:51842/api/v1/server/status';
$tailBytes = (int) (getenv('BEATS_MONITOR_LOG_TAIL_BYTES') ?: (64 * 1024));
$tailBytes = max(4096, min($tailBytes, 1024 * 1024));
$tailLines = (int) (getenv('BEATS_MONITOR_LOG_HISTORY_LIMIT_LINES') ?: 300);
$tailLines = max(50, min($tailLines, 5000));

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    header('Cache-Control: no-store');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    json_response(405, ['sucesso' => false, 'mensagem' => 'Method not allowed.']);
}

$authorization = get_authorization_header();
if (!validate_monitor_token($authorization, $apiValidateUrl)) {
    json_response(401, ['sucesso' => false, 'mensagem' => 'Unauthorized.']);
}

$action = $_GET['action'] ?? 'list';
if ($action === 'list') {
    list_logs($logRoot, $runtimeLogFile);
}

if ($action === 'file') {
    read_log_file($logRoot, (string) ($_GET['path'] ?? ''), $tailBytes, $tailLines);
}

json_response(400, ['sucesso' => false, 'mensagem' => 'Invalid action.']);

function get_authorization_header(): string
{
    return (string) (
        $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? ''
    );
}

function validate_monitor_token(string $authorization, string $validateUrl): bool
{
    if (!preg_match('/^Bearer\s+\S+$/i', $authorization)) {
        return false;
    }

    if (function_exists('curl_init')) {
        $ch = curl_init($validateUrl);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HEADER => false,
            CURLOPT_TIMEOUT => 3,
            CURLOPT_HTTPHEADER => [
                'Authorization: ' . $authorization,
                'Accept: application/json',
            ],
        ]);
        curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        return $status === 200;
    }

    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'header' => "Authorization: {$authorization}\r\nAccept: application/json\r\n",
            'timeout' => 3,
            'ignore_errors' => true,
        ],
    ]);
    @file_get_contents($validateUrl, false, $context);
    $headers = $http_response_header ?? [];
    foreach ($headers as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d+)/', $header, $match)) {
            return (int) $match[1] === 200;
        }
    }
    return false;
}

function list_logs(string $logRoot, string $runtimeLogFile): void
{
    $root = realpath($logRoot);
    if ($root === false || !is_dir($root)) {
        json_response(500, [
            'sucesso' => false,
            'mensagem' => 'Log root was not found.',
        ]);
    }

    $root = rtrim(str_replace('\\', '/', $root), '/');
    $runtimeReal = realpath($root . '/' . $runtimeLogFile);
    $files = [];

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)
    );

    foreach ($iterator as $item) {
        if (!$item->isFile()) {
            continue;
        }

        $path = str_replace('\\', '/', $item->getPathname());
        $real = realpath($path);
        if ($real === false || !is_inside_root($real, $root)) {
            continue;
        }

        $relative = ltrim(substr($path, strlen($root)), '/');
        $size = @filesize($path);
        $mtime = @filemtime($path);
        $isRuntime = $relative === $runtimeLogFile
            || ($runtimeReal !== false && realpath($path) === $runtimeReal);

        $files[] = [
            'file' => $relative,
            'size' => is_int($size) ? $size : 0,
            'mtime_ms' => is_int($mtime) ? $mtime * 1000 : 0,
            'runtime' => $isRuntime,
        ];
    }

    usort($files, static function (array $left, array $right): int {
        if ($left['runtime'] !== $right['runtime']) {
            return $left['runtime'] ? -1 : 1;
        }
        if ($left['mtime_ms'] !== $right['mtime_ms']) {
            return $right['mtime_ms'] <=> $left['mtime_ms'];
        }
        return strcmp($left['file'], $right['file']);
    });

    json_response(200, [
        'sucesso' => true,
        'dados' => [
            'root' => $root,
            'runtime_file' => file_exists($root . '/' . $runtimeLogFile)
                ? $runtimeLogFile
                : ($files[0]['file'] ?? $runtimeLogFile),
            'files' => $files,
            'source' => 'php_bridge',
        ],
    ]);
}

function read_log_file(string $logRoot, string $relativePath, int $tailBytes, int $tailLines): void
{
    $root = realpath($logRoot);
    if ($root === false || !is_dir($root)) {
        json_response(500, ['sucesso' => false, 'mensagem' => 'Log root was not found.']);
    }

    $root = rtrim(str_replace('\\', '/', $root), '/');
    $relativePath = normalize_relative_path($relativePath);
    $path = realpath($root . '/' . $relativePath);

    if ($path === false || !is_file($path) || !is_inside_root($path, $root)) {
        json_response(404, [
            'sucesso' => false,
            'mensagem' => 'Log file was not found.',
        ]);
    }

    $path = str_replace('\\', '/', $path);
    $size = @filesize($path);
    $mtime = @filemtime($path);
    $size = is_int($size) ? $size : 0;
    $offset = max(0, $size - $tailBytes);
    $handle = @fopen($path, 'rb');
    if ($handle === false) {
        json_response(500, ['sucesso' => false, 'mensagem' => 'Log file could not be opened.']);
    }

    if ($offset > 0) {
        fseek($handle, $offset);
    }

    $content = stream_get_contents($handle);
    fclose($handle);
    if ($content === false) {
        $content = '';
    }

    if ($offset > 0) {
        $content = preg_replace('/^[^\r\n]*(\r?\n)?/', '', $content, 1) ?? $content;
    }

    $content = str_replace(["\r\n", "\r"], "\n", $content);
    $content = rtrim($content, "\n");
    $lines = $content === '' ? [] : explode("\n", $content);
    if (count($lines) > $tailLines) {
        $lines = array_slice($lines, -$tailLines);
    }

    json_response(200, [
        'sucesso' => true,
        'dados' => [
            'file' => $relativePath,
            'lines' => $lines,
            'size' => $size,
            'mtime_ms' => is_int($mtime) ? $mtime * 1000 : 0,
            'truncated' => $offset > 0,
            'missing' => false,
            'source' => 'php_bridge',
        ],
    ]);
}

function normalize_relative_path(string $path): string
{
    $path = str_replace('\\', '/', rawurldecode($path));
    $path = ltrim($path, '/');
    $parts = [];
    foreach (explode('/', $path) as $part) {
        if ($part === '' || $part === '.') {
            continue;
        }
        if ($part === '..') {
            array_pop($parts);
            continue;
        }
        $parts[] = $part;
    }
    return implode('/', $parts);
}

function is_inside_root(string $path, string $root): bool
{
    $path = rtrim(str_replace('\\', '/', $path), '/');
    $root = rtrim(str_replace('\\', '/', $root), '/');
    return $path === $root || str_starts_with($path, $root . '/');
}

function json_response(int $status, array $payload): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    $json = json_encode(
        $payload,
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE
    );
    echo $json === false
        ? '{"sucesso":false,"mensagem":"JSON encoding failed."}'
        : $json;
    exit;
}
