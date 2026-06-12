<?php
declare(strict_types=1);

const BEATS_MONITOR_COMMAND_TABLE = 'beats_monitor_commands';

$apiValidateUrl = getenv('BEATS_MONITOR_VALIDATE_URL') ?: 'http://127.0.0.1:51842/api/v1/server/status';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    header('Cache-Control: no-store');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(405, ['sucesso' => false, 'mensagem' => 'Method not allowed.']);
}

$authorization = get_authorization_header();
if (!validate_monitor_token($authorization, $apiValidateUrl)) {
    json_response(401, ['sucesso' => false, 'mensagem' => 'Unauthorized.']);
}

$payload = read_json_payload();
$identity = identity_from_authorization($authorization);
$command = command_from_payload($payload, $identity);

$pdo = open_game_database(load_game_db_config());
ensure_command_table($pdo);
$commandId = enqueue_command($pdo, $command);

json_response(202, [
    'sucesso' => true,
    'mensagem' => 'Chat command queued for the game server.',
    'dados' => [
        'id' => $commandId,
        'source' => 'php_bridge',
    ],
]);

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

function read_json_payload(): array
{
    $raw = file_get_contents('php://input');
    $decoded = json_decode($raw === false ? '' : $raw, true);
    if (!is_array($decoded)) {
        json_response(400, ['sucesso' => false, 'mensagem' => 'Invalid JSON payload.']);
    }
    return $decoded;
}

function identity_from_authorization(string $authorization): array
{
    if (!preg_match('/^Bearer\s+([^.\s]+)\.[^\s]+$/i', $authorization, $match)) {
        return [];
    }

    $json = base64_url_decode($match[1]);
    if ($json === null) {
        return [];
    }

    $identity = json_decode($json, true);
    return is_array($identity) ? $identity : [];
}

function base64_url_decode(string $value): ?string
{
    $padding = strlen($value) % 4;
    if ($padding > 0) {
        $value .= str_repeat('=', 4 - $padding);
    }

    $decoded = base64_decode(strtr($value, '-_', '+/'), true);
    return $decoded === false ? null : $decoded;
}

function command_from_payload(array $payload, array $identity): array
{
    $endpoint = normalize_endpoint((string) ($payload['endpoint'] ?? ''));
    $body = $payload['body'] ?? [];
    if (!is_array($body)) {
        json_response(400, ['sucesso' => false, 'mensagem' => 'Invalid chat payload.']);
    }

    $requestedBy = trim((string) ($identity['player'] ?? ''));
    if ($requestedBy === '') {
        $requestedBy = trim((string) ($identity['subject'] ?? 'Penultima'));
    }
    if ($requestedBy === '') {
        $requestedBy = 'Penultima';
    }

    $base = [
        'requested_by' => $requestedBy,
        'requested_by_account_id' => max(0, (int) ($identity['account_id'] ?? 0)),
    ];

    if ($endpoint === 'server/broadcast') {
        return $base + [
            'action' => 'broadcast',
            'channel_key' => 'chat_global',
            'target_name' => '',
            'message' => chat_message($body['message'] ?? ''),
        ];
    }

    if ($endpoint === 'players/message') {
        return $base + [
            'action' => 'private',
            'channel_key' => 'chat_private',
            'target_name' => chat_target($body['player'] ?? $body['target'] ?? $body['name'] ?? ''),
            'message' => chat_message($body['message'] ?? ''),
        ];
    }

    if ($endpoint !== 'server/chat-message') {
        json_response(400, ['sucesso' => false, 'mensagem' => 'Unsupported chat endpoint.']);
    }

    $channel = (string) ($body['channel'] ?? '');
    if ($channel === 'chat_private') {
        return $base + [
            'action' => 'private',
            'channel_key' => 'chat_private',
            'target_name' => chat_target($body['target'] ?? $body['player'] ?? ''),
            'message' => chat_message($body['message'] ?? ''),
        ];
    }

    $outgoingChannel = $channel === 'chat_local' ? 'chat_global' : $channel;
    if (!in_array($outgoingChannel, ['chat_global', 'chat_trade', 'chat_help'], true)) {
        json_response(400, ['sucesso' => false, 'mensagem' => 'Unsupported chat channel.']);
    }

    return $base + [
        'action' => 'channel',
        'channel_key' => $outgoingChannel,
        'target_name' => '',
        'message' => chat_message($body['message'] ?? ''),
    ];
}

