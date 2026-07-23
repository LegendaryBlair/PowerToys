@echo off
setlocal ENABLEDELAYEDEXPANSION

@REM Check if PowerToys.exe is running before trying to kill it.
@REM This avoids hanging if taskkill behaves unexpectedly when the process doesn't exist.
tasklist /FI "IMAGENAME eq PowerToys.exe" 2>NUL | find /I "PowerToys.exe" >NUL
if errorlevel 1 exit /b 0

@REM We loop here until PowerToys.exe is no longer running. We can't use the /F flag inside the loop,
@REM because it doesn't give the application an opportunity to clean up. Instead we send WM_CLOSE
@REM (taskkill without /F), which is caught by the message loops in PowerToys.exe, closing its windows
@REM one by one. We re-check with tasklist each iteration rather than trusting taskkill's exit code,
@REM so a transient failure (e.g. "Access is denied") is not mistaken for "process not found".
for /l %%x in (1, 1, 100) do (
    tasklist /FI "IMAGENAME eq PowerToys.exe" 2>NUL | find /I "PowerToys.exe" >NUL
    if errorlevel 1 exit /b 0
    taskkill /IM PowerToys.exe 1>NUL 2>NUL
    @REM ping -n 2 waits ~1 second (first reply is immediate, then a 1s gap), giving the app time to
    @REM shut down and avoiding a tight spin. (ping -n 1 would return immediately with no delay.)
    ping -n 2 127.0.0.1 >NUL 2>NUL
)

@REM Force kill if graceful close failed after all attempts
taskkill /F /IM PowerToys.exe 1>NUL 2>NUL
exit /b 0