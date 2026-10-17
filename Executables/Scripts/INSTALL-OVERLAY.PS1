#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================
# DPI awareness (before any window is created)
# ============================================================
if (-not ('NativeMethods.Dpi' -as [type])) {
    Add-Type -Namespace NativeMethods -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
'@
}
try { [void][NativeMethods.Dpi]::SetProcessDPIAware() } catch { }
$g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:scale = [math]::Max(1.0, ($g.DpiX / 96.0))
$g.Dispose()

# ============================================================
# Fast per-frame transparency helper (PS 5.1 / .NET Framework)
# ============================================================
if (-not ('LogoHelper.Trans' -as [type])) {
    try {
        $script:refSD = [System.Drawing.Graphics].Assembly.Location
        Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
namespace LogoHelper {
    public static class Trans {
        public static Bitmap MakeTransparent(Bitmap src, int targetSize) {
            Bitmap bmp = new Bitmap(targetSize, targetSize, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp)) {
                g.InterpolationMode = InterpolationMode.HighQualityBilinear;
                g.DrawImage(src, 0, 0, targetSize, targetSize);
            }
            Rectangle rect = new Rectangle(0, 0, targetSize, targetSize);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int len = targetSize * targetSize * 4;
            byte[] bytes = new byte[len];
            Marshal.Copy(data.Scan0, bytes, 0, len);
            for (int i = 0; i < targetSize * targetSize; i++) {
                int o = i * 4;
                if (bytes[o + 2] + bytes[o + 1] + bytes[o] < 30) bytes[o + 3] = 0;
            }
            Marshal.Copy(bytes, 0, data.Scan0, len);
            bmp.UnlockBits(data);
            return bmp;
        }
    }
}
'@ -ReferencedAssemblies $script:refSD
    } catch { }
}

# ============================================================
# Drawing helpers
# ============================================================
function New-ScaledFont {
    param([string]$Family, [double]$Size, [System.Drawing.FontStyle]$Style)
    return New-Object System.Drawing.Font -ArgumentList @($Family, [single]($Size * $script:scale), $Style, [System.Drawing.GraphicsUnit]::Point)
}

function Draw-AnimatedDots {
    param($g, [string]$BaseText, [System.Drawing.RectangleF]$Rect, $Font, $Brush)
    $dots = ''
    for ($i = 0; $i -lt $script:dotCount; $i++) { $dots += '.' }
    $full = $BaseText + $dots
    $tSz = $g.MeasureString($full, $Font)
    $sx = [single]($Rect.X + ($Rect.Width - $tSz.Width) / 2)
    $sy = [single]($Rect.Y + ($Rect.Height - $Font.Height) / 2)
    $sf = New-Object System.Drawing.StringFormat
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Near
    $g.DrawString($BaseText, $Font, $Brush, $sx, $sy, $sf)
    if ($dots) {
        $g.DrawString($dots, $Font, $Brush, [single]($sx + $g.MeasureString($BaseText, $Font).Width), $sy, $sf)
    }
    $sf.Dispose()
}

function New-RoundRect {
    param([System.Drawing.RectangleF]$Rect, [single]$Radius)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $p.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $p.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $p.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Draw-SpacedText {
    param($gr, [string]$Text, $Font, $Brush, [single]$CenterX, [single]$Y, [single]$Tracking, [single]$MaxWidth = 0)
    if (-not $Text) { return }
    $chars = $Text.ToCharArray()
    $widths = New-Object single[] $chars.Count
    $baseTotal = [single]0
    for ($i = 0; $i -lt $chars.Count; $i++) {
        $widths[$i] = [single]$gr.MeasureString($chars[$i].ToString(), $Font).Width
        $baseTotal += $widths[$i]
    }
    $tr = [single]$Tracking
    if ($MaxWidth -gt 0 -and $chars.Count -gt 1) {
        $avail = [single]($MaxWidth - $baseTotal)
        if ($avail -lt 0) { $avail = 0 }
        $tr = [single][math]::Min($Tracking, $avail / ($chars.Count - 1))
    }
    $total = $baseTotal
    if ($chars.Count -gt 1) { $total += $tr * ($chars.Count - 1) }
    $x = [single]($CenterX - $total / 2)
    $sf = New-Object System.Drawing.StringFormat
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Near
    for ($i = 0; $i -lt $chars.Count; $i++) {
        $gr.DrawString($chars[$i].ToString(), $Font, $Brush, $x, $Y, $sf)
        $x += $widths[$i] + $tr
    }
    $sf.Dispose()
}

function Draw-PathGlow {
    param($g, $Path, $Color, [int]$Passes, [int]$BaseAlpha, [single]$Step)
    for ($i = 0; $i -lt $Passes; $i++) {
        $a = [int]($BaseAlpha * (1.0 - ($i / [double]$Passes)))
        if ($a -lt 2) { $a = 2 }
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($a, $Color.R, $Color.G, $Color.B), [single]($Step * ($i + 1)))
        $g.DrawPath($pen, $Path)
        $pen.Dispose()
    }
}