function normalize_endpoint(string $endpoint): string
{
    $endpoint = trim($endpoint);
    $endpoint = preg_replace('#^/+api/v1/+?#', '', $endpoint) ?? $endpoint;
    return trim($endpoint, '/');
}

function chat_message(mixed $value): string
{
    $message = trim((string) $value);
    if ($message === '') {
        json_response(400, ['sucesso' => false, 'mensagem' => 'Message is required.']);
    }
    return utf8_substr($message, 0, 1000);
}

function chat_target(mixed $value): string
{
    $target = trim((string) $value);
    if ($target === '') {
        json_response(400, ['sucesso' => false, 'mensagem' => 'Private message target is required.']);
    }
    return utf8_substr($target, 0, 255);
}

function utf8_substr(string $value, int $start, int $length): string
{
    return function_exists('mb_substr')
        ? mb_substr($value, $start, $length, 'UTF-8')
        : substr($value, $start, $length);
}

function load_game_db_config(): array
{
    $envConfig = [
        'host' => getenv('BEATS_MONITOR_DB_HOST') ?: '',
        'port' => getenv('BEATS_MONITOR_DB_PORT') ?: '',
        'user' => getenv('BEATS_MONITOR_DB_USER') ?: '',
        'password' => getenv('BEATS_MONITOR_DB_PASSWORD') ?: '',
        'database' => getenv('BEATS_MONITOR_DB_NAME') ?: '',
        'socket' => getenv('BEATS_MONITOR_DB_SOCKET') ?: '',
    ];
    if ($envConfig['user'] !== '' && $envConfig['database'] !== '') {
        return normalize_db_config($envConfig);
    }

    $myaacConfig = load_myaac_config();
    if (isset($myaacConfig['database_user'][0], $myaacConfig['database_name'][0])) {
        return normalize_db_config([
            'host' => (string) ($myaacConfig['database_host'] ?? '127.0.0.1'),
            'port' => (string) ($myaacConfig['database_port'] ?? '3306'),
            'user' => (string) $myaacConfig['database_user'],
            'password' => (string) ($myaacConfig['database_password'] ?? ''),
            'database' => (string) $myaacConfig['database_name'],
            'socket' => (string) ($myaacConfig['database_socket'] ?? ''),
        ]);
    }

    $serverPath = getenv('BEATS_MONITOR_SERVER_PATH') ?: (string) ($myaacConfig['server_path'] ?? '/home/penultima/Penultima-Server');
    $lua = [];
    foreach (['config.lua', 'config.local.lua'] as $file) {
        $lua = array_replace($lua, parse_lua_config(rtrim($serverPath, '/\\') . DIRECTORY_SEPARATOR . $file));
    }

    return normalize_db_config([
        'host' => (string) ($lua['mysqlHost'] ?? $lua['sqlHost'] ?? $lua['database_host'] ?? '127.0.0.1'),
        'port' => (string) ($lua['mysqlPort'] ?? $lua['sqlPort'] ?? $lua['database_port'] ?? '3306'),
        'user' => (string) ($lua['mysqlUser'] ?? $lua['sqlUser'] ?? $lua['database_username'] ?? ''),
        'password' => (string) ($lua['mysqlPass'] ?? $lua['sqlPass'] ?? $lua['database_password'] ?? ''),
        'database' => (string) ($lua['mysqlDatabase'] ?? $lua['sqlDatabase'] ?? $lua['database_schema'] ?? ''),
        'socket' => (string) ($lua['mysqlSock'] ?? ''),
    ]);
}

