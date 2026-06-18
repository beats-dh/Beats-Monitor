#!/usr/bin/env python3
"""
Local live remote-control host for Penultima Beats Monitor.

This intentionally runs on the Windows desktop that has the Tibia client open.
It does not touch the production game server. The desktop browser captures the
Tibia window with getDisplayMedia, the phone receives that stream with WebRTC,
and this helper injects phone input into the local Tibia window.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import secrets
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse


DEFAULT_PORT = 51844
DEFAULT_WINDOW_MATCH = "Tibia - Waldir"

SW_RESTORE = 9
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
INPUT_KEYBOARD = 1


user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", ctypes.c_ushort),
        ("wScan", ctypes.c_ushort),
        ("dwFlags", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class INPUTUNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", ctypes.c_ulong), ("union", INPUTUNION)]


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", ctypes.c_long),
        ("top", ctypes.c_long),
        ("right", ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]


EnumWindowsProc = ctypes.WINFUNCTYPE(
    ctypes.c_bool,
    ctypes.c_void_p,
    ctypes.c_void_p,
)


VK_BY_KEY = {
    "Backspace": 0x08,
    "Tab": 0x09,
    "Enter": 0x0D,
    "Shift": 0x10,
    "Control": 0x11,
    "Alt": 0x12,
    "Pause": 0x13,
    "CapsLock": 0x14,
    "Escape": 0x1B,
    "Space": 0x20,
    "PageUp": 0x21,
    "PageDown": 0x22,
    "End": 0x23,
    "Home": 0x24,
    "ArrowLeft": 0x25,
    "ArrowUp": 0x26,
    "ArrowRight": 0x27,
    "ArrowDown": 0x28,
    "Insert": 0x2D,
    "Delete": 0x2E,
}

for index in range(1, 13):
    VK_BY_KEY[f"F{index}"] = 0x6F + index

for code in range(ord("0"), ord("9") + 1):
    VK_BY_KEY[chr(code)] = code

for code in range(ord("A"), ord("Z") + 1):
    VK_BY_KEY[chr(code)] = code
    VK_BY_KEY[chr(code).lower()] = code


def local_ip() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("8.8.8.8", 80))
            return probe.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: Any) -> None:
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def html_response(handler: BaseHTTPRequestHandler, body: str) -> None:
    encoded = body.encode("utf-8")
    handler.send_response(200)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(encoded)))
    handler.end_headers()
    handler.wfile.write(encoded)


def read_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0") or "0")
    if length <= 0:
        return {}
    raw = handler.rfile.read(min(length, 1024 * 1024))
    try:
        data = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def window_title(hwnd: int) -> str:
    length = user32.GetWindowTextLengthW(hwnd)
    if length <= 0:
        return ""
    buffer = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buffer, length + 1)
    return buffer.value


def find_window(match_text: str) -> tuple[int | None, str | None]:
    needle = match_text.lower()
    matches: list[tuple[int, str]] = []

    @EnumWindowsProc
    def callback(hwnd: int, _: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        title = window_title(hwnd)
        if title and needle in title.lower():
            matches.append((hwnd, title))
            return False
        return True

    user32.EnumWindows(callback, 0)
    if matches:
        return matches[0]
    return None, None


def window_rect(hwnd: int) -> tuple[int, int, int, int]:
    rect = RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise RuntimeError("Could not read Tibia window position.")
    width = max(1, rect.right - rect.left)
    height = max(1, rect.bottom - rect.top)
    return rect.left, rect.top, width, height


def focus_window(hwnd: int) -> bool:
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, SW_RESTORE)
        time.sleep(0.08)

    current_thread = kernel32.GetCurrentThreadId()
    target_thread = user32.GetWindowThreadProcessId(hwnd, None)
    foreground = user32.GetForegroundWindow()
    foreground_thread = user32.GetWindowThreadProcessId(foreground, None) if foreground else 0

    attached: list[int] = []
    for thread_id in {target_thread, foreground_thread}:
        if thread_id and thread_id != current_thread:
            if user32.AttachThreadInput(current_thread, thread_id, True):
                attached.append(thread_id)

    try:
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
        user32.SetActiveWindow(hwnd)
        user32.SetFocus(hwnd)
    finally:
        for thread_id in attached:
            user32.AttachThreadInput(current_thread, thread_id, False)

    time.sleep(0.04)
    return user32.GetForegroundWindow() == hwnd


def target_window(match_text: str) -> tuple[int, str]:
    hwnd, title = find_window(match_text)
    if not hwnd:
        raise RuntimeError(f"No visible window matching {match_text!r} was found.")
    return hwnd, title or ""


def clamp(value: float, lower: float = 0.0, upper: float = 1.0) -> float:
    return max(lower, min(upper, value))


def send_mouse_click(match_text: str, x_norm: float, y_norm: float, button: str) -> dict[str, Any]:
    hwnd, title = target_window(match_text)
    if not focus_window(hwnd):
        return {
            "ok": False,
            "error": f"Could not focus target window: {title}",
            "window": title,
        }
    left, top, width, height = window_rect(hwnd)
    x = left + round(clamp(float(x_norm)) * width)
    y = top + round(clamp(float(y_norm)) * height)

    down = MOUSEEVENTF_RIGHTDOWN if button == "right" else MOUSEEVENTF_LEFTDOWN
    up = MOUSEEVENTF_RIGHTUP if button == "right" else MOUSEEVENTF_LEFTUP

    user32.SetCursorPos(x, y)
    time.sleep(0.02)
    user32.mouse_event(down, 0, 0, 0, 0)
    time.sleep(0.035)
    user32.mouse_event(up, 0, 0, 0, 0)
    return {"ok": True, "window": title, "x": x, "y": y}


def send_key(match_text: str, key: str, action: str) -> dict[str, Any]:
    hwnd, title = target_window(match_text)
    if not focus_window(hwnd):
        return {
            "ok": False,
            "error": f"Could not focus target window: {title}",
            "window": title,
        }
    vk = VK_BY_KEY.get(key)
    if vk is None:
        return {"ok": False, "error": f"Unsupported key: {key}"}

    flags = KEYEVENTF_KEYUP if action == "up" else 0
    user32.keybd_event(vk, 0, flags, 0)
    return {"ok": True, "window": title, "key": key, "action": action}


def tap_key(match_text: str, key: str) -> dict[str, Any]:
    down = send_key(match_text, key, "down")
    if not down.get("ok"):
        return down
    time.sleep(0.04)
    return send_key(match_text, key, "up")


def send_unicode_text(match_text: str, text: str) -> dict[str, Any]:
    hwnd, title = target_window(match_text)
    if not focus_window(hwnd):
        return {
            "ok": False,
            "error": f"Could not focus target window: {title}",
            "window": title,
        }
    sent = 0
    for char in text[:500]:
        code = ord(char)
        extra = ctypes.c_ulong(0)
        key_down = INPUT(
            type=INPUT_KEYBOARD,
            union=INPUTUNION(
                ki=KEYBDINPUT(0, code, KEYEVENTF_UNICODE, 0, ctypes.pointer(extra))
            ),
        )
        key_up = INPUT(
            type=INPUT_KEYBOARD,
            union=INPUTUNION(
                ki=KEYBDINPUT(
                    0,
                    code,
                    KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                    0,
                    ctypes.pointer(extra),
                )
            ),
        )
        inputs = (INPUT * 2)(key_down, key_up)
        user32.SendInput(2, inputs, ctypes.sizeof(INPUT))
        sent += 1
        time.sleep(0.004)
    return {"ok": True, "window": title, "characters": sent}


class LiveRemoteState:
    def __init__(self, pin: str, window_match: str, phone_ip: str, port: int) -> None:
        self.pin = pin
        self.window_match = window_match
        self.phone_ip = phone_ip
        self.port = port
        self.lock = threading.Lock()
        self.room: dict[str, Any] = {
            "offer": None,
            "answer": None,
            "updatedAt": 0,
        }

    def reset_room(self) -> None:
        with self.lock:
            self.room = {"offer": None, "answer": None, "updatedAt": time.time()}

    def set_offer(self, offer: Any) -> None:
        with self.lock:
            self.room["offer"] = offer
            self.room["answer"] = None
            self.room["updatedAt"] = time.time()

    def set_answer(self, answer: Any) -> None:
        with self.lock:
            self.room["answer"] = answer
            self.room["updatedAt"] = time.time()

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return dict(self.room)


def require_pin(handler: BaseHTTPRequestHandler, state: LiveRemoteState, data: dict[str, Any]) -> bool:
    query = parse_qs(urlparse(handler.path).query)
    supplied = data.get("pin") or query.get("pin", [""])[0]
    if supplied != state.pin:
        json_response(handler, 403, {"ok": False, "error": "Invalid PIN."})
        return False
    return True


def make_handler(state: LiveRemoteState) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "PenultimaLiveRemote/1.0"

        def log_message(self, fmt: str, *args: Any) -> None:
            sys.stdout.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))
            sys.stdout.flush()

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/":
                html_response(self, render_template(INDEX_HTML, state))
                return
            if parsed.path == "/host":
                html_response(self, render_template(HOST_HTML, state))
                return
            if parsed.path == "/viewer":
                html_response(self, render_template(VIEWER_HTML, state))
                return
            if parsed.path == "/api/status":
                hwnd, title = find_window(state.window_match)
                json_response(
                    self,
                    200,
                    {
                        "ok": True,
                        "pin": state.pin,
                        "hostUrl": f"http://127.0.0.1:{state.port}/host?pin={state.pin}",
                        "viewerUrl": f"http://{state.phone_ip}:{state.port}/viewer?pin={state.pin}",
                        "targetFound": bool(hwnd),
                        "targetTitle": title,
                        "windowMatch": state.window_match,
                    },
                )
                return
            if parsed.path == "/api/signal/offer":
                if not require_pin(self, state, {}):
                    return
                offer = state.snapshot().get("offer")
                if not offer:
                    json_response(self, 204, {})
                    return
                json_response(self, 200, {"ok": True, "offer": offer})
                return
            if parsed.path == "/api/signal/answer":
                if not require_pin(self, state, {}):
                    return
                answer = state.snapshot().get("answer")
                if not answer:
                    json_response(self, 204, {})
                    return
                json_response(self, 200, {"ok": True, "answer": answer})
                return
            self.send_error(404)

        def do_POST(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            data = read_json(self)
            if parsed.path.startswith("/api/"):
                if not require_pin(self, state, data):
                    return

            try:
                if parsed.path == "/api/signal/reset":
                    state.reset_room()
                    json_response(self, 200, {"ok": True})
                    return
                if parsed.path == "/api/signal/offer":
                    state.set_offer(data.get("description"))
                    json_response(self, 200, {"ok": True})
                    return
                if parsed.path == "/api/signal/answer":
                    state.set_answer(data.get("description"))
                    json_response(self, 200, {"ok": True})
                    return
                if parsed.path == "/api/input":
                    result = handle_input(state, data)
                    status = 200 if result.get("ok") else 400
                    json_response(self, status, result)
                    return
            except Exception as error:  # noqa: BLE001
                json_response(self, 500, {"ok": False, "error": str(error)})
                return
            self.send_error(404)

    return Handler


def handle_input(state: LiveRemoteState, data: dict[str, Any]) -> dict[str, Any]:
    input_type = str(data.get("type") or "")
    if input_type == "tap":
        return send_mouse_click(
            state.window_match,
            float(data.get("x", 0.5)),
            float(data.get("y", 0.5)),
            str(data.get("button") or "left"),
        )
    if input_type == "key":
        key = str(data.get("key") or "")
        action = str(data.get("action") or "tap")
        if action == "tap":
            return tap_key(state.window_match, key)
        if action in {"down", "up"}:
            return send_key(state.window_match, key, action)
        return {"ok": False, "error": f"Unsupported key action: {action}"}
    if input_type == "text":
        return send_unicode_text(state.window_match, str(data.get("text") or ""))
    return {"ok": False, "error": f"Unsupported input type: {input_type}"}


def template_vars(state: LiveRemoteState) -> dict[str, str]:
    return {
        "pin": state.pin,
        "port": str(state.port),
        "phone_ip": state.phone_ip,
        "host_url": f"http://127.0.0.1:{state.port}/host?pin={state.pin}",
        "viewer_url": f"http://{state.phone_ip}:{state.port}/viewer?pin={state.pin}",
        "window_match": state.window_match.replace('"', "&quot;"),
    }


def render_template(template: str, state: LiveRemoteState) -> str:
    rendered = template
    for key, value in template_vars(state).items():
        rendered = rendered.replace("{" + key + "}", value)
    return rendered


COMMON_STYLE = """
<style>
  :root {
    color-scheme: dark;
    --bg: #11161d;
    --panel: #18212b;
    --line: #324254;
    --text: #edf3fa;
    --muted: #a8b4c0;
    --accent: #93c5fd;
    --danger: #fca5a5;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    background: var(--bg);
    color: var(--text);
    font: 15px/1.4 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }
  main { max-width: 1040px; margin: 0 auto; padding: 18px; }
  h1 { margin: 0 0 14px; font-size: 24px; }
  p { color: var(--muted); }
  a, button {
    color: inherit;
    font: inherit;
  }
  .panel {
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 14px;
    margin: 12px 0;
  }
  .row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
  .button, button {
    border: 1px solid var(--line);
    background: #223044;
    border-radius: 8px;
    padding: 10px 14px;
    text-decoration: none;
    cursor: pointer;
    min-height: 42px;
  }
  button.primary, .button.primary {
    background: var(--accent);
    color: #0b1420;
    border-color: var(--accent);
    font-weight: 700;
  }
  button:disabled { opacity: .55; cursor: not-allowed; }
  code {
    padding: 2px 5px;
    border-radius: 5px;
    background: #0b1017;
    color: var(--accent);
  }
  .status { color: var(--muted); min-height: 22px; }
  video {
    width: 100%;
    background: #000;
    border: 1px solid var(--line);
    border-radius: 8px;
    aspect-ratio: 16 / 9;
    object-fit: contain;
    touch-action: none;
  }
  .viewer-layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 220px;
    gap: 12px;
  }
  .dpad {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
  }
  .dpad button {
    min-width: 0;
    min-height: 58px;
    padding: 8px 6px;
    font-size: 18px;
  }
  .dpad .blank { visibility: hidden; }
  .toolbar { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
  textarea {
    width: 100%;
    min-height: 70px;
    resize: vertical;
    background: #0b1017;
    color: var(--text);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 10px;
    font: inherit;
  }
  @media (max-width: 860px) {
    main { padding: 10px; }
    .viewer-layout { display: block; }
    video { aspect-ratio: 16 / 10; }
    .controls { margin-top: 10px; }
  }
</style>
"""


INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Penultima Live Remote</title>
""" + COMMON_STYLE + """
</head>
<body>
<main>
  <h1>Penultima Live Remote</h1>
  <div class="panel">
    <p>This helper is local to the Windows PC. It does not restart or control the production server.</p>
    <p>Target window match: <code>{window_match}</code></p>
    <p>PIN: <code>{pin}</code></p>
  </div>
  <div class="panel">
    <h2>1. Desktop host</h2>
    <p>Open this on the PC with Tibia running and choose the <code>Tibia - Waldir</code> window when Chrome asks what to share.</p>
    <p><a class="button primary" href="{host_url}">Open Desktop Host</a></p>
  </div>
  <div class="panel">
    <h2>2. Phone controller</h2>
    <p>Open this on the phone while it is on the same network as the PC.</p>
    <p><a class="button primary" href="{viewer_url}">{viewer_url}</a></p>
  </div>
</main>
</body>
</html>
"""


HOST_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Penultima Live Host</title>
""" + COMMON_STYLE + """
</head>
<body>
<main>
  <h1>Desktop Host</h1>
  <div class="panel">
    <p>PIN: <code id="pin">{pin}</code></p>
    <p>Phone URL: <code>{viewer_url}</code></p>
    <p>Keep this page open. Select the Tibia window, not the whole screen, for correct click mapping.</p>
    <div class="row">
      <button id="start" class="primary">Start sharing Tibia window</button>
      <button id="reset">Reset pairing</button>
      <a class="button" href="/">Back</a>
    </div>
    <p class="status" id="status">Idle.</p>
  </div>
  <video id="preview" autoplay muted playsinline></video>
</main>
<script>
const PIN = "{pin}";
let pc;
let stream;

const statusEl = document.getElementById("status");
const preview = document.getElementById("preview");
const startButton = document.getElementById("start");

function status(text) {
  statusEl.textContent = text;
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ pin: PIN, ...body })
  });
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

