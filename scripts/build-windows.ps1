param(
    [string]$Gm2 = "gm2",
    [string]$PkgConfig = "pkg-config",
    [switch]$Aggressive
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

& $PkgConfig --exists sdl2
if ($LASTEXITCODE -ne 0) { throw "SDL2 development package was not found by pkg-config." }

$SdlLibs = ((& $PkgConfig --libs sdl2) -join " ") -split '\s+'
$SdlCflags = ((& $PkgConfig --cflags sdl2) -join " ") -split '\s+'
$Modules = @("RNG", "FrameBuffer", "Input", "Audio", "Visuals", "Game", "Platform")
$BuildDir = Join-Path $Root "build\windows"

if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$Common = @("-fpim4", "-I", "src", "-Wall") + $SdlCflags
$Opt = @("-O3")
if ($Aggressive) { $Opt += @("-flto", "-fm2-whole-program") }

$Objects = @()
foreach ($Module in $Modules) {
    $Obj = Join-Path $BuildDir "$Module.o"
    $Args = $Common + $Opt + @("-c", "src/$Module.mod", "-o", $Obj)
    & $Gm2 @Args
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $Objects += $Obj
}

$MainObj = Join-Path $BuildDir "Main.o"
$MainArgs = $Common + $Opt + @("-c", "-fscaffold-main", "src/Main.mod", "-o", $MainObj)
& $Gm2 @MainArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$LinkArgs = @("-fpim4") + $Opt + @($MainObj) + $Objects + @("-o", "ionlancer.exe") + $SdlLibs
& $Gm2 @LinkArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Built $Root\ionlancer.exe"
