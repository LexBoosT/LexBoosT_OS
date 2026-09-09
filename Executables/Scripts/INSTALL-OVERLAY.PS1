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
    if ($script:dotCount -le 0) { return }
    $tSz = $g.MeasureString($BaseText, $Font)
    $dstep = [single]($Font.Height * 0.45)
    $dotsRect = New-Object System.Drawing.RectangleF(
        [single]($Rect.Width / 2 + $tSz.Width / 2 + 6),
        [single]$Rect.Y,
        [single]($dstep * 3),
        [single]$Rect.Height)
    $dotsFmt = New-Object System.Drawing.StringFormat
    $dotsFmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    for ($i = 0; $i -lt $script:dotCount; $i++) {
        $dRect = New-Object System.Drawing.RectangleF(
            [single]($dotsRect.X + $i * $dstep),
            $dotsRect.Y,
            $dstep,
            $dotsRect.Height)
        $g.DrawString('.', $Font, $Brush, $dRect, $dotsFmt)
    }
    $dotsFmt.Dispose()
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
$script:headText = '- Welcome to the LexBoosT OS Installation Process -'
$script:statusText = 'Initializing LexBoosT OS...'
$script:statusColor = [System.Drawing.Color]::White
$script:summaryDuration = ''
$script:summaryResult = ''
$script:showSummary = $false
$script:bottomText = 'Some installation steps may take a while. Please be patient.'

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
    $pad = [int](24 * $script:scale)

    $script:headY = [int]($H * 0.06)
    $script:headRect = New-Object System.Drawing.RectangleF(0, $script:headY, $W, 80)
    $script:titleY = $script:headY + 96
    $script:titleRect = New-Object System.Drawing.RectangleF(0, $script:titleY, $W, 90)

    $script:logoW = $script:logoDisplay
    $script:logoH = $script:logoW
    $script:logoX = [int](($W - $script:logoW) / 2)
    $script:logoY = $script:titleY + 105

    $script:statusY = $script:logoY + $script:logoH + 40
    $script:statusRect = New-Object System.Drawing.RectangleF(0, $script:statusY, $W, 70)

    $script:barY = $script:statusY + 90
    $script:barW = [int]($W * 0.5)
    $script:barH = [int](20 * $script:scale)
    $script:barX = [int](($W - $script:barW) / 2)

    $script:summaryY = $script:barY + $script:barH + 24
    $script:bottomY = [int]($H * 0.90)

    $script:hackerPad = $pad
    $script:hackerSize = New-Object System.Drawing.Size([int]($W * 0.42), [int]($H * 0.40))
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

