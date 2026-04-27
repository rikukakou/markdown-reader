@echo off
setlocal
set "ROOT_DIR=%~dp0"

where pyw >nul 2>nul
if %errorlevel%==0 (
  pyw -3 "%ROOT_DIR%Windows\markdown_reader.pyw" %*
  exit /b %errorlevel%
)

where pythonw >nul 2>nul
if %errorlevel%==0 (
  pythonw "%ROOT_DIR%Windows\markdown_reader.pyw" %*
  exit /b %errorlevel%
)

where python >nul 2>nul
if %errorlevel%==0 (
  python "%ROOT_DIR%Windows\markdown_reader.pyw" %*
  exit /b %errorlevel%
)

echo Python 3 is required to run Markdown Reader for Windows.
echo Install Python from https://www.python.org/downloads/windows/
exit /b 1
