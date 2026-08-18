param(
    [ValidateSet("auto", "x11", "wayland")]
    [string]$Backend = "auto"
)

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Game = Join-Path $Root "ionlancer.exe"

if (-not (Test-Path $Game)) {
    Write-Error "ionlancer.exe is not built"
    exit 1
}

if ($Backend -eq "auto") {
    Remove-Item Env:SDL_VIDEODRIVER -ErrorAction SilentlyContinue
} else {
    $env:SDL_VIDEODRIVER = $Backend
}

& $Game
exit $LASTEXITCODE