$script:fontTitle = New-ScaledFont 'Segoe UI' 26 ([System.Drawing.FontStyle]::Bold)
$script:fontHead = New-ScaledFont 'Segoe UI' 34 ([System.Drawing.FontStyle]::Bold)
$script:fontStatus = New-ScaledFont 'Segoe UI' 20 ([System.Drawing.FontStyle]::Bold)
$script:fontSmall = New-ScaledFont 'Segoe UI' 12 ([System.Drawing.FontStyle]::Regular)
$script:fontPercent = New-ScaledFont 'Segoe UI' 12 ([System.Drawing.FontStyle]::Bold)
$script:fontHack = New-ScaledFont 'Consolas' 10 ([System.Drawing.FontStyle]::Regular)
$script:fontBottom = New-ScaledFont 'Segoe UI' 15 ([System.Drawing.FontStyle]::Regular)
$script:brushWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$script:brushHead = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(175, 255, 255, 255))
$script:brushCyan = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 229, 255))
$script:brushGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(175, 180, 190))
$script:brushDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 145, 155))
$script:brushBottom = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(130, 175, 180, 190))
$script:brushTrack = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(16, 16, 20))
$script:brushBorder = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 150, 155, 170))
$script:penBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 150, 155, 170))
$script:fmtCenter = New-Object System.Drawing.StringFormat
$script:fmtCenter.Alignment = [System.Drawing.StringAlignment]::Center
$script:fmtCenter.LineAlignment = [System.Drawing.StringAlignment]::Center

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
    $g.Clear([System.Drawing.Color]::Black)
    $W = $script:backdrop.Width
    $H = $script:backdrop.Height
    if ($W -lt 1 -or $H -lt 1) { return }

    # ---- logo (animated, transparent bg) ----
    if ($script:logoFrames -and $script:logoFrameCount -gt 0 -and $script:logoFrames[$script:logoFrameIndex]) {
        $g.DrawImage($script:logoFrames[$script:logoFrameIndex], $script:logoX, $script:logoY, $script:logoW, $script:logoH)
    }

    # ---- welcome / thank you headline ----
    $g.DrawString($script:headText, $script:fontHead, $script:brushHead, $script:headRect, $script:fmtCenter)

    # ---- title (fixed) ----
    $g.DrawString($script:titleText, $script:fontTitle, $script:brushWhite, $script:titleRect, $script:fmtCenter)
    if (-not $script:showSummary) {
        Draw-AnimatedDots $g $script:titleText $script:titleRect $script:fontTitle $script:brushWhite
    }

    # ---- status ----
    $statusBrush = New-Object System.Drawing.SolidBrush($script:statusColor)
    $g.DrawString($script:statusText, $script:fontStatus, $statusBrush, $script:statusRect, $script:fmtCenter)
    if ($script:showSummary -and $script:errorCount -eq 0) {
        Draw-AnimatedDots $g $script:statusText $script:statusRect $script:fontStatus $statusBrush
    }
    $statusBrush.Dispose()

    # ---- progress bar ----
    $bhh = [math]::Max(8, $script:barH - 6)
    $yy = $script:barY + ($script:barH - $bhh) / 2
    $full = New-Object System.Drawing.RectangleF([single]($script:barX + 3), [single]$yy, [single][math]::Max(0, $script:barW - 6), [single]$bhh)
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
            $path = New-RoundRect $fill ([single]$rad)
            $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($fill, [System.Drawing.Color]::FromArgb(124, 77, 255), [System.Drawing.Color]::FromArgb(0, 229, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $g.FillPath($grad, $path)
            $grad.Dispose()
            $path.Dispose()
            $ms = ([DateTime]::Now.Ticks / 10000) % 1400
            $st = $ms / 1400.0
            $sxp = $fill.X + $fill.Width * $st
            $path = New-RoundRect $fill ([single]$rad)
            $old = $g.Clip
            $g.SetClip($path)
            $sh = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF([single]($sxp - 40), [single]$script:barY, [single]80, [single]$script:barH)), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [System.Drawing.Color]::FromArgb(70, 255, 255, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $sh.SetSigmaBellShape(0.5)
            $g.FillRectangle($sh, [single]($sxp - 40), [single]$script:barY, [single]80, [single]$script:barH)
            $sh.Dispose()
            $g.Clip = $old
            $old.Dispose()
            $path.Dispose()
        }
        $path = New-RoundRect $full ([single]$rad)
        $g.DrawPath($script:penBorder, $path)
        $path.Dispose()
    }

    # ---- percent ----
    $pctText = '{0}%' -f [int]([math]::Round($script:displayed * 100))
    $g.DrawString($pctText, $script:fontPercent, $script:brushCyan, [single]($script:barX + $script:barW + 14), [single]($script:barY + 2))

    # ---- summary ----
    if ($script:showSummary) {
        $r1 = New-Object System.Drawing.RectangleF(0, $script:summaryY, $W, 24)
        $r2 = New-Object System.Drawing.RectangleF(0, ($script:summaryY + 26), $W, 24)
        $g.DrawString($script:summaryDuration, $script:fontSmall, $script:brushGray, $r1, $script:fmtCenter)
        $g.DrawString($script:summaryResult, $script:fontSmall, $script:brushGray, $r2, $script:fmtCenter)
    }

    # ---- hacker terminal ----
    $n = $script:procBuf.Count
    if ($n -gt 0) {
        $lx = $script:hackerPad
        $ly = $script:hackerPad
        $lh = [int]($script:fontHack.Height) + 4
        for ($i = 0; $i -lt $n; $i++) {
            $item = $script:procBuf[$i]
            $fade = 0.35 + 0.65 * (($i + 1) / $n)
            $base = $item.Color
            $c = [System.Drawing.Color]::FromArgb([int]($base.R * $fade), [int]($base.G * $fade), [int]($base.B * $fade))
            $sb = New-Object System.Drawing.SolidBrush($c)
            $g.DrawString($item.Text, $script:fontHack, $sb, [single]$lx, [single]$ly)
            $sb.Dispose()
            $ly += $lh
        }
    }
    # ---- bottom patience note ----
    $rBot = New-Object System.Drawing.RectangleF(0, $script:bottomY, $W, 44)
    $g.DrawString($script:bottomText, $script:fontBottom, $script:brushBottom, $rBot, $script:fmtCenter)
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
