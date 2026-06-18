param(
    [int]$Port = 51844,
    [string]$WindowMatch = "Tibia - Waldir",
    [string]$Pin = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HostScript = Join-Path $ScriptDir "live_remote_host.py"

if (-not (Test-Path -LiteralPath $HostScript)) {
    throw "Missing live remote host script: $HostScript"
}

$ArgsList = @($HostScript, "--host", "0.0.0.0", "--port", [string]$Port, "--window-match", $WindowMatch)
if (-not [string]::IsNullOrWhiteSpace($Pin)) {
    $ArgsList += @("--pin", $Pin)
}

python @ArgsList