function load_myaac_config(): array
{
    $config = [];
    $baseConfig = realpath(__DIR__ . '/../config.php');
    if ($baseConfig !== false && is_file($baseConfig)) {
        require $baseConfig;
        $localConfig = dirname($baseConfig) . '/config.local.php';
        if (is_file($localConfig)) {
            require $localConfig;
        }
    }
    return is_array($config) ? $config : [];
}

function parse_lua_config(string $path): array
{
    if (!is_file($path) || !is_readable($path)) {
        return [];
    }

    $values = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (preg_match('/^\s*([A-Za-z0-9_]+)\s*=\s*"((?:\\\\.|[^"\\\\])*)"/', $line, $match)) {
            $values[$match[1]] = stripcslashes($match[2]);
            continue;
        }
        if (preg_match('/^\s*([A-Za-z0-9_]+)\s*=\s*([0-9]+)/', $line, $match)) {
            $values[$match[1]] = $match[2];
        }
    }
    return $values;
}

function normalize_db_config(array $config): array
{
    $config['host'] = $config['host'] !== '' ? $config['host'] : '127.0.0.1';
    $config['port'] = $config['port'] !== '' ? $config['port'] : '3306';
    if ($config['user'] === '' || $config['database'] === '') {
        json_response(500, ['sucesso' => false, 'mensagem' => 'Game database configuration was not found.']);
    }
    return $config;
}

function open_game_database(array $config): PDO
{
    $dsn = $config['socket'] !== ''
        ? 'mysql:unix_socket=' . $config['socket'] . ';dbname=' . $config['database'] . ';charset=utf8mb4'
        : 'mysql:host=' . $config['host'] . ';port=' . $config['port'] . ';dbname=' . $config['database'] . ';charset=utf8mb4';

    return new PDO($dsn, $config['user'], $config['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::MYSQL_ATTR_INIT_COMMAND => 'SET NAMES utf8mb4',
    ]);
}

function ensure_command_table(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS `' . BEATS_MONITOR_COMMAND_TABLE . '` (
            `id` bigint unsigned NOT NULL AUTO_INCREMENT,
            `action` varchar(32) NOT NULL,
            `channel_key` varchar(32) NOT NULL DEFAULT "",
            `target_name` varchar(255) NOT NULL DEFAULT "",
            `message` text NOT NULL,
            `requested_by` varchar(255) NOT NULL DEFAULT "Penultima",
            `requested_by_account_id` int unsigned NOT NULL DEFAULT 0,
            `status` varchar(16) NOT NULL DEFAULT "pending",
            `attempts` int unsigned NOT NULL DEFAULT 0,
            `error` text NULL,
            `created_at` int unsigned NOT NULL,
            `processed_at` int unsigned NULL,
            PRIMARY KEY (`id`),
            KEY `idx_beats_monitor_commands_status` (`status`, `id`),
            KEY `idx_beats_monitor_commands_created` (`created_at`, `id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
    );
}

function enqueue_command(PDO $pdo, array $command): int
{
    $statement = $pdo->prepare(
        'INSERT INTO `' . BEATS_MONITOR_COMMAND_TABLE . '`
        (`action`, `channel_key`, `target_name`, `message`, `requested_by`, `requested_by_account_id`, `created_at`)
        VALUES (:action, :channel_key, :target_name, :message, :requested_by, :requested_by_account_id, :created_at)'
    );
    $statement->execute([
        ':action' => $command['action'],
        ':channel_key' => $command['channel_key'],
        ':target_name' => $command['target_name'],
        ':message' => $command['message'],
        ':requested_by' => $command['requested_by'],
        ':requested_by_account_id' => $command['requested_by_account_id'],
        ':created_at' => time(),
    ]);
    return (int) $pdo->lastInsertId();
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
