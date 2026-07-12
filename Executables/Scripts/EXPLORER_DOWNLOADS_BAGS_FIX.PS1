$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' "Removing Downloads shell bags (HKCU)..."
$bagsPath = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags'
try {
    Get-ChildItem -Path $bagsPath -ErrorAction SilentlyContinue | ForEach-Object {
        $fullPath = Join-Path -Path $_.PSPath -ChildPath 'Shell\{885A186E-A440-4ADA-812B-DB871B942259}'
        if (Test-Path -Path $fullPath -ErrorAction SilentlyContinue) {
            Remove-Item -Path $fullPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log '+' "Downloads shell bags removed"
} catch {
    Write-Log '-' "Shell bags fix: $_"
}
# Exit cleanly
exit 0
