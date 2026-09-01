#Requires -RunAsAdministrator
# =============================================================================
# LexBoosT OS - Intel APO (Application Performance Optimization) - enable si present
# =============================================================================
# Intel 12e gen+ / Core Ultra uniquement. APO (jusqu'a +14% FPS en 2025 sur ~15
# titres supportes pour la 12e-14e gen & Core Ultra 2) est gere par le pilote
# Intel DTT. Rien n'est casse : no-op sur AMD ; sur Intel, on active le service
# DTT/APO s'il existe et on documente le prerequis (pilote DTT + app APO).
$ErrorActionPreference = 'Continue'

function Test-IsIntel12Plus {
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $n = $cpu.Name
        return ($n -match 'Intel') -and ($n -match 'i[3579]-1[2-9]\d{3}' -or $n -match 'Core Ultra')
    } catch { return $false }
}

if (-not (Test-IsIntel12Plus)) {
    Write-Host '[-] Non-Intel (12th gen+) detected - Intel APO not applicable (no-op).'
    exit 0
}

Write-Host '[i] Intel 12th gen+/Core Ultra detected - checking Intel DTT/APO...'

# 1) Activer le service Intel DTT / APO s'il existe (nom/affichage varies selon fabricant)
try {
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Intel.*(Dtt|Apo)' -or $_.Name -match 'esif' -or $_.DisplayName -match 'Application Performance|Dynamic Tuning' } | Select-Object -First 1
    if ($svc) {
        try { Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction Stop } catch {}
        try { Start-Service -Name $svc.Name -ErrorAction SilentlyContinue } catch {}
        Write-Host "[+] Intel DTT/APO service '$($svc.Name)' enabled + started."
    } else {
        Write-Host '[-] No Intel DTT/APO service found.'
    }
} catch {
    Write-Host "[-] APO handling: $_"
}
exit 0
