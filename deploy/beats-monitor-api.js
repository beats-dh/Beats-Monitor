"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const APP_DIR = __dirname;
loadEnvFile(path.join(APP_DIR, ".env"));

const HOST = process.env.BEATS_MONITOR_HOST || "127.0.0.1";
const PORT = Number.parseInt(process.env.BEATS_MONITOR_PORT || "51842", 10);
const SERVER_ROOT = process.env.PENULTIMA_SERVER_ROOT || "/home/penultima/Penultima-Server";
const TOKEN_TTL_SECONDS = Number.parseInt(process.env.BEATS_MONITOR_TOKEN_TTL_SECONDS || "3600", 10);
const TOKEN_SECRET = process.env.BEATS_MONITOR_TOKEN_SECRET || "";
const LOGIN_USER = process.env.BEATS_MONITOR_USER || "";
const LOGIN_PASSWORD_HASH = process.env.BEATS_MONITOR_PASSWORD_HASH || "";
const LOGIN_PASSWORD = process.env.BEATS_MONITOR_PASSWORD || "";
const ALLOW_MUTATIONS = process.env.BEATS_MONITOR_ALLOW_MUTATIONS === "true";
const ALLOWED_ORIGIN = process.env.BEATS_MONITOR_ALLOWED_ORIGIN || "";
const GAME_AUTH_ENABLED = parseBoolean(process.env.BEATS_MONITOR_GAME_AUTH || "false");
const REQUIRED_PLAYER_NAME = process.env.BEATS_MONITOR_REQUIRED_PLAYER_NAME || "";
const MIN_GROUP_ID = Number.parseInt(process.env.BEATS_MONITOR_MIN_GROUP_ID || "6", 10);
const CHAT_SOURCE = process.env.BEATS_MONITOR_CHAT_SOURCE || "database";
const CHAT_HISTORY_LIMIT = Number.parseInt(process.env.BEATS_MONITOR_CHAT_HISTORY_LIMIT || "200", 10);
const CHAT_POLL_MS = Number.parseInt(process.env.BEATS_MONITOR_CHAT_POLL_MS || "2000", 10);
const ALLOW_CHAT_SEND = parseBoolean(process.env.BEATS_MONITOR_ALLOW_CHAT_SEND || process.env.BEATS_MONITOR_ALLOW_MUTATIONS || "false");

if (!TOKEN_SECRET || TOKEN_SECRET.length < 32) {
  failStart("BEATS_MONITOR_TOKEN_SECRET must be set and at least 32 characters.");
}

if (!GAME_AUTH_ENABLED && (!LOGIN_USER || (!LOGIN_PASSWORD_HASH && !LOGIN_PASSWORD))) {
  failStart("BEATS_MONITOR_USER and BEATS_MONITOR_PASSWORD_HASH must be set unless BEATS_MONITOR_GAME_AUTH=true.");
}

const clients = new Set();
let lastCpuSample = readCpuSample();
let lastChatMessageId = 0;

function failStart(message) {
  console.error(`[beats-monitor-api] ${message}`);
  process.exit(1);
}

function parseBoolean(value) {
  return ["1", "true", "yes", "on"].includes(String(value || "").toLowerCase());
}

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) {
      continue;
    }
    const key = trimmed.slice(0, trimmed.indexOf("=")).trim();
    let value = trimmed.slice(trimmed.indexOf("=") + 1).trim();
    value = value.replace(/^["']|["']$/g, "");
    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

function corsHeaders(request) {
  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  };
  const origin = request.headers.origin;
  if (ALLOWED_ORIGIN === "*") {
    headers["Access-Control-Allow-Origin"] = "*";
  } else if (ALLOWED_ORIGIN && origin === ALLOWED_ORIGIN) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers.Vary = "Origin";
  }
  return headers;
}

function sendJson(request, response, statusCode, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    ...corsHeaders(request),
    "Content-Length": Buffer.byteLength(body)
  });
  response.end(body);
}

function sendOptions(request, response) {
  response.writeHead(204, {
    ...corsHeaders(request),
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Max-Age": "86400"
  });
  response.end();
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk.toString("utf8");
      if (body.length > 1024 * 1024) {
        reject(new Error("Request body is too large."));
        request.destroy();
      }
    });
    request.on("end", () => {
      if (!body.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch {
        resolve({});
      }
    });
    request.on("error", reject);
  });
}

function base64Url(input) {
  return Buffer.from(input).toString("base64url");
}

function signToken(payload) {
  const encoded = base64Url(JSON.stringify(payload));
  const signature = crypto.createHmac("sha256", TOKEN_SECRET).update(encoded).digest("base64url");
  return `${encoded}.${signature}`;
}