function Convert-ToTransparentLogo {
    param([string]$Path)
    $src = [System.Drawing.Image]::FromFile($Path)
    $w = $src.Width
    $h = $src.Height
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution($src.HorizontalResolution, $src.VerticalResolution)
    $gg = [System.Drawing.Graphics]::FromImage($bmp)
    $gg.DrawImage($src, 0, 0, $w, $h)
    $gg.Dispose()
    $src.Dispose()
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $len = $w * $h * 4
    $bytes = New-Object byte[] $len
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $len)
    for ($i = 0; $i -lt ($w * $h); $i++) {
        $o = $i * 4
        if (([int]$bytes[$o + 2] + [int]$bytes[$o + 1] + [int]$bytes[$o]) -lt 30) {
            $bytes[$o + 3] = 0
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $len)
    $bmp.UnlockBits($data)
    return $bmp
}

# ============================================================
# State
# ============================================================
$script:logRoot = 'C:\ProgramData\AME\Logs'
$script:ameProcesses = @('AME Wizard Beta', 'AME Wizard', 'AME Beta', 'AME', 'TrustedUninstaller.CLI')
$script:gifPath = Join-Path $PSScriptRoot '..\install.gif'
if (-not (Test-Path -LiteralPath $script:gifPath)) { $script:gifPath = Join-Path $PSScriptRoot 'install.gif' }
$script:maxProcLines = 25

$script:readOffset = 0
$script:pending = ''
$script:statusCount = 0
$script:latestStatus = $null
$script:successSeenAt = $null
$script:finished = $false
$script:cmdFinished = $false
$script:errorCount = 0
$script:warningCount = 0
$script:displayed = 0.0
$script:progressMax = 100
$script:startTime = Get-Date
$script:lastPaintMs = 0
$script:summaryShown = $false
$script:closing = $false
$script:allowClose = $false
$script:dotCount = 0
$script:procBuf = New-Object System.Collections.ArrayList
$script:finishMarker = Join-Path $env:TEMP 'LexBoosT_InstallFinished.marker'
Remove-Item -LiteralPath $script:finishMarker -Force -ErrorAction SilentlyContinue

$script:logoFrames = $null
$script:logoFrameProcessed = $null
$script:logoFrameCount = 0
$script:logoFrameIndex = 0
$script:logoDelays = @()
$script:logoElapsed = 0.0
$script:logoAnimImg = $null
$script:logoDisplay = 0

# Text/UI state drawn by the backdrop
$script:titleText = 'Installation in progress'
$script:headText = 'WELCOME TO THE LEXBOOST OS INSTALLATION PROCESS'
$script:statusText = 'Initializing LexBoosT OS...'
$script:statusColor = [System.Drawing.Color]::White
$script:summaryDuration = ''
$script:summaryResult = ''
$script:showSummary = $false
$script:bottomText = 'Some installation steps may take a while — please be patient.'

# ============================================================
# Log helpers
# ============================================================
function Get-LatestLogFile {
    $dirs = @(Get-ChildItem -LiteralPath $script:logRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if (-not $dirs) { return $null }
    $out = Join-Path $dirs[0].FullName 'Output.txt'
    if (Test-Path -LiteralPath $out) { return $out }
    return $null
}

function Read-NewLogLines {
    param([string]$LogFile)
    if (-not $LogFile) { return @() }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $len = [int]$fs.Length
        if ($len -lt $script:readOffset) { $script:readOffset = 0 }
        if ($len -eq $script:readOffset) { $fs.Dispose(); return @() }
        [void]$fs.Seek($script:readOffset, [System.IO.SeekOrigin]::Begin)
        $count = $len - $script:readOffset
        $buf = New-Object byte[] $count
        $read = $fs.Read($buf, 0, $count)
        $script:readOffset = $len
        $chunk = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $script:pending += $chunk
        $parts = $script:pending -split "`r?`n"
        if ($script:pending.EndsWith("`n") -or $script:pending.EndsWith("`r")) {
            $script:pending = ''
            return $parts
        }
        $script:pending = $parts[$parts.Count - 1]
        if ($parts.Count -gt 1) { return $parts[0..($parts.Count - 2)] }
        return @()
    } catch { return @() }
    finally { if ($fs) { $fs.Dispose() } }
}

function Add-ProcLine {
    param([string]$Text, [System.Drawing.Color]$Color)
    [void]$script:procBuf.Add([PSCustomObject]@{ Text = $Text; Color = $Color })
    while ($script:procBuf.Count -gt $script:maxProcLines) { $script:procBuf.RemoveAt(0) }
}

