const assert = require("node:assert/strict");
const test = require("node:test");

process.env.BEATS_MONITOR_TOKEN_SECRET = "test-token-secret-that-is-long-enough";
process.env.BEATS_MONITOR_USER = "admin";
process.env.BEATS_MONITOR_PASSWORD = "admin";
process.env.BEATS_MONITOR_REQUIRED_PLAYER_NAME = "Waldir";
process.env.BEATS_MONITOR_GAME_AUTH = "false";

const {
  chatCommandFromRequest,
  chatHistoryWhereSql,
  privateRowVisibleToIdentity
} = require("./beats-monitor-api");

const waldir = { subject: "wmshuee@gmail.com", account_id: 8, player: "Waldir" };

test("private history only includes messages involving the authenticated monitor player", () => {
  assert.equal(
    privateRowVisibleToIdentity({ player_name: "Waldir", message: "to Tankso: test" }, waldir),
    true
  );
  assert.equal(
    privateRowVisibleToIdentity({ player_name: "Tankso", message: "to Waldir: answer" }, waldir),
    true
  );
  assert.equal(
    privateRowVisibleToIdentity({ player_name: "Tankso", message: "to Another: hidden" }, waldir),
    false
  );
  assert.equal(
    privateRowVisibleToIdentity({ player_name: "Tankso", message: "to Waldirx: hidden" }, waldir),
    false
  );
  assert.equal(
    privateRowVisibleToIdentity({ player_name: "Tankso", message: "to Waldir: answer" }, {}),
    true
  );
});

test("private history query scopes chat_private to the monitor player", () => {
  const whereSql = chatHistoryWhereSql(["chat_global", "chat_private"], waldir);

  assert.match(whereSql, /channel_key IN \('chat_global'\)/);
  assert.match(whereSql, /channel_key = 'chat_private'/);
  assert.match(whereSql, /player_name = 'Waldir'/);
  assert.match(whereSql, /message LIKE 'to Waldir:%'/);
});

test("private send command is queued as the authenticated monitor player", () => {
  const command = chatCommandFromRequest(
    "server/chat-message",
    { channel: "chat_private", target: "Tankso", message: "hello" },
    waldir
  );

  assert.equal(command.action, "private");
  assert.equal(command.channel_key, "chat_private");
  assert.equal(command.target_name, "Tankso");
  assert.equal(command.message, "hello");
  assert.equal(command.requested_by, "Waldir");
  assert.equal(command.requested_by_account_id, 8);
});