function verifyToken(token) {
  if (!token || !token.includes(".")) {
    return null;
  }
  const [encoded, signature] = token.split(".");
  const expected = crypto.createHmac("sha256", TOKEN_SECRET).update(encoded).digest("base64url");
  if (!constantEquals(signature, expected)) {
    return null;
  }
  try {
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) {
      return null;
    }
    return payload;
  } catch {
    return null;
  }
}

function constantEquals(left, right) {
  const leftBuffer = Buffer.from(String(left));
  const rightBuffer = Buffer.from(String(right));
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function hashPassword(password) {
  return crypto.createHash("sha256").update(String(password), "utf8").digest("hex");
}

function hashSha1(password) {
  return crypto.createHash("sha1").update(String(password), "utf8").digest("hex");
}

function authenticateConfiguredLogin(username, password) {
  if (!LOGIN_USER || (!LOGIN_PASSWORD_HASH && !LOGIN_PASSWORD)) {
    return null;
  }

  const suppliedHash = hashPassword(password);
  const expectedHash = LOGIN_PASSWORD_HASH || hashPassword(LOGIN_PASSWORD);
  if (username !== LOGIN_USER || !constantEquals(suppliedHash, expectedHash)) {
    return null;
  }

  return {
    subject: username,
    auth: "configured",
    account_id: 0,
    player: ""
  };
}

function authenticateGameAccount(username, password) {
  if (!GAME_AUTH_ENABLED || !username || !password) {
    return null;
  }

  const safeUsername = sqlString(username);
  const safePlayerName = sqlString(REQUIRED_PLAYER_NAME);
  const fields = ["account_id", "account_name", "email", "stored_password", "account_type", "max_group_id", "required_group_id", "required_player"];
  const requiredGroupColumn = REQUIRED_PLAYER_NAME
    ? `MAX(CASE WHEN p.name = '${safePlayerName}' THEN p.group_id ELSE 0 END) AS required_group_id`
    : "MAX(p.group_id) AS required_group_id";
  const requiredPlayerColumn = REQUIRED_PLAYER_NAME
    ? `MAX(CASE WHEN p.name = '${safePlayerName}' THEN p.name ELSE '' END) AS required_player`
    : "MAX(p.name) AS required_player";
  const sql = [
    "SELECT a.id AS account_id, a.name AS account_name, a.email, a.password AS stored_password, a.type AS account_type,",
    "MAX(p.group_id) AS max_group_id,",
    requiredGroupColumn + ",",
    requiredPlayerColumn,
    "FROM accounts a",
    "LEFT JOIN players p ON p.account_id = a.id",
    `WHERE a.email = '${safeUsername}' OR a.name = '${safeUsername}'`,
    "GROUP BY a.id, a.name, a.email, a.password, a.type",
    "LIMIT 1;"
  ].join(" ");

  let rows;
  try {
    rows = mysqlQuery(sql, fields);
  } catch (error) {
    console.error("[beats-monitor-api] game auth query failed:", error.message);
    return null;
  }

  if (!rows.length) {
    return null;
  }

  const row = rows[0];
  const storedPassword = String(row.stored_password || "").trim().toLowerCase();
  const suppliedPassword = hashSha1(password).toLowerCase();
  if (!constantEquals(storedPassword, suppliedPassword)) {
    return null;
  }

  const maxGroupId = toInt(row.max_group_id);
  const requiredGroupId = toInt(row.required_group_id);
  const groupId = REQUIRED_PLAYER_NAME ? requiredGroupId : maxGroupId;
  if (groupId < MIN_GROUP_ID) {
    return null;
  }

  return {
    subject: row.email || row.account_name,
    auth: "game-account",
    account_id: toInt(row.account_id),
    player: REQUIRED_PLAYER_NAME ? row.required_player : "",
    group_id: groupId
  };
}

function getBearerToken(request) {
  const header = request.headers.authorization || "";
  const match = String(header).match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : "";
}

function isAuthenticated(request) {
  return Boolean(verifyToken(getBearerToken(request)));
}

function authenticatedIdentity(request) {
  return verifyToken(getBearerToken(request));
}

function routePath(request) {
  const url = new URL(request.url, `http://${request.headers.host || `${HOST}:${PORT}`}`);
  let pathname = url.pathname;
  if (pathname.startsWith("/beats-monitor-api/")) {
    pathname = pathname.slice("/beats-monitor-api".length);
  }
  return {
    url,
    route: pathname.replace(/^\/api\/v1\/?/, "").replace(/^\/+/, "")
  };
}

function parseLuaConfig(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }
  const config = {};
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.+?)\s*(?:--.*)?$/);
    if (!match) {
      continue;
    }
    const key = match[1];
    let value = match[2].trim();
    const stringMatch = value.match(/^"([^"]*)"$/);
    if (stringMatch) {
      value = stringMatch[1];
    } else if (/^\d+$/.test(value)) {
      value = Number.parseInt(value, 10);
    }
    config[key] = value;
  }
  return config;
}

