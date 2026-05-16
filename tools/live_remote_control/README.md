# Penultima Live Remote Control

This is a local Windows helper for controlling the Tibia client from a phone.
It does not restart, reload, or control the production server.

The current Flutter Live page only captures a local window as a browser video.
Browsers do not forward clicks or keyboard events from that video into the
captured Tibia window. Remote control needs a local host process that can send
input to Windows.

## Start

Run this on the Windows PC where Tibia is open:

```powershell
D:\Server\Beats-Monitor\tools\live_remote_control\start-live-remote-host.ps1
```

The command prints two URLs:

- Desktop host: open this on the PC and choose the `Tibia - Waldir` window.
- Phone viewer: open this on the phone while it is on the same network.

If Windows Firewall asks, allow access for the private network.

## Usage

1. Keep the Tibia window visible on the PC.
2. Open the desktop host URL on the PC.
3. Click `Start sharing Tibia window`.
4. In the browser prompt, select the `Tibia - Waldir` window, not the whole screen.
5. Open the phone viewer URL on the phone.
6. Tap `Connect`.
7. Tap the video to left-click Tibia.
8. Use the arrow pad to walk.
9. Use `Keyboard` or `Send text` for typing.

## Notes

- Phone and PC must be on the same local network.
- Click mapping is correct only when the desktop host shares the Tibia window.
- If the phone cannot open the URL, check Windows Firewall or the PC network.
- The helper targets the first visible window whose title contains `Tibia - Waldir`.
- To target another character, pass `-WindowMatch "Tibia - Character Name"` to the start script.
- If input says it cannot focus the target window, click the Tibia window once on the PC and try again. If Windows still blocks focus, run the PowerShell start command as administrator.
