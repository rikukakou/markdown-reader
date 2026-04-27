$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PythonDepsDir = Join-Path $RootDir ".tools\python-deps"
$BuildDir = Join-Path $RootDir "build"
$PortableDir = Join-Path $BuildDir "Markdown-Reader-Windows"
$ZipFile = Join-Path $BuildDir "Markdown-Reader-Windows-portable.zip"

if (-not (Test-Path $PythonDepsDir)) {
    Write-Host "Installing runtime dependencies into .tools\python-deps..."
    python -m pip install --target $PythonDepsDir markdown pillow
}

if (Test-Path $PortableDir) {
    Remove-Item -LiteralPath $PortableDir -Recurse -Force
}

if (Test-Path $ZipFile) {
    Remove-Item -LiteralPath $ZipFile -Force
}

New-Item -ItemType Directory -Path $PortableDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $PortableDir ".tools") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $PortableDir ".tools\python-deps") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $PortableDir "Windows") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $PortableDir "Assets") | Out-Null

Copy-Item -LiteralPath (Join-Path $RootDir "Windows\markdown_reader.pyw") -Destination (Join-Path $PortableDir "Windows\markdown_reader.pyw")
Copy-Item -LiteralPath (Join-Path $RootDir "Assets\AppIconSource.png") -Destination (Join-Path $PortableDir "Assets\AppIconSource.png")
Copy-Item -LiteralPath (Join-Path $RootDir "README.md") -Destination (Join-Path $PortableDir "README.md")
Copy-Item -Path (Join-Path $PythonDepsDir "*") -Destination (Join-Path $PortableDir ".tools\python-deps") -Recurse

$Launcher = @'
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

where pyw >nul 2>nul
if %errorlevel%==0 (
  pyw -3 "%SCRIPT_DIR%Windows\markdown_reader.pyw"
  exit /b %errorlevel%
)

where pythonw >nul 2>nul
if %errorlevel%==0 (
  pythonw "%SCRIPT_DIR%Windows\markdown_reader.pyw"
  exit /b %errorlevel%
)

echo Python 3 is required to run Markdown Reader for Windows.
echo Install Python from https://www.python.org/downloads/windows/
pause
exit /b 1
'@

Set-Content -LiteralPath (Join-Path $PortableDir "Markdown Reader.cmd") -Value $Launcher -Encoding ASCII

Compress-Archive -Path (Join-Path $PortableDir "*") -DestinationPath $ZipFile -Force

Write-Host "Built portable package:"
Write-Host $PortableDir
Write-Host ""
Write-Host "Built zip:"
Write-Host $ZipFile