function serverConfig() {
  return {
    ...parseLuaConfig(path.join(SERVER_ROOT, "config.lua")),
    ...parseLuaConfig(path.join(SERVER_ROOT, "config.local.lua"))
  };
}

function dbConfig() {
  const config = serverConfig();
  return {
    host: String(config.mysqlHost || "127.0.0.1"),
    user: String(config.mysqlUser || "root"),
    password: String(config.mysqlPass || ""),
    database: String(config.mysqlDatabase || "penultima"),
    socket: String(config.mysqlSock || ""),
    port: Number.parseInt(String(config.mysqlPort || "3306"), 10)
  };
}

function mysqlQuery(sql, fields) {
  const db = dbConfig();
  const args = ["--batch", "--skip-column-names", "--raw"];
  if (db.socket) {
    args.push("--protocol=SOCKET", `--socket=${db.socket}`);
  } else {
    args.push(`--host=${db.host}`, `--port=${db.port}`);
  }
  args.push(`--user=${db.user}`, db.database, "--execute", sql);

  const output = execFileSync("mysql", args, {
    encoding: "utf8",
    env: { ...process.env, MYSQL_PWD: db.password },
    timeout: 5000
  }).trim();

  if (!output) {
    return [];
  }
  return output.split(/\r?\n/).map((line) => {
    const values = line.split("\t");
    const row = {};
    fields.forEach((field, index) => {
      row[field] = values[index] ?? "";
    });
    return row;
  });
}

function mysqlExecute(sql) {
  mysqlQuery(sql, []);
}

function mysqlScalar(sql) {
  const rows = mysqlQuery(sql, ["value"]);
  return rows[0]?.value ?? "";
}

function sqlString(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}

function toInt(value, fallback = 0) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toBool(value) {
  return ["1", "true", "yes"].includes(String(value).toLowerCase());
}

function vocationName(id) {
  const value = toInt(id);
  const names = {
    0: "None",
    1: "Sorcerer",
    2: "Druid",
    3: "Paladin",
    4: "Knight",
    5: "Master Sorcerer",
    6: "Elder Druid",
    7: "Royal Paladin",
    8: "Elite Knight",
    9: "Monk",
    10: "Exalted Monk"
  };
  return names[value] || String(id || "Unknown");
}

function canaryPid() {
  try {
    return execFileSync("pgrep", ["-n", "-u", "penultima", "-x", "canary"], { encoding: "utf8", timeout: 1000 }).trim();
  } catch {
    return "";
  }
}

function commandText(command, args, fallback = "") {
  try {
    return execFileSync(command, args, { encoding: "utf8", timeout: 3000 }).trim();
  } catch {
    return fallback;
  }
}

function gameProcessStartTimeMs(pid) {
  if (!pid) {
    return 0;
  }
  const started = commandText("ps", ["-o", "lstart=", "-p", pid], "");
  const parsed = Date.parse(started);
  return Number.isFinite(parsed) ? parsed : 0;
}

function chatBridgeActive() {
  const pid = canaryPid();
  if (!pid) {
    return false;
  }

  try {
    const binaryMtime = fs.statSync(path.join(SERVER_ROOT, "canary")).mtimeMs;
    const processStarted = gameProcessStartTimeMs(pid);
    return processStarted > 0 && processStarted + 1000 >= binaryMtime;
  } catch {
    return false;
  }
}

function maxPlayers() {
  const config = serverConfig();
  return toInt(config.maxPlayers, 0);
}

function buildServerStatus() {
  const config = serverConfig();
  const pid = canaryPid();
  const online = Boolean(pid);
  const uptime = pid ? toInt(commandText("ps", ["-o", "etimes=", "-p", pid], "0")) : 0;
  const playersOnline = toInt(safeMysqlScalar("SELECT COUNT(*) FROM players_online;"));
  const gitVersion = commandText("git", ["-C", SERVER_ROOT, "rev-parse", "--short", "HEAD"], "unknown");

  return {
    sucesso: true,
    dados: {
      max_players: maxPlayers(),
      players_online: playersOnline,
      server_ip: String(config.ip || "127.0.0.1"),
      server_location: String(config.location || "South America"),
      server_name: String(config.serverName || "Penultima"),
      server_version: gitVersion,
      status: online ? "online" : "offline",
      uptime
    }
  };
}