function Update-FromLog {
    $log = Get-LatestLogFile
    if (-not $log) { return }
    $newLines = Read-NewLogLines $log
    if ($newLines.Count -eq 0) {
        if ($script:successSeenAt -and ((Get-Date) - $script:successSeenAt).TotalSeconds -ge 2) {
            $script:finished = $true
        }
        return
    }
    $script:successSeenAt = $null

    foreach ($ln in $newLines) {
        $trim = $ln.Trim()
        if (-not $trim) { continue }

        if ($trim -match '^\[Status\]\s*(.+)$') {
            $script:statusCount++
            $script:latestStatus = $Matches[1].Trim()
        }
        elseif ($trim -match '^\[Error\]') {
            $script:errorCount++
            Add-ProcLine $trim ([System.Drawing.Color]::FromArgb(255, 90, 90))
        }
        elseif ($trim -match '^\[Process \| Err \|.*?\]\s*(.*)$') {
            $script:errorCount++
            Add-ProcLine $Matches[1].Trim() ([System.Drawing.Color]::FromArgb(255, 90, 90))
        }
        elseif ($trim -match '^\[Process \| Out \|.*?\]\s*(.*)$') {
            $content = $Matches[1].Trim()
            if ($content -match 'FAIL=([1-9]\d*)') { $script:warningCount += [int]$Matches[1] }
            if ($content -match 'Success|OK=') {
                Add-ProcLine $content ([System.Drawing.Color]::FromArgb(0, 255, 136))
            } elseif ($content -match '\[INFO\]') {
                Add-ProcLine $content ([System.Drawing.Color]::FromArgb(175, 180, 190))
            } else {
                Add-ProcLine $content ([System.Drawing.Color]::FromArgb(120, 125, 135))
            }
        }

        if ($trim -match 'Running.*FINISH-INSTALL\.CMD') {
            $script:cmdFinished = $true
        }
    }

    $lastLine = ''
    for ($i = $newLines.Count - 1; $i -ge 0; $i--) {
        if ($newLines[$i].Trim()) { $lastLine = $newLines[$i].Trim(); break }
    }
    if ($lastLine -match '^\[Process \| Out \|.*?\] Success!$') {
        $script:successSeenAt = Get-Date
    }
}

# ============================================================
# Screen + UI helpers
# ============================================================
function Get-OverlayScreen {
    foreach ($p in $script:ameProcesses) {
        $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
        foreach ($pr in $procs) {
            if ($pr.MainWindowHandle -ne [IntPtr]::Zero) {
                $s = [System.Windows.Forms.Screen]::FromHandle($pr.MainWindowHandle)
                if ($s) { return $s }
            }
        }
    }
    $pt = [System.Windows.Forms.Cursor]::Position
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        if ($s.Bounds.Contains($pt)) { return $s }
    }
    return [System.Windows.Forms.Screen]::PrimaryScreen
}

function Format-Duration {
    param([TimeSpan]$Dur)
    if ($Dur.TotalHours -ge 1) { return '{0}h {1}m {2}s' -f [int]$Dur.TotalHours, $Dur.Minutes, $Dur.Seconds }
    if ($Dur.TotalMinutes -ge 1) { return '{0}m {1}s' -f [int]$Dur.TotalMinutes, $Dur.Seconds }
    return '{0}s' -f $Dur.Seconds
}

function Close-Overlay {
    if ($script:closing) { return }
    $script:closing = $true
    $dotTimer.Stop(); $bgTimer.Stop(); $timer.Stop()
    [System.Windows.Forms.Cursor]::Show()
    $script:allowClose = $true
    $form.Close()
}