async function getJson(url) {
  const response = await fetch(url + (url.includes("?") ? "&" : "?") + "pin=" + encodeURIComponent(PIN), {
    cache: "no-store"
  });
  if (response.status === 204) return null;
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

function waitIceComplete(peer) {
  if (peer.iceGatheringState === "complete") return Promise.resolve();
  return new Promise((resolve) => {
    const done = () => {
      if (peer.iceGatheringState === "complete") {
        peer.removeEventListener("icegatheringstatechange", done);
        resolve();
      }
    };
    peer.addEventListener("icegatheringstatechange", done);
    setTimeout(resolve, 3500);
  });
}

async function waitForAnswer() {
  for (;;) {
    const result = await getJson("/api/signal/answer");
    if (result?.answer) return result.answer;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
}

async function startHost() {
  startButton.disabled = true;
  try {
    status("Choose the Tibia client window in the browser prompt.");
    await postJson("/api/signal/reset", {});
    stream = await navigator.mediaDevices.getDisplayMedia({
      video: { frameRate: 30 },
      audio: false
    });
    preview.srcObject = stream;

    pc = new RTCPeerConnection({ iceServers: [] });
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));
    stream.getVideoTracks()[0].addEventListener("ended", () => {
      status("Screen sharing stopped.");
      startButton.disabled = false;
    });

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await waitIceComplete(pc);
    await postJson("/api/signal/offer", { description: pc.localDescription });
    status("Waiting for phone to connect: {viewer_url}");

    const answer = await waitForAnswer();
    await pc.setRemoteDescription(answer);
    status("Phone connected. Keep this tab open.");
  } catch (error) {
    console.error(error);
    status("Error: " + error.message);
    startButton.disabled = false;
  }
}