function safeMysqlScalar(sql) {
  try {
    return mysqlScalar(sql);
  } catch {
    return "";
  }
}

function ensureBeatsMonitorCommandTable() {
  mysqlExecute([
    "CREATE TABLE IF NOT EXISTS `beats_monitor_commands` (",
    "`id` bigint unsigned NOT NULL AUTO_INCREMENT,",
    "`action` varchar(32) NOT NULL,",
    "`channel_key` varchar(32) NOT NULL DEFAULT '',",
    "`target_name` varchar(255) NOT NULL DEFAULT '',",
    "`message` text NOT NULL,",
    "`requested_by` varchar(255) NOT NULL DEFAULT 'Beats Monitor',",
    "`requested_by_account_id` int unsigned NOT NULL DEFAULT 0,",
    "`status` varchar(16) NOT NULL DEFAULT 'pending',",
    "`attempts` int unsigned NOT NULL DEFAULT 0,",
    "`error` text NULL,",
    "`created_at` int unsigned NOT NULL,",
    "`processed_at` int unsigned NULL,",
    "PRIMARY KEY (`id`),",
    "KEY `idx_beats_monitor_commands_status` (`status`, `id`),",
    "KEY `idx_beats_monitor_commands_created` (`created_at`, `id`)",
    ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
  ].join(" "));
}

function enqueueBeatsMonitorCommand(command) {
  if (!chatBridgeActive()) {
    const error = new Error("Game chat bridge is not active until the next game server restart.");
    error.statusCode = 503;
    throw error;
  }

  ensureBeatsMonitorCommandTable();
  const now = Math.floor(Date.now() / 1000);
  const sql = [
    "INSERT INTO `beats_monitor_commands`",
    "(`action`, `channel_key`, `target_name`, `message`, `requested_by`, `requested_by_account_id`, `created_at`)",
    "VALUES (",
    `'${sqlString(command.action)}',`,
    `'${sqlString(command.channel_key || "")}',`,
    `'${sqlString(command.target_name || "")}',`,
    `'${sqlString(String(command.message || "").slice(0, 1000))}',`,
    `'${sqlString(command.requested_by || "Beats Monitor")}',`,
    `${toInt(command.requested_by_account_id)},`,
    `${now}`,
    ");"
  ].join(" ");
  mysqlExecute(sql);
}

function chatCommandFromRequest(route, body, identity) {
  const actor = identity?.player || identity?.subject || "Beats Monitor";
  const accountId = toInt(identity?.account_id);

  if (route === "server/broadcast") {
    return {
      action: "broadcast",
      channel_key: "chat_global",
      message: body.message,
      requested_by: actor,
      requested_by_account_id: accountId
    };
  }

  if (route === "players/message") {
    return {
      action: "private",
      channel_key: "chat_private",
      target_name: body.player || body.target || body.name,
      message: body.message,
      requested_by: actor,
      requested_by_account_id: accountId
    };
  }

  const channel = String(body.channel || "");
  if (channel === "chat_local") {
    throw new Error("Local chat cannot be sent from Beats Monitor because it has no in-game position.");
  }
  if (channel === "chat_private") {
    return {
      action: "private",
      channel_key: "chat_private",
      target_name: body.target || body.player || "",
      message: body.message,
      requested_by: actor,
      requested_by_account_id: accountId
    };
  }
  if (!["chat_global", "chat_trade", "chat_help"].includes(channel)) {
    throw new Error("Unsupported chat channel.");
  }
  return {
    action: "channel",
    channel_key: channel,
    message: body.message,
    requested_by: actor,
    requested_by_account_id: accountId
  };
}

function buildPlayersPayload() {
  const fields = ["id", "name", "level", "vocation", "online_time"];
  const sql = [
    "SELECT p.id, p.name, p.level, p.vocation,",
    "GREATEST(0, UNIX_TIMESTAMP() - IFNULL(p.lastlogin, UNIX_TIMESTAMP())) AS online_time",
    "FROM players_online po",
    "JOIN players p ON p.id = po.player_id",
    "ORDER BY p.level DESC, p.name ASC;"
  ].join(" ");

  let players = [];
  try {
    players = mysqlQuery(sql, fields).map((row) => ({
      id: toInt(row.id),
      name: row.name,
      level: toInt(row.level),
      vocation: vocationName(row.vocation),
      online_time: toInt(row.online_time)
    }));
  } catch {
    players = [];
  }

  return {
    sucesso: true,
    dados: {
      total: players.length,
      max: maxPlayers(),
      players
    }
  };
}

