#Requires -Version 5.1
# =============================================================================
# LexBoosT OS - Welcome panel
# -----------------------------------------------------------------------------
# Runs after sign-in (launched hidden by launch_welcome_panel.vbs via the
# scheduled Logon task). Waits until the user's Explorer desktop is available,
# then shows one short branded LexBoosT OS welcome panel. It does not
# enumerate or display boot, process, service, or startup-app status.
#
# Self-contained WPF window (no project, no deps).
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'
$sessionId  = (Get-Process -Id $PID).SessionId
$mutexName  = 'Local\LexBoosTWelcomePanel_' + $sessionId
$createdNew = $false
$mutex      = [System.Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) { exit 0 }

try {
    # A logon trigger can fire while Explorer is still being created. Do not show
    # the custom panel until the actual user desktop exists; if it never appears,
    # silently exit instead of presenting a misleading post-boot panel.
    $deadline = (Get-Date).AddSeconds(30)
    $desktopReady = $false
    do {
        $desktopReady = [bool](Get-Process -Name explorer -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $sessionId } |
            Select-Object -First 1)
        if (-not $desktopReady) { Start-Sleep -Milliseconds 250 }
    } while (-not $desktopReady -and (Get-Date) -lt $deadline)

    if (-not $desktopReady) { exit 0 }
    Start-Sleep -Milliseconds 1400

    # Localize the panel to the user's UI language: French if the system is
    # French, English for every other detected language. Get-Culture reflects the
    # interactive user's UI culture in the logon task.
    $uiLang = (Get-Culture).Name
    $isFrench = $uiLang -like 'fr*'
    if ($isFrench) {
        $tWelcomeTo      = 'BIENVENUE SUR'
        $tTitle          = 'Bienvenue sur LexBoosT OS'
        $tGreetingPrefix = 'Amuse toi bien, '
        $tTagline        = 'LÉGER - STABLE - RAPIDE'
    } else {
        $tWelcomeTo      = 'WELCOME TO'
        $tTitle          = 'Welcome to LexBoosT OS'
        $tGreetingPrefix = 'Have fun, '
        $tTagline        = 'LIGHTWEIGHT - STABLE - FAST'
    }

    Add-Type -AssemblyName @('PresentationFramework', 'PresentationCore', 'WindowsBase')

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="__TITLE__" Width="640" Height="410" Opacity="0"
        WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterScreen" Topmost="True"
        AllowsTransparency="True" Background="Transparent">
    <Border CornerRadius="18" Background="#F00A1220" BorderBrush="#805B8DEF" BorderThickness="1.4" Padding="34">
        <Border.Effect>
            <DropShadowEffect Color="#AA4C7DFF" BlurRadius="28" ShadowDepth="0" Opacity="0.45"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="__WELCOME_TO__" Foreground="#FFA9C3F7"
                       FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14"
                       FontWeight="SemiBold" HorizontalAlignment="Center"/>
            <Image Grid.Row="1" Name="LogoImage" Width="108" Height="108" Stretch="Uniform"
                   Margin="0,16,0,16" HorizontalAlignment="Center"
                   RenderOptions.BitmapScalingMode="HighQuality"/>
            <TextBlock Grid.Row="2" Text="LexBoosT OS" Foreground="White"
                       FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="46"
                       FontWeight="Bold" Margin="0,0,0,0" HorizontalAlignment="Center"/>
            <Border Grid.Row="3" Width="250" Height="2" CornerRadius="1" Margin="0,15,0,15"
                    Background="#FF4C7DFF" HorizontalAlignment="Center"/>
            <TextBlock Grid.Row="4" Name="UserGreeting" Foreground="#FFE8EEF7"
                       FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="18"
                       TextAlignment="Center" HorizontalAlignment="Center"/>
            <TextBlock Grid.Row="5" Text="__TAGLINE__" Foreground="#FF8E9FC0"
                       FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11"
                       FontWeight="SemiBold" Margin="0,18,0,0"
                       VerticalAlignment="Bottom" HorizontalAlignment="Center"/>
        </Grid>
    </Border>
</Window>
'@

    $xaml = $xaml.Replace('__TITLE__', $tTitle)
    $xaml = $xaml.Replace('__WELCOME_TO__', $tWelcomeTo)
    $xaml = $xaml.Replace('__TAGLINE__', $tTagline)

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $greeting = $window.FindName('UserGreeting')
    $displayName = $env:USERNAME
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = 'Player' }
    # Prefix normal + username in bold (two Runs so only the name is bold)
    $greeting.Inlines.Clear()
    $greeting.Inlines.Add([System.Windows.Documents.Run]::new($tGreetingPrefix))
    $boldRun = [System.Windows.Documents.Run]::new($displayName)
    $boldRun.FontWeight = [System.Windows.FontWeights]::Bold
    $greeting.Inlines.Add($boldRun)

    # Brand logo, centered in the panel. Fixed 108x108 so it is identical at any
    # screen resolution. The file is always expected at this absolute path.
    $logo = $window.FindName('LogoImage')
    $logoPath = Join-Path 'C:\Windows\LexBoosTOS\Resources' 'user.png'
    if ($logo -and (Test-Path -LiteralPath $logoPath)) {
        try {
            $img = [System.Windows.Media.Imaging.BitmapImage]::new()
            $img.BeginInit()
            $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $img.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
            $img.UriSource = [System.Uri]::new($logoPath, [System.UriKind]::Absolute)
            $img.EndInit()
            $img.Freeze()
            $logo.Source = $img
        } catch {
            # Missing/unreadable logo: hide the slot so the panel still renders.
            $logo.Visibility = 'Collapsed'
        }
    } else {
        if ($logo) { $logo.Visibility = 'Collapsed' }
    }

    $window.Add_Loaded({
        $fadeIn = New-Object Windows.Media.Animation.DoubleAnimation
        $fadeIn.From = 0
        $fadeIn.To = 1
        $fadeIn.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(450))
        $window.BeginAnimation([Windows.Window]::OpacityProperty, $fadeIn)
    })

    $closePanel = {
        $fadeOut = New-Object Windows.Media.Animation.DoubleAnimation
        $fadeOut.From = $window.Opacity
        $fadeOut.To = 0
        $fadeOut.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(550))
        $fadeOut.Add_Completed({ $window.Close() })
        $window.BeginAnimation([Windows.Window]::OpacityProperty, $fadeOut)
    }

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(5)
    $timer.Add_Tick({
        $timer.Stop()
        & $closePanel
    })

    $window.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
            $timer.Stop()
            & $closePanel
        }
    })
    $window.Add_MouseLeftButtonDown({
        $timer.Stop()
        & $closePanel
    })
    $window.Add_Closed({ $timer.Stop() })

    $timer.Start()
    [void]$window.ShowDialog()
} finally {
    if ($mutex) {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}
