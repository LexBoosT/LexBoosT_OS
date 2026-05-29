function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# Activate and start planned tasks
Get-ScheduledTask -TaskPath "\Microsoft\Windows\.NET Framework\" | ForEach-Object {
    if ($_.State -eq "Disabled") {
        Enable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath
    }
    Start-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath
}

Start-Process PowerShell -Verb RunAs -ArgumentList "-Command `"New-Item -Path '$env:windir\System32\systemlive' -ItemType File -Force`""

# Credits to https://stackoverflow.com/users/9898643/theo
$env:PATH = [Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
[AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object {
    $path = $_.Location
    if ($path) {
        $name = Split-Path $path -Leaf
        Write-Log '+' "Running NGEN on '$name'"
        ngen.exe install $path /nologo
    }
}
# Exit cleanly
exit 0