function chatEnabled() {
  return CHAT_SOURCE === "database";
}

function normalizeChatChannels(channels) {
  const allowed = new Set(["chat_local", "chat_global", "chat_trade", "chat_help", "chat_private"]);
  if (!Array.isArray(channels) || !channels.length) {
    return Array.from(allowed);
  }
  return channels.filter((channel) => allowed.has(String(channel)));
}

function chatRowToPayload(row) {
  return {
    player: row.player_name || "Unknown",
    message: row.message || "",
    timestamp: toInt(row.created_at, Math.floor(Date.now() / 1000)),
    level: toInt(row.player_level)
  };
}

function queryChatRows(whereSql, limit) {
  if (!chatEnabled()) {
    return [];
  }

  const fields = ["id", "channel_key", "player_name", "player_level", "message", "created_at"];
  const sql = [
    "SELECT id, channel_key, player_name, player_level,",
    "REPLACE(REPLACE(message, CHAR(9), '    '), CHAR(10), ' ') AS message, created_at",
    "FROM beats_monitor_chat_messages",
    whereSql,
    "ORDER BY id DESC",
    `LIMIT ${Math.max(1, Math.min(toInt(limit, CHAT_HISTORY_LIMIT), 1000))};`
  ].join(" ");

  try {
    return mysqlQuery(sql, fields);
  } catch {
    return [];
  }
}

function buildChatHistoryPayload(channels) {
  const selected = normalizeChatChannels(channels);
  const result = {
    chat_local: [],
    chat_global: [],
    chat_trade: [],
    chat_help: [],
    chat_private: []
  };

  if (!selected.length) {
    return result;
  }

  const channelSql = selected.map((channel) => `'${sqlString(channel)}'`).join(",");
  const rows = queryChatRows(`WHERE channel_key IN (${channelSql})`, CHAT_HISTORY_LIMIT).reverse();
  rows.forEach((row) => {
    if (!result[row.channel_key]) {
      return;
    }
    result[row.channel_key].push(chatRowToPayload(row));
  });

  return result;
}

function initializeChatCursor() {
  if (!chatEnabled()) {
    return;
  }
  lastChatMessageId = toInt(safeMysqlScalar("SELECT IFNULL(MAX(id), 0) FROM beats_monitor_chat_messages;"));
}

function pollChatMessages() {
  if (!chatEnabled()) {
    return;
  }

  const fields = ["id", "channel_key", "player_name", "player_level", "message", "created_at"];
  const sql = [
    "SELECT id, channel_key, player_name, player_level,",
    "REPLACE(REPLACE(message, CHAR(9), '    '), CHAR(10), ' ') AS message, created_at",
    "FROM beats_monitor_chat_messages",
    `WHERE id > ${lastChatMessageId}`,
    "ORDER BY id ASC",
    "LIMIT 200;"
  ].join(" ");

  let rows = [];
  try {
    rows = mysqlQuery(sql, fields);
  } catch {
    return;
  }

  rows.forEach((row) => {
    lastChatMessageId = Math.max(lastChatMessageId, toInt(row.id));
    broadcastEvent(row.channel_key, chatRowToPayload(row));
  });
}

function buildPlayerPayload(name) {
  const safeName = sqlString(name);
  const fields = [
    "id", "name", "level", "vocation", "health", "max_health", "mana", "max_mana",
    "magic", "fist", "club", "sword", "axe", "distance", "shielding", "fishing",
    "online", "premium"
  ];
  const sql = [
    "SELECT p.id, p.name, p.level, p.vocation, p.health, p.healthmax, p.mana, p.manamax,",
    "p.maglevel, p.skill_fist, p.skill_club, p.skill_sword, p.skill_axe, p.skill_dist,",
    "p.skill_shielding, p.skill_fishing, IF(po.player_id IS NULL, 0, 1) AS online,",
    "IF(IFNULL(a.premdays, 0) > 0, 1, 0) AS premium",
    "FROM players p",
    "LEFT JOIN players_online po ON po.player_id = p.id",
    "LEFT JOIN accounts a ON a.id = p.account_id",
    `WHERE p.name = '${safeName}' LIMIT 1;`
  ].join(" ");

  const rows = mysqlQuery(sql, fields);
  if (!rows.length) {
    return null;
  }

  const row = rows[0];
  return {
    id: toInt(row.id),
    name: row.name,
    level: toInt(row.level),
    vocation: vocationName(row.vocation),
    health: toInt(row.health),
    max_health: toInt(row.max_health, 1),
    mana: toInt(row.mana),
    max_mana: toInt(row.max_mana, 1),
    online: toBool(row.online),
    premium: toBool(row.premium),
    skills: {
      magic: toInt(row.magic),
      fist: toInt(row.fist),
      club: toInt(row.club),
      sword: toInt(row.sword),
      axe: toInt(row.axe),
      distance: toInt(row.distance),
      shielding: toInt(row.shielding),
      fishing: toInt(row.fishing)
    }
  };
}