function Layout {
    $W = $form.ClientSize.Width
    $H = $form.ClientSize.Height

    # ---- particles (positions + speeds), re-seeded on resize ----
    if ($W -gt 0 -and $H -gt 0 -and -not $script:particles) {
        $script:particles = New-Object object[] $script:particleCount
        for ($i = 0; $i -lt $script:particleCount; $i++) {
            $script:particles[$i] = @{
                x = [single]($script:rand.NextDouble() * $W)
                y = [single]($script:rand.NextDouble() * $H)
                r = [single](0.8 + $script:rand.NextDouble() * 1.6)
                spd = [single](6 + $script:rand.NextDouble() * 14)
                phase = [single]($script:rand.NextDouble() * 6.28)
                twinkle = [single](0.6 + $script:rand.NextDouble() * 1.2)
            }
        }
    }

    # ---- live log terminal (right column) ----
    $termH = [int]($H * 0.54)
    $termW = [int][math]::Min([int]($W * 0.45), 1100)

    # ---- central glass card + terminal as a centered group ----
    $termGap = [int](20 * $script:scale)
    $maxCardW = $W - [int](48 * $script:scale) * 2 - $termGap - $termW
    $cardW = [int][math]::Max(420, [math]::Min(860, $maxCardW))
    $groupW = $cardW + $termGap + $termW
    $groupX = [int]([math]::Max([int](48 * $script:scale), ($W - $groupW) / 2))
    $cardX = $groupX
    $cardY = [int]($H * 0.10)
    $cardH = [int]($H * 0.64)
    if ($cardH -gt $H - 2 * $cardY) { $cardH = $H - 2 * $cardY }
    $script:cardRect = New-Object System.Drawing.RectangleF([single]$cardX, [single]$cardY, [single]$cardW, [single]$cardH)
    $script:cardRadius = [single](18 * $script:scale)

    # terminal just right of the card, vertically centered on it
    $termX = $cardX + $cardW + $termGap
    $termY = [int]($cardY + ($cardH - $termH) / 2)
    $script:termRect = New-Object System.Drawing.RectangleF([single]$termX, [single]$termY, [single]$termW, [single]$termH)
    $script:termRadius = [single](14 * $script:scale)
    $script:hackerPad = [int](14 * $script:scale)

    # ---- headline / title (centered on the CARD, not the screen) ----
    $script:headY = $cardY + [int](28 * $script:scale)
    $script:headRect = New-Object System.Drawing.RectangleF([single]$cardX, $script:headY, [single]$cardW, 40)
    $script:titleY = $script:headY + [int](34 * $script:scale)
    $script:titleRect = New-Object System.Drawing.RectangleF([single]$cardX, $script:titleY, [single]$cardW, 56)

    # ---- logo (with orbital ring) ----
    $script:logoW = [int][math]::Min($script:logoDisplay, $cardW * 0.38)
    $script:logoH = $script:logoW
    $script:logoCX = [single]($cardX + $cardW / 2)
    $script:logoCY = [single]($script:titleY + [int](72 * $script:scale) + $script:logoH / 2)
    $script:logoX = [int]($script:logoCX - $script:logoW / 2)
    $script:logoY = [int]($script:logoCY - $script:logoH / 2)

    # ---- pre-render orbital ring (avoids per-frame GDI+ allocation) ----
    if ($script:ringFrames) { foreach ($b in $script:ringFrames) { if ($b) { $b.Dispose() } } }
    $script:ringFrames = $null
    $ringR = [single]($script:logoW * 0.52)
    $diam = [int]([math]::Ceiling($ringR * 2 * 1.15))
    $script:ringFrames = New-Object object[] 36
    for ($i = 0; $i -lt 36; $i++) {
        $bmp = New-Object System.Drawing.Bitmap($diam, $diam)
        $bg = [System.Drawing.Graphics]::FromImage($bmp)
        $bg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $cx = $diam / 2
        $rr = New-Object System.Drawing.RectangleF([single]($cx - $ringR), [single]($cx - $ringR), [single]($ringR * 2), [single]($ringR * 2))
        $base = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 120, 130, 180), [single](1.2 * $script:scale))
        $bg.DrawEllipse($base, $rr.X, $rr.Y, $rr.Width, $rr.Height)
        $base.Dispose()
        $pa = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 0, 229, 255), [single](2.4 * $script:scale))
        $pa.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pa.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $ang = [single]($i * 10)
        $bg.DrawArc($pa, $rr, $ang, 90)
        $pa.Dispose()
        $pb = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(170, 124, 77, 255), [single](2.4 * $script:scale))
        $pb.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pb.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $bg.DrawArc($pb, $rr, ($ang + 180) % 360, 90)
        $pb.Dispose()
        $bg.Dispose()
        $script:ringFrames[$i] = $bmp
    }
    $script:animStep = [int]($diam / 2)

    # ---- status (centered on the CARD) ----
    $script:statusY = [int]($script:logoCY + $script:logoH / 2 + [int](28 * $script:scale))
    $script:statusRect = New-Object System.Drawing.RectangleF([single]$cardX, $script:statusY, [single]$cardW, 40)

    # ---- progress bar + percent chip (centered on the CARD) ----
    $script:barY = $script:statusY + [int](48 * $script:scale)
    $script:barW = [int]($cardW * 0.58)
    $script:barH = [int](14 * $script:scale)
    $script:barX = [int]($cardX + ($cardW - $script:barW) / 2)
    $script:chipW = [int](56 * $script:scale)
    $script:chipH = $script:barH
    $script:chipX = $script:barX + $script:barW + [int](12 * $script:scale)
    $script:chipY = $script:barY

    # ---- summary (centered on the CARD) ----
    $script:summaryY = $script:barY + $script:barH + [int](20 * $script:scale)

    # ---- footer ----
    $script:footerY = [int]($H * 0.885)
    $script:footerRect = New-Object System.Drawing.RectangleF(0, $script:footerY, $W, 40)
}

# ============================================================
# Build UI
# ============================================================
$script:screen = Get-OverlayScreen
$screenW = $script:screen.Bounds.Width
$screenH = $script:screen.Bounds.Height

$script:logoDisplay = [int][math]::Min($screenW * 0.34, $screenH * 0.30)
$script:logoFrames = $null
$script:logoFrameProcessed = $null
$script:logoFrameCount = 0
$script:logoFrameIndex = 0
$script:logoDelays = @()
$script:logoElapsed = 0.0
$script:logoAnimImg = $null
if (Test-Path -LiteralPath $script:gifPath) {
    if ('LogoHelper.Trans' -as [type]) {
        try {
            $script:logoAnimImg = [System.Drawing.Image]::FromFile($script:gifPath)
            $script:logoFrameCount = $script:logoAnimImg.GetFrameCount([System.Drawing.Imaging.FrameDimension]::Time)
            $script:logoFrames = New-Object object[] $script:logoFrameCount
            $script:logoFrameProcessed = New-Object bool[] $script:logoFrameCount
            try {
                $prop = $script:logoAnimImg.GetPropertyItem(20736)
                for ($i = 0; $i -lt $script:logoFrameCount; $i++) {
                    $off = $i * 4
                    if (($off + 4) -le $prop.Value.Length) { $d = [BitConverter]::ToUInt32($prop.Value, $off) / 100.0 } else { $d = 0.08 }
                    if ($d -le 0) { $d = 0.08 }
                    $script:logoDelays += $d
                }
            } catch {
                for ($i = 0; $i -lt $script:logoFrameCount; $i++) { $script:logoDelays += 0.08 }
            }
        } catch {
            $script:logoFrames = $null
            $script:logoFrameCount = 0
        }
    } else {
        try {
            $script:logoFrames = @(Convert-ToTransparentLogo $script:gifPath)
            $script:logoFrameProcessed = @($true)
            $script:logoFrameCount = 1
            $script:logoDelays = @(0.08)
        } catch {
            $script:logoFrames = $null
            $script:logoFrameCount = 0
        }
    }
}

