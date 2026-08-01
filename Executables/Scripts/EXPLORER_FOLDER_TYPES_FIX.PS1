$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

Write-Log '+' "Removing Downloads folder grouping (HKLM)..."
$folderTypesKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes'
$downloadsFolderID = '{885a186e-a440-4ada-812b-db871b942259}'
$path = Join-Path -Path $folderTypesKey -ChildPath $downloadsFolderID
try {
    Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        if ((Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).GroupBy) {
            Set-ItemProperty -Path $_.PSPath -Name GroupBy -Value '' -ErrorAction SilentlyContinue
        }
    }
    Write-Log '+' "Downloads grouping removed"
} catch {
    Write-Log '-' "Download grouping fix: $_"
}
# Exit cleanly
exit 0