function readCpuSample() {
  try {
    const parts = fs.readFileSync("/proc/stat", "utf8").split(/\r?\n/)[0].trim().split(/\s+/).slice(1).map(Number);
    const idle = parts[3] + (parts[4] || 0);
    const total = parts.reduce((sum, value) => sum + value, 0);
    return { idle, total };
  } catch {
    return { idle: 0, total: 0 };
  }
}

function cpuUsagePercent() {
  const current = readCpuSample();
  const idleDiff = current.idle - lastCpuSample.idle;
  const totalDiff = current.total - lastCpuSample.total;
  lastCpuSample = current;
  if (totalDiff <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, (1 - idleDiff / totalDiff) * 100));
}

function memInfo() {
  const result = {};
  try {
    const text = fs.readFileSync("/proc/meminfo", "utf8");
    for (const line of text.split(/\r?\n/)) {
      const match = line.match(/^([^:]+):\s+(\d+)/);
      if (match) {
        result[match[1]] = Number.parseInt(match[2], 10);
      }
    }
  } catch {
    // Keep defaults.
  }
  return result;
}

function processMemoryMb(pid) {
  if (!pid) {
    return 0;
  }
  try {
    const status = fs.readFileSync(`/proc/${pid}/status`, "utf8");
    const rss = status.match(/^VmRSS:\s+(\d+)/m);
    return rss ? Number.parseInt(rss[1], 10) / 1024 : 0;
  } catch {
    return 0;
  }
}

function cpuName() {
  try {
    const match = fs.readFileSync("/proc/cpuinfo", "utf8").match(/^model name\s+:\s+(.+)$/m);
    return match ? match[1] : os.cpus()[0]?.model || "CPU";
  } catch {
    return os.cpus()[0]?.model || "CPU";
  }
}

function buildSystemPayload() {
  const pid = canaryPid();
  const cpu = cpuUsagePercent();
  const mem = memInfo();
  const totalGb = (mem.MemTotal || 0) / 1024 / 1024;
  const availableGb = (mem.MemAvailable || 0) / 1024 / 1024;
  const usagePercent = totalGb > 0 ? ((totalGb - availableGb) / totalGb) * 100 : 0;
  const procMemory = processMemoryMb(pid);

  return {
    cpu: {
      usage_percent: cpu,
      kernel_time_percent: 0,
      user_time_percent: cpu
    },
    memory: {
      private_usage_mb: procMemory,
      working_set_mb: procMemory,
      page_fault_count: 0,
      peak_working_set_mb: procMemory,
      quota_paged_pool_mb: 0,
      quota_peak_paged_pool_mb: 0
    },
    process: {
      name: pid ? "canary" : "canary offline"
    },
    system: {
      cpu: {
        name: cpuName(),
        usage_percent: cpu,
        idle_time_percent: Math.max(0, 100 - cpu),
        kernel_time_percent: 0,
        user_time_percent: cpu
      },
      cpu_cores: os.cpus().length,
      architecture: process.arch === "x64" ? 9 : 0,
      memory: {
        available_gb: availableGb,
        total_gb: totalGb,
        usage_percent: usagePercent,
        performance: {
          commit: {
            total_gb: Math.max(0, totalGb - availableGb)
          }
        }
      }
    }
  };
}