$script:fontHead = New-ScaledFont 'Segoe UI' 13 ([System.Drawing.FontStyle]::Bold)
$script:fontTitle = New-ScaledFont 'Segoe UI' 25 ([System.Drawing.FontStyle]::Bold)
$script:fontStatus = New-ScaledFont 'Segoe UI' 16 ([System.Drawing.FontStyle]::Regular)
$script:fontSmall = New-ScaledFont 'Segoe UI' 12 ([System.Drawing.FontStyle]::Regular)
$script:fontPercent = New-ScaledFont 'Segoe UI' 11 ([System.Drawing.FontStyle]::Bold)
$script:fontHack = New-ScaledFont 'Consolas' 10 ([System.Drawing.FontStyle]::Regular)
$script:fontFooter = New-ScaledFont 'Segoe UI' 12 ([System.Drawing.FontStyle]::Regular)
$script:fontTermTitle = New-ScaledFont 'Segoe UI' 10 ([System.Drawing.FontStyle]::Bold)
$script:brushWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$script:brushHead = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 160, 190))
$script:brushCyan = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 229, 255))
$script:brushGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(175, 180, 190))
$script:brushDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 145, 155))
$script:brushFooter = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 150, 175))
$script:brushTrack = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 24, 26, 34))
$script:brushCardFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(46, 16, 18, 26))
$script:brushCardBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 100, 110, 140), 1)
$script:brushTermFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, 10, 12, 17))
$script:brushTermBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 70, 90, 110), 1)
$script:penBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 150, 155, 170))
$script:fmtCenter = New-Object System.Drawing.StringFormat
$script:fmtCenter.Alignment = [System.Drawing.StringAlignment]::Center
$script:fmtCenter.LineAlignment = [System.Drawing.StringAlignment]::Center
$script:fmtLeft = New-Object System.Drawing.StringFormat
$script:fmtLeft.Alignment = [System.Drawing.StringAlignment]::Near
$script:fmtLeft.LineAlignment = [System.Drawing.StringAlignment]::Near

# ---- particles: pre-allocated brushes (NO per-frame allocation) ----
$script:brushParticles = New-Object object[] 16
for ($i = 0; $i -lt 16; $i++) {
    $a = [int](8 + $i * 7)
    $script:brushParticles[$i] = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($a, 235, 240, 255))
}
$script:particleCount = 36
$script:rand = New-Object System.Random

$form = New-Object System.Windows.Forms.Form
$form.Text = 'LexBoosT OS'
$form.BackColor = [System.Drawing.Color]::Black
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.ControlBox = $false
$form.KeyPreview = $false
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.Bounds = $script:screen.Bounds

$form.Add_FormClosing({
    [System.Windows.Forms.Cursor]::Show()
    if (-not $script:allowClose) { $_.Cancel = $true }
})