document.getElementById("start").addEventListener("click", startHost);
document.getElementById("reset").addEventListener("click", async () => {
  await postJson("/api/signal/reset", {});
  status("Pairing reset.");
});
</script>
</body>
</html>
"""


VIEWER_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>Penultima Live Controller</title>
""" + COMMON_STYLE + """
</head>
<body>
<main>
  <h1>Phone Controller</h1>
  <div class="panel row">
    <button id="connect" class="primary">Connect</button>
    <button id="keyboard">Keyboard</button>
    <a class="button" href="/">Back</a>
    <span class="status" id="status">Waiting.</span>
  </div>
  <div class="viewer-layout">
    <section>
      <video id="remote" autoplay playsinline></video>
    </section>
    <section class="controls panel">
      <div class="dpad">
        <button class="blank"></button>
        <button data-hold-key="ArrowUp">Up</button>
        <button class="blank"></button>
        <button data-hold-key="ArrowLeft">Left</button>
        <button data-hold-key="ArrowDown">Down</button>
        <button data-hold-key="ArrowRight">Right</button>
      </div>
      <div class="toolbar" style="margin-top: 10px;">
        <button data-tap-key="Enter">Enter</button>
        <button data-tap-key="Escape">Esc</button>
        <button data-tap-key="Tab">Tab</button>
        <button data-button="right">Right click</button>
      </div>
      <p>Tap the video for left click. Use the movement pad to hold arrow keys.</p>
      <textarea id="text" placeholder="Type here, then Send text. Enter/Esc buttons are above."></textarea>
      <div class="row" style="margin-top: 8px;">
        <button id="sendText">Send text</button>
        <button id="clearText">Clear</button>
      </div>
      <textarea id="mobileKeyboard" aria-label="Mobile keyboard" style="opacity:0;position:fixed;left:-1000px;top:-1000px;width:1px;height:1px;"></textarea>
    </section>
  </div>
</main>
<script>
const PIN = "{pin}";
let pc;
let lastButton = "left";
const statusEl = document.getElementById("status");
const remote = document.getElementById("remote");
const text = document.getElementById("text");
const mobileKeyboard = document.getElementById("mobileKeyboard");

function status(message) {
  statusEl.textContent = message;
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ pin: PIN, ...body })
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || result.ok === false) {
    throw new Error(result.error || response.statusText);
  }
  return result;
}

async function getJson(url) {
  const response = await fetch(url + (url.includes("?") ? "&" : "?") + "pin=" + encodeURIComponent(PIN), {
    cache: "no-store"
  });
  if (response.status === 204) return null;
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

function waitIceComplete(peer) {
  if (peer.iceGatheringState === "complete") return Promise.resolve();
  return new Promise((resolve) => {
    const done = () => {
      if (peer.iceGatheringState === "complete") {
        peer.removeEventListener("icegatheringstatechange", done);
        resolve();
      }
    };
    peer.addEventListener("icegatheringstatechange", done);
    setTimeout(resolve, 3500);
  });
}

async function waitForOffer() {
  for (;;) {
    const result = await getJson("/api/signal/offer");
    if (result?.offer) return result.offer;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
}

async function connect() {
  document.getElementById("connect").disabled = true;
  try {
    status("Waiting for desktop host...");
    const offer = await waitForOffer();
    pc = new RTCPeerConnection({ iceServers: [] });
    pc.addEventListener("track", (event) => {
      remote.srcObject = event.streams[0];
      status("Connected.");
    });
    await pc.setRemoteDescription(offer);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await waitIceComplete(pc);
    await postJson("/api/signal/answer", { description: pc.localDescription });
    status("Connecting video...");
  } catch (error) {
    console.error(error);
    status("Error: " + error.message);
    document.getElementById("connect").disabled = false;
  }
}

function normalizedPoint(event) {
  const rect = remote.getBoundingClientRect();
  const videoW = remote.videoWidth || rect.width;
  const videoH = remote.videoHeight || rect.height;
  const videoAspect = videoW / videoH;
  const rectAspect = rect.width / rect.height;
  let width = rect.width;
  let height = rect.height;
  let offsetX = 0;
  let offsetY = 0;
  if (rectAspect > videoAspect) {
    width = rect.height * videoAspect;
    offsetX = (rect.width - width) / 2;
  } else {
    height = rect.width / videoAspect;
    offsetY = (rect.height - height) / 2;
  }
  const x = Math.max(0, Math.min(1, (event.clientX - rect.left - offsetX) / width));
  const y = Math.max(0, Math.min(1, (event.clientY - rect.top - offsetY) / height));
  return { x, y };
}

async function sendTap(event, button) {
  event.preventDefault();
  const point = normalizedPoint(event);
  try {
    await postJson("/api/input", { type: "tap", button, ...point });
    status(button === "right" ? "Right click sent." : "Click sent.");
  } catch (error) {
    status("Input error: " + error.message);
  }
}

async function sendKey(key, action) {
  try {
    await postJson("/api/input", { type: "key", key, action });
    status(`${key} ${action}.`);
  } catch (error) {
    status("Key error: " + error.message);
  }
}

remote.addEventListener("pointerdown", (event) => sendTap(event, lastButton));
remote.addEventListener("contextmenu", (event) => event.preventDefault());

document.querySelectorAll("[data-button='right']").forEach((button) => {
  button.addEventListener("click", () => {
    lastButton = lastButton === "right" ? "left" : "right";
    button.textContent = lastButton === "right" ? "Next tap: right" : "Right click";
  });
});

document.querySelectorAll("[data-hold-key]").forEach((button) => {
  const key = button.dataset.holdKey;
  const release = () => sendKey(key, "up");
  button.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    button.setPointerCapture?.(event.pointerId);
    sendKey(key, "down");
  });
  button.addEventListener("pointerup", release);
  button.addEventListener("pointercancel", release);
  button.addEventListener("pointerleave", release);
});

document.querySelectorAll("[data-tap-key]").forEach((button) => {
  button.addEventListener("click", () => sendKey(button.dataset.tapKey, "tap"));
});

document.addEventListener("keydown", (event) => {
  if (event.target === text || event.target === mobileKeyboard) return;
  sendKey(event.key === " " ? "Space" : event.key, "down");
  event.preventDefault();
});
document.addEventListener("keyup", (event) => {
  if (event.target === text || event.target === mobileKeyboard) return;
  sendKey(event.key === " " ? "Space" : event.key, "up");
  event.preventDefault();
});

document.getElementById("sendText").addEventListener("click", async () => {
  if (!text.value) return;
  try {
    await postJson("/api/input", { type: "text", text: text.value });
    status("Text sent.");
  } catch (error) {
    status("Text error: " + error.message);
  }
});
document.getElementById("clearText").addEventListener("click", () => {
  text.value = "";
});
document.getElementById("keyboard").addEventListener("click", () => {
  mobileKeyboard.value = "";
  mobileKeyboard.focus();
  status("Mobile keyboard focused.");
});
mobileKeyboard.addEventListener("beforeinput", async (event) => {
  if (!event.data) return;
  event.preventDefault();
  try {
    await postJson("/api/input", { type: "text", text: event.data });
  } catch (error) {
    status("Keyboard error: " + error.message);
  }
});
mobileKeyboard.addEventListener("keydown", (event) => {
  if (["Enter", "Backspace", "Tab", "Escape"].includes(event.key)) {
    sendKey(event.key, "tap");
    event.preventDefault();
  }
});

document.getElementById("connect").addEventListener("click", connect);
</script>
</body>
</html>
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Penultima local live remote-control host")
    parser.add_argument("--host", default="0.0.0.0", help="HTTP bind address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="HTTP port")
    parser.add_argument("--pin", default="", help="Pairing PIN; generated when omitted")
    parser.add_argument(
        "--window-match",
        default=DEFAULT_WINDOW_MATCH,
        help="Visible Windows title text used for input targeting",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    pin = args.pin.strip() or f"{secrets.randbelow(900000) + 100000}"
    phone_ip = local_ip()
    state = LiveRemoteState(pin, args.window_match, phone_ip, args.port)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(state))

    print("Penultima Live Remote local helper")
    print("This does not restart or control the production server.")
    print(f"Target window match: {args.window_match!r}")
    print(f"Desktop host: http://127.0.0.1:{args.port}/host?pin={pin}")
    print(f"Phone viewer: http://{phone_ip}:{args.port}/viewer?pin={pin}")
    print(f"PIN: {pin}")
    print("Keep the Tibia window visible and select the Tibia window in the browser prompt.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping live remote helper.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