async function handleApiRequest(request, response) {
  if (request.method === "OPTIONS") {
    sendOptions(request, response);
    return;
  }

  const { url, route } = routePath(request);

  if (request.method === "POST" && route === "login") {
    const body = await readBody(request);
    const suppliedUser = String(body.username || "");
    const suppliedPassword = String(body.password || "");
    const identity = authenticateConfiguredLogin(suppliedUser, suppliedPassword)
      || authenticateGameAccount(suppliedUser, suppliedPassword);

    if (!identity) {
      sendJson(request, response, 401, { sucesso: false, mensagem: "Invalid credentials." });
      return;
    }

    const now = Math.floor(Date.now() / 1000);
    sendJson(request, response, 200, {
      token: signToken({ ...identity, iat: now, exp: now + TOKEN_TTL_SECONDS }),
      expires_in: TOKEN_TTL_SECONDS
    });
    return;
  }

  const identity = authenticatedIdentity(request);
  if (!identity) {
    sendJson(request, response, 401, { sucesso: false, mensagem: "Unauthorized." });
    return;
  }

  if (request.method === "GET" && route === "server/status") {
    sendJson(request, response, 200, buildServerStatus());
    return;
  }

  if (request.method === "GET" && route === "playersOnline") {
    sendJson(request, response, 200, buildPlayersPayload());
    return;
  }

  if (request.method === "GET" && route === "players/banned") {
    sendJson(request, response, 200, []);
    return;
  }

  if (request.method === "GET" && route.startsWith("players/ban/history")) {
    sendJson(request, response, 200, []);
    return;
  }

  if (request.method === "GET" && route.startsWith("players/")) {
    const name = decodeURIComponent(route.slice("players/".length));
    const player = buildPlayerPayload(name);
    if (!player) {
      sendJson(request, response, 404, { sucesso: false, mensagem: "Player not found." });
      return;
    }
    sendJson(request, response, 200, { sucesso: true, dados: player });
    return;
  }

  if (request.method === "POST" && ["server/broadcast", "server/chat-message", "players/message"].includes(route)) {
    const body = await readBody(request);
    if (!ALLOW_CHAT_SEND) {
      sendJson(request, response, 403, {
        sucesso: false,
        mensagem: "Chat sending is disabled in this production adapter."
      });
      return;
    }
    try {
      const command = chatCommandFromRequest(route, body, identity);
      if (!String(command.message || "").trim()) {
        sendJson(request, response, 400, { sucesso: false, mensagem: "Message is required." });
        return;
      }
      if (command.action === "private" && !String(command.target_name || "").trim()) {
        sendJson(request, response, 400, { sucesso: false, mensagem: "Private message target is required." });
        return;
      }
      enqueueBeatsMonitorCommand(command);
      sendJson(request, response, 202, { sucesso: true, mensagem: "Chat command queued for the game server." });
    } catch (error) {
      sendJson(request, response, error.statusCode || 400, { sucesso: false, mensagem: error.message });
    }
    return;
  }

  if (request.method === "POST" && ["server/state", "players/ban", "players/kick"].includes(route)) {
    await readBody(request);
    if (!ALLOW_MUTATIONS) {
      sendJson(request, response, 403, {
        sucesso: false,
        mensagem: "Mutating actions are disabled in this production adapter."
      });
      return;
    }
    sendJson(request, response, 501, {
      sucesso: false,
      mensagem: "Mutating actions must be wired to explicit audited server commands before enabling."
    });
    return;
  }

  sendJson(request, response, 404, { sucesso: false, mensagem: `Unknown endpoint: ${url.pathname}` });
}

function encodeWebSocketFrame(payload) {
  const data = Buffer.from(JSON.stringify(payload), "utf8");
  if (data.length < 126) {
    return Buffer.concat([Buffer.from([0x81, data.length]), data]);
  }
  if (data.length <= 0xffff) {
    const header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(data.length, 2);
    return Buffer.concat([header, data]);
  }
  const header = Buffer.alloc(10);
  header[0] = 0x81;
  header[1] = 127;
  header.writeBigUInt64BE(BigInt(data.length), 2);
  return Buffer.concat([header, data]);
}

function decodeWebSocketMessages(buffer) {
  const messages = [];
  let offset = 0;

  while (offset + 2 <= buffer.length) {
    const opcode = buffer[offset] & 0x0f;
    let length = buffer[offset + 1] & 0x7f;
    const masked = Boolean(buffer[offset + 1] & 0x80);
    offset += 2;

    if (length === 126) {
      if (offset + 2 > buffer.length) break;
      length = buffer.readUInt16BE(offset);
      offset += 2;
    } else if (length === 127) {
      if (offset + 8 > buffer.length) break;
      length = Number(buffer.readBigUInt64BE(offset));
      offset += 8;
    }

    let mask = null;
    if (masked) {
      if (offset + 4 > buffer.length) break;
      mask = buffer.subarray(offset, offset + 4);
      offset += 4;
    }

    if (offset + length > buffer.length) break;
    const payload = Buffer.from(buffer.subarray(offset, offset + length));
    offset += length;

    if (mask) {
      for (let index = 0; index < payload.length; index += 1) {
        payload[index] ^= mask[index % 4];
      }
    }

    if (opcode === 0x1) {
      messages.push(payload.toString("utf8"));
    }
  }

  return messages;
}

function sendToClient(client, payload) {
  if (!client.socket.destroyed) {
    client.socket.write(encodeWebSocketFrame(payload));
  }
}