$script:backdrop = New-Object System.Windows.Forms.Panel
$script:backdrop.Dock = [System.Windows.Forms.DockStyle]::Fill
try {
    $style = [System.Windows.Forms.ControlStyles]::AllPaintingInWmPaint -bor [System.Windows.Forms.ControlStyles]::UserPaint -bor [System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer -bor [System.Windows.Forms.ControlStyles]::ResizeRedraw
    $m = $script:backdrop.GetType().GetMethod('SetStyle', [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    if ($m) { [void]$m.Invoke($script:backdrop, @($style, $true)) }
} catch { }
$script:backdrop.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $W = $script:backdrop.Width
    $H = $script:backdrop.Height
    if ($W -lt 1 -or $H -lt 1) { return }

    $nowMs = [DateTime]::Now.Ticks / 10000
    $tSec = ([DateTime]::Now - $script:startTime).TotalSeconds

    # ---- background: pure black ----
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0))

    # ---- white fading particles (pre-allocated brushes, no per-frame alloc) ----
    if ($script:particles) {
        $dt = 0.016
        if ($script:lastPaintMs -gt 0) {
            $dt = ($nowMs - $script:lastPaintMs) / 1000.0
            if ($dt -gt 0.25) { $dt = 0.25 }
            if ($dt -le 0) { $dt = 0.016 }
        }
        for ($i = 0; $i -lt $script:particles.Count; $i++) {
            $pt = $script:particles[$i]
            # drift upward, wrap at edges
            $pt.y -= $pt.spd * $dt
            if ($pt.y -lt -4) {
                $pt.y = [single]($H + 4)
                $pt.x = [single]($script:rand.NextDouble() * $W)
            }
            # fade: twinkle 0..1 -> brush index
            $tw = 0.5 + 0.5 * [Math]::Sin($tSec * $pt.twinkle + $pt.phase)
            $bi = [int]($tw * 15.5)
            if ($bi -lt 0) { $bi = 0 } elseif ($bi -gt 15) { $bi = 15 }
            $d = $pt.r * 2
            $g.FillEllipse($script:brushParticles[$bi], $pt.x, $pt.y, $d, $d)
        }
    }

    # ---- live log terminal card ----
    $tr = $script:termRect
    $tpath = New-RoundRect $tr $script:termRadius
    $g.FillPath($script:brushTermFill, $tpath)
    $g.DrawPath($script:brushTermBorder, $tpath)
    $tpath.Dispose()
    $hdrH = [int](30 * $script:scale)
    $dotX = [single]($tr.X + 16 * $script:scale)
    $dotY = [single]($tr.Y + $hdrH / 2)
    $pulse = 0.55 + 0.45 * [Math]::Sin($tSec * 2.2)
    $dcol = [System.Drawing.Color]::FromArgb([int](120 + 135 * $pulse), 80, 250, 140)
    $dbrush = New-Object System.Drawing.SolidBrush($dcol)
    $g.FillEllipse($dbrush, [single]($dotX - 4 * $script:scale), [single]($dotY - 4 * $script:scale), [single](8 * $script:scale), [single](8 * $script:scale))
    $dbrush.Dispose()
    $g.DrawString('LIVE INSTALL LOG', $script:fontTermTitle, $script:brushHead, [single]($dotX + 12 * $script:scale), [single]($tr.Y + [int](8 * $script:scale)), $script:fmtLeft)
    $sepY = [single]($tr.Y + $hdrH)
    $sep = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 90, 110, 140), 1)
    $g.DrawLine($sep, [single]($tr.X + 12 * $script:scale), $sepY, [single]($tr.Right - 12 * $script:scale), $sepY)
    $sep.Dispose()
    $n = $script:procBuf.Count
    $lh = [int]($script:fontHack.Height + 4)
    $tx = [single]($tr.X + 14 * $script:scale)
    $ty = [single]($tr.Y + $hdrH + [int](10 * $script:scale))
    $maxLines = [int](($tr.Height - $hdrH - 16 * $script:scale) / $lh)
    if ($maxLines -lt 1) { $maxLines = 1 }
    $maxTextW = [single]($tr.Width - 28 * $script:scale)
    $clipRect = New-Object System.Drawing.RectangleF([single]$tr.X, [single]$tr.Y, [single]$tr.Width, [single]$tr.Height)
    $oldClip = $g.Clip
    $g.SetClip($clipRect)
    if ($n -eq 0) {
        $g.DrawString('Awaiting installer output...', $script:fontHack, $script:brushDim, $tx, $ty, $script:fmtLeft)
    } else {
        $start = 0
        if ($n -gt $maxLines) { $start = $n - $maxLines }
        $shown = $n - $start
        for ($i = $start; $i -lt $n; $i++) {
            $item = $script:procBuf[$i]
            $lineText = $item.Text
            if ($g.MeasureString($lineText, $script:fontHack).Width -gt $maxTextW) {
                while ($lineText.Length -gt 1 -and $g.MeasureString($lineText + '...', $script:fontHack).Width -gt $maxTextW) {
                    $lineText = $lineText.Substring(0, $lineText.Length - 1)
                }
                $lineText = $lineText.TrimEnd() + '...'
            }
            $fade = 0.35 + 0.65 * (($i - $start + 1) / $shown)
            $base = $item.Color
            $c = [System.Drawing.Color]::FromArgb([int]($base.R * $fade), [int]($base.G * $fade), [int]($base.B * $fade))
            $sb = New-Object System.Drawing.SolidBrush($c)
            $g.DrawString($lineText, $script:fontHack, $sb, $tx, [single]($ty + ($i - $start) * $lh), $script:fmtLeft)
            $sb.Dispose()
        }
    }
    $g.Clip = $oldClip
    $oldClip.Dispose()

    # ---- central glass card ----
    $cr = $script:cardRect
    $cpath = New-RoundRect $cr $script:cardRadius
    $g.FillPath($script:brushCardFill, $cpath)
    $g.DrawPath($script:brushCardBorder, $cpath)
    $cpath.Dispose()
    $hlX1 = [single]($cr.X + $script:cardRadius)
    $hlX2 = [single]($cr.Right - $script:cardRadius)
    $hl = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF($hlX1, [single]$cr.Y, [single]($hlX2 - $hlX1), 1)), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [System.Drawing.Color]::FromArgb(90, 200, 220, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $hl.SetSigmaBellShape(0.6)
    $hlPen = New-Object System.Drawing.Pen($hl, 1)
    $g.DrawLine($hlPen, $hlX1, [single]($cr.Y + 0.5), $hlX2, [single]($cr.Y + 0.5))
    $hlPen.Dispose(); $hl.Dispose()

    # ---- eyebrow headline (spaced caps, auto-fit to card width) ----
    $spacedCx = [single]($cr.X + $cr.Width / 2)
    $spacedCy = [single]$script:headY
    $spacedTr = [single](3 * $script:scale)
    $spacedMax = [single]($cr.Width - [int](56 * $script:scale))
    Draw-SpacedText $g $script:headText $script:fontHead $script:brushHead $spacedCx $spacedCy $spacedTr $spacedMax

    # ---- title (centered, with animated dots right next to it) ----
    if (-not $script:showSummary) {
        Draw-AnimatedDots $g $script:titleText $script:titleRect $script:fontTitle $script:brushWhite
    } else {
        $g.DrawString($script:titleText, $script:fontTitle, $script:brushWhite, $script:titleRect, $script:fmtCenter)
    }

    # ---- logo: pre-rendered orbital ring + image (blit only) ----
    if ($script:ringFrames) {
        $rf = $script:ringFrames[[int]($tSec * 3) % 36]
        $g.DrawImage($rf, [single]($script:logoCX - $script:animStep), [single]($script:logoCY - $script:animStep))
    }

    if ($script:logoFrames -and $script:logoFrameCount -gt 0 -and $script:logoFrames[$script:logoFrameIndex]) {
        $g.DrawImage($script:logoFrames[$script:logoFrameIndex], $script:logoX, $script:logoY, $script:logoW, $script:logoH)
    }

    # ---- status (animated dots right next to it, when summary) ----
    $statusBrush = New-Object System.Drawing.SolidBrush($script:statusColor)
    if ($script:showSummary -and $script:errorCount -eq 0) {
        Draw-AnimatedDots $g $script:statusText $script:statusRect $script:fontStatus $statusBrush
    } else {
        $g.DrawString($script:statusText, $script:fontStatus, $statusBrush, $script:statusRect, $script:fmtCenter)
    }
    $statusBrush.Dispose()

    # ---- progress bar ----
    $bhh = [math]::Max(8, $script:barH - 4)
    $yy = $script:barY + ($script:barH - $bhh) / 2
    $full = New-Object System.Drawing.RectangleF([single]$script:barX, [single]$yy, [single]$script:barW, [single]$bhh)
    if ($full.Width -gt 0 -and $full.Height -gt 0) {
        $rad = $bhh / 2
        $path = New-RoundRect $full ([single]$rad)
        $g.FillPath($script:brushTrack, $path)
        $path.Dispose()
        $ratio = $script:displayed
        if ($ratio -lt 0) { $ratio = 0 } elseif ($ratio -gt 1) { $ratio = 1 }
        $fw = $full.Width * $ratio
        if ($fw -ge 1) {
            $fill = New-Object System.Drawing.RectangleF($full.X, $full.Y, [single][math]::Max($fw, $bhh), $full.Height)
            $glowPath = New-RoundRect $fill ([single]$rad)
            Draw-PathGlow $g $glowPath ([System.Drawing.Color]::FromArgb(255, 0, 229, 255)) 1 40 ([single](5 * $script:scale))
            $glowPath.Dispose()
            $path = New-RoundRect $fill ([single]$rad)
            $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($fill, [System.Drawing.Color]::FromArgb(124, 77, 255), [System.Drawing.Color]::FromArgb(0, 229, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $g.FillPath($grad, $path)
            $grad.Dispose()
            $path.Dispose()
            $ms = $nowMs % 1600
            $st = $ms / 1600.0
            $sxp = $fill.X + $fill.Width * $st
            $path = New-RoundRect $fill ([single]$rad)
            $old = $g.Clip
            $g.SetClip($path)
            $sh = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF([single]($sxp - 40), $full.Y, [single]80, $full.Height)), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [System.Drawing.Color]::FromArgb(70, 255, 255, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $sh.SetSigmaBellShape(0.5)
            $g.FillRectangle($sh, [single]($sxp - 40), $full.Y, [single]80, $full.Height)
            $sh.Dispose()
            $g.Clip = $old
            $old.Dispose()
            $path.Dispose()
        }
    }
    # ---- percent chip ----
    $pctText = '{0}%' -f [int]([math]::Round($script:displayed * 100))
    $chipRect = New-Object System.Drawing.RectangleF([single]$script:chipX, [single]$script:chipY, [single]$script:chipW, [single]$script:chipH)
    $chipPath = New-RoundRect $chipRect ([single]($script:chipH / 2))
    $chipGrad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($chipRect, [System.Drawing.Color]::FromArgb(60, 124, 77, 255), [System.Drawing.Color]::FromArgb(60, 0, 229, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.FillPath($chipGrad, $chipPath)
    $chipPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(160, 0, 229, 255), 1)
    $g.DrawPath($chipPen, $chipPath)
    $chipPath.Dispose(); $chipGrad.Dispose(); $chipPen.Dispose()
    $g.DrawString($pctText, $script:fontPercent, $script:brushWhite, $chipRect, $script:fmtCenter)

    # ---- summary (centered on the CARD) ----
    if ($script:showSummary) {
        $r1 = New-Object System.Drawing.RectangleF([single]$script:cardRect.X, $script:summaryY, [single]$script:cardRect.Width, 24)
        $r2 = New-Object System.Drawing.RectangleF([single]$script:cardRect.X, ($script:summaryY + 26), [single]$script:cardRect.Width, 24)
        $g.DrawString($script:summaryDuration, $script:fontSmall, $script:brushGray, $r1, $script:fmtCenter)
        $g.DrawString($script:summaryResult, $script:fontSmall, $script:brushGray, $r2, $script:fmtCenter)
    }

    # ---- footer: gradient hairline + patience note ----
    $flX1 = [single]($W * 0.20)
    $flX2 = [single]($W * 0.80)
    $fl = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF($flX1, [single]$script:footerY, [single]($flX2 - $flX1), 1)), [System.Drawing.Color]::FromArgb(0, 0, 229, 255), [System.Drawing.Color]::FromArgb(120, 124, 77, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $fl.SetSigmaBellShape(0.4)
    $flPen = New-Object System.Drawing.Pen($fl, 1)
    $g.DrawLine($flPen, $flX1, [single]$script:footerY, $flX2, [single]$script:footerY)
    $flPen.Dispose(); $fl.Dispose()
    $rBot = New-Object System.Drawing.RectangleF(0, ($script:footerY + 14 * $script:scale), $W, 40)
    $g.DrawString($script:bottomText, $script:fontFooter, $script:brushFooter, $rBot, $script:fmtCenter)
    $script:lastPaintMs = $nowMs
})
$form.Controls.Add($script:backdrop)

# ============================================================
# Timers
# ============================================================
$dotTimer = New-Object System.Windows.Forms.Timer
$dotTimer.Interval = 350
$dotTimer.Add_Tick({
    $script:dotCount = ($script:dotCount + 1) % 4
    $script:backdrop.Invalidate()
})

$bgTimer = New-Object System.Windows.Forms.Timer
$bgTimer.Interval = 33
$bgTimer.Add_Tick({
    if ($script:finished) {
        $script:displayed = 1.0
    } else {
        if ($script:statusCount -gt $script:progressMax) { $script:progressMax = $script:statusCount }
        $targetRatio = if ($script:progressMax -gt 0) { $script:statusCount / [double]$script:progressMax } else { 0 }
        $script:displayed += ($targetRatio - $script:displayed) * 0.18
        if ([math]::Abs($targetRatio - $script:displayed) -lt 0.003) { $script:displayed = $targetRatio }
    }

    if ($script:logoFrameCount -gt 1) {
        $script:logoElapsed += 0.033
        $guard = 0
        while ($script:logoElapsed -ge $script:logoDelays[$script:logoFrameIndex] -and $guard -lt 200) {
            $script:logoElapsed -= $script:logoDelays[$script:logoFrameIndex]
            $script:logoFrameIndex = ($script:logoFrameIndex + 1) % $script:logoFrameCount
            $guard++
        }
    }
    if ($script:logoFrameCount -gt 0 -and $script:logoFrames -and -not $script:logoFrameProcessed[$script:logoFrameIndex]) {
        try {
            $script:logoAnimImg.SelectActiveFrame([System.Drawing.Imaging.FrameDimension]::Time, $script:logoFrameIndex)
            $fb = New-Object System.Drawing.Bitmap($script:logoAnimImg)
            $script:logoFrames[$script:logoFrameIndex] = [LogoHelper.Trans]::MakeTransparent($fb, $script:logoDisplay)
            $fb.Dispose()
        } catch { }
        $script:logoFrameProcessed[$script:logoFrameIndex] = $true
    }

    $script:backdrop.Invalidate()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    Update-FromLog

    if ($script:cmdFinished -or (Test-Path -LiteralPath $script:finishMarker)) {
        $script:finished = $true
    }

    if ($script:finished -and -not $script:summaryShown) {
        $script:summaryShown = $true
        $script:showSummary = $true
        $script:titleText = 'Installation Complete'
        $script:headText = '- Thank you for using LexBoosT OS -'
        if ($script:errorCount -gt 0) {
            $script:statusText = "Completed with $($script:errorCount) error(s)"
            $script:statusColor = [System.Drawing.Color]::FromArgb(255, 90, 90)
        } else {
            $script:statusText = 'Completed successfully! Your device will reboot in a few seconds, please wait'
            $script:statusColor = [System.Drawing.Color]::White
        }
        $dur = (Get-Date) - $script:startTime
        $script:summaryDuration = "Duration: $(Format-Duration $dur)"
        $script:summaryResult = "Errors: $($script:errorCount)   |   Warnings: $($script:warningCount)"
    }
    elseif (-not $script:finished -and $script:latestStatus) {
        $t = $script:latestStatus
        if ($t.Length -gt 72) { $t = $t.Substring(0, 72) + '...' }
        $script:statusText = $t
        $script:statusColor = [System.Drawing.Color]::White
    }

    $script:backdrop.Invalidate()

    $running = @(Get-Process -Name $script:ameProcesses -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { Close-Overlay }
})

# ============================================================
# Start
# ============================================================
$form.Add_Shown({
    Layout
    [System.Windows.Forms.Cursor]::Hide()
    $form.Activate()
    $timer.Start()
    $dotTimer.Start()
    $bgTimer.Start()
})

[void]$form.ShowDialog()
