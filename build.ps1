param(
    [ValidateSet("build", "run", "test", "check", "clean")]
    [string]$Target = "build"
)

$ErrorActionPreference = "Stop"
$Odin = "odin"
$Bin = "bin"
$Out = "$Bin\wcu.exe"
$CmdDir = "cmd/wcu"
$Strict = @("-vet", "-strict-style", "-vet-tabs", "-disallow-do", "-warnings-as-errors")
$InternalDirs = Get-ChildItem -Path internal -Recurse -Directory

switch ($Target) {
    "build" {
        New-Item -ItemType Directory -Force -Path $Bin | Out-Null
        & $Odin build $CmdDir @Strict -out:$Out
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "built $Out"
    }
    "run" {
        & $Odin run $CmdDir -- @($args)
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    "check" {
        & $Odin check $CmdDir @Strict
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    "test" {
        foreach ($d in $InternalDirs) {
            & $Odin test $d.FullName @Strict
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    }
    "clean" {
        if (Test-Path $Bin) { Remove-Item -Recurse -Force $Bin }
        Write-Host "cleaned"
    }
}
