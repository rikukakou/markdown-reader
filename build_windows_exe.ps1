$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolDir = Join-Path $RootDir ".tools\pyinstaller"
$PythonDepsDir = Join-Path $RootDir ".tools\python-deps"
$BuildDir = Join-Path $RootDir "build"
$PyInstallerWorkDir = Join-Path $BuildDir "pyinstaller-work"
$SpecDir = Join-Path $BuildDir "pyinstaller-spec"
$DistDir = Join-Path $BuildDir "exe"
$ZipFile = Join-Path $BuildDir "Markdown-Reader-Windows-exe.zip"
$AppScript = Join-Path $RootDir "Windows\markdown_reader.pyw"
$IconSource = Join-Path $RootDir "Assets\AppIconSource.png"
$WindowsIcon = Join-Path $BuildDir "AppIcon.ico"

if (-not (Test-Path $ToolDir)) {
    Write-Host "Installing PyInstaller into .tools\pyinstaller..."
    python -m pip install --target $ToolDir pyinstaller
}

if (-not (Test-Path $PythonDepsDir)) {
    Write-Host "Installing runtime dependencies into .tools\python-deps..."
    python -m pip install --target $PythonDepsDir markdown pillow
}

if (Test-Path $PyInstallerWorkDir) {
    Remove-Item -LiteralPath $PyInstallerWorkDir -Recurse -Force
}

if (Test-Path $SpecDir) {
    Remove-Item -LiteralPath $SpecDir -Recurse -Force
}

if (Test-Path $DistDir) {
    try {
        Remove-Item -LiteralPath $DistDir -Recurse -Force
    }
    catch {
        $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $PyInstallerWorkDir = Join-Path $BuildDir "pyinstaller-work-$Stamp"
        $SpecDir = Join-Path $BuildDir "pyinstaller-spec-$Stamp"
        $DistDir = Join-Path $BuildDir "exe-$Stamp"
    }
}

if (Test-Path $ZipFile) {
    Remove-Item -LiteralPath $ZipFile -Force
}

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
New-Item -ItemType Directory -Path $SpecDir -Force | Out-Null

$env:PYTHONPATH = "$PythonDepsDir;$ToolDir"

python (Join-Path $RootDir "scripts\generate_windows_icon.py") $IconSource $WindowsIcon

if ($LASTEXITCODE -ne 0) {
    throw "Windows icon generation failed with exit code $LASTEXITCODE."
}

python -m PyInstaller `
    --noconfirm `
    --clean `
    --windowed `
    --name "Markdown Reader" `
    --distpath $DistDir `
    --workpath $PyInstallerWorkDir `
    --specpath $SpecDir `
    --icon $WindowsIcon `
    --add-data "$IconSource;Assets" `
    $AppScript

if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller failed with exit code $LASTEXITCODE."
}

$AppDir = Join-Path $DistDir "Markdown Reader"
Compress-Archive -Path (Join-Path $AppDir "*") -DestinationPath $ZipFile -Force

Write-Host "Built Windows executable:"
Write-Host (Join-Path $AppDir "Markdown Reader.exe")
Write-Host ""
Write-Host "Built release zip:"
Write-Host $ZipFile
