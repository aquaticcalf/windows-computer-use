param(
    [ValidateSet("build", "run", "test", "vet", "clean")]
    [string]$Target = "build"
)

$ErrorActionPreference = "Stop"
$Odin = "odin"
$Bin = "bin"
$Out = "$Bin\wcu.exe"

switch ($Target) {
    "build" {
        & $Odin build cmd/wcu -out:$Out
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "built $Out"
    }
    "run" {
        & $Odin run cmd/wcu -- @($args)
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    "test" {
        & $Odin test internal/version
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    "vet" {
        & $Odin check cmd/wcu
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    "clean" {
        if (Test-Path $Bin) { Remove-Item -Recurse -Force $Bin }
        Write-Host "cleaned"
    }
}