function broadcastEvent(eventName, data) {
  for (const client of clients) {
    if (client.authenticated && client.subscriptions.has(eventName)) {
      sendToClient(client, { type: "event", event: eventName, data });
    }
  }
}

function handleSocketMessage(client, message) {
  let payload;
  try {
    payload = JSON.parse(message);
  } catch {
    return;
  }

  if (payload.type === "ping") {
    sendToClient(client, { type: "pong" });
    return;
  }

  const tokenPayload = client.authenticated ? client.identity : verifyToken(payload.token);
  if (!client.authenticated && !tokenPayload) {
    sendToClient(client, { type: "error", message: "Unauthorized." });
    return;
  }
  client.authenticated = true;
  client.identity = tokenPayload || client.identity;

  if (payload.type === "subscribe" && Array.isArray(payload.events)) {
    payload.events.forEach((eventName) => client.subscriptions.add(eventName));
    sendToClient(client, { type: "subscribed", events: Array.from(client.subscriptions) });
    if (client.subscriptions.has("system_resources")) {
      sendToClient(client, { type: "event", event: "system_resources", data: buildSystemPayload() });
    }
    if (client.subscriptions.has("server_status")) {
      sendToClient(client, { type: "event", event: "server_status", data: buildServerStatus().dados });
    }
    if (client.subscriptions.has("chat_history")) {
      sendToClient(client, { type: "event", event: "chat_history", data: buildChatHistoryPayload(payload.events) });
    }
    return;
  }

  if (payload.type === "chat_history") {
    sendToClient(client, { type: "event", event: "chat_history", data: buildChatHistoryPayload(payload.channels) });
    return;
  }

  if (payload.type === "chat_message") {
    if (!ALLOW_CHAT_SEND) {
      sendToClient(client, { type: "error", message: "Chat sending is disabled in this production adapter." });
      return;
    }

    try {
      const body = payload.data || {};
      const command = chatCommandFromRequest("server/chat-message", body, client.identity);
      if (!String(command.message || "").trim()) {
        sendToClient(client, { type: "error", message: "Message is required." });
        return;
      }
      if (command.action === "private" && !String(command.target_name || "").trim()) {
        sendToClient(client, { type: "error", message: "Private message target is required." });
        return;
      }
      enqueueBeatsMonitorCommand(command);
      sendToClient(client, { type: "chat_send_ack", message: "Chat command queued for the game server." });
    } catch (error) {
      sendToClient(client, { type: "error", message: error.message });
    }
    return;
  }

  if (payload.type === "unsubscribe") {
    if (Array.isArray(payload.events) && payload.events.length) {
      payload.events.forEach((eventName) => client.subscriptions.delete(eventName));
    } else {
      client.subscriptions.clear();
    }
  }
}

function handleUpgrade(request, socket) {
  const url = new URL(request.url, `http://${request.headers.host || `${HOST}:${PORT}`}`);
  const pathname = url.pathname.startsWith("/beats-monitor-api/")
    ? url.pathname.slice("/beats-monitor-api".length)
    : url.pathname;

  if (pathname !== "/ws") {
    socket.destroy();
    return;
  }

  const key = request.headers["sec-websocket-key"];
  if (!key) {
    socket.destroy();
    return;
  }

  const accept = crypto
    .createHash("sha1")
    .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
    .digest("base64");

  socket.write([
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${accept}`,
    "",
    ""
  ].join("\r\n"));

  const client = { socket, authenticated: false, subscriptions: new Set() };
  clients.add(client);
  sendToClient(client, { type: "connected" });

  socket.on("data", (chunk) => {
    decodeWebSocketMessages(chunk).forEach((message) => handleSocketMessage(client, message));
  });
  socket.on("close", () => clients.delete(client));
  socket.on("error", () => clients.delete(client));
}

const server = http.createServer((request, response) => {
  handleApiRequest(request, response).catch((error) => {
    console.error("[beats-monitor-api]", error);
    sendJson(request, response, 500, { sucesso: false, mensagem: "Internal server error." });
  });
});

server.on("upgrade", handleUpgrade);

setInterval(() => {
  broadcastEvent("system_resources", buildSystemPayload());
  broadcastEvent("server_status", buildServerStatus().dados);
}, 2000);

setInterval(pollChatMessages, Math.max(1000, CHAT_POLL_MS));

server.listen(PORT, HOST, () => {
  initializeChatCursor();
  console.log(`[beats-monitor-api] listening on http://${HOST}:${PORT}`);
});

process.on("SIGTERM", () => server.close(() => process.exit(0)));
process.on("SIGINT", () => server.close(() => process.exit(0)));
