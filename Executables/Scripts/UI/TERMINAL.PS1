# Script to install Windows Terminal if missing and configure settings.json
# Path to settings.json file
$settingsPath = "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

function Write-Log {
    param([string]$Status, [string]$Message)
    Write-Host "[$Status] $Message"
}

# Function to check if Windows Terminal is installed
function Test-WindowsTerminalInstalled {
    $terminalPaths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\WindowsTerminal.exe",
        "$env:PROGRAMFILES\WindowsApps\Microsoft.WindowsTerminal_*\WindowsTerminal.exe"
    )
    
    foreach ($path in $terminalPaths) {
        if (Test-Path $path) {
            return $true
        }
    }
    
    try {
        $wingetList = winget list --id Microsoft.WindowsTerminal 2>$null
        if ($wingetList -match "Microsoft.WindowsTerminal") {
            return $true
        }
    } catch {
        # Winget might not be available
    }
    
    return $false
}

# Function to check if Winget is installed
function Test-WingetInstalled {
    try {
        $wingetVersion = winget --version 2>$null
        return $? -and ($wingetVersion -ne $null)
    } catch {
        return $false
    }
}

# Function to install Winget (if missing on older Windows versions)
function Install-Winget {
    Write-Log '+' "Winget not found. Attempting to install Winget..."
    
    $wingetUrl = "https://aka.ms/getwinget"
    $tempFile = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    
    try {
        Invoke-WebRequest -Uri $wingetUrl -OutFile $tempFile -UseBasicParsing
        Add-AppxPackage -Path $tempFile
        Remove-Item $tempFile -Force
        Write-Log '+' "Winget installed successfully."
        return $true
    } catch {
        Write-Log '-' "ERROR: Failed to install Winget automatically."
        return $false
    }
}

# Main script execution
try {
    # Step 1: Install Windows Terminal if missing
    if (-not (Test-WindowsTerminalInstalled)) {
        Write-Log '+' "Windows Terminal is not installed. Installing via Winget..."
        
        if (-not (Test-WingetInstalled)) {
            Write-Log '+' "Winget not found. Attempting to install it first..."
            if (-not (Install-Winget)) {
                Write-Log '-' "ERROR: Cannot proceed without Winget."
                exit 1
            }
        }
        
        try {
            winget install --id Microsoft.WindowsTerminal -e --accept-package-agreements --accept-source-agreements
            Write-Log '+' "Windows Terminal installed successfully."
            Start-Sleep -Seconds 3
        } catch {
            Write-Log '-' "ERROR: Failed to install Windows Terminal."
            exit 1
        }
    } else {
        Write-Log '+' "Windows Terminal is already installed."
    }
} catch {
    Write-Log '-' "ERROR: Installation check failed."
    exit 1
}

# JSON content to write
$jsonContent = @'
{
    "$help": "https://aka.ms/terminal-documentation",
    "$schema": "https://aka.ms/terminal-profiles-schema",
    "actions": [],
    "copyFormatting": "none",
    "copyOnSelect": false,
    "defaultProfile": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
    "keybindings": 
    [
        {
            "id": "Terminal.CopyToClipboard",
            "keys": "ctrl+c"
        },
        {
            "id": "Terminal.PasteFromClipboard",
            "keys": "ctrl+v"
        },
        {
            "id": "Terminal.DuplicatePaneAuto",
            "keys": "alt+shift+d"
        }
    ],
    "newTabMenu": 
    [
        {
            "type": "remainingProfiles"
        }
    ],
    "profiles": 
    {
        "defaults": 
        {
            "backgroundImage": "desktopWallpaper",
            "backgroundImageOpacity": 0.2,
            "colorScheme": "CGA",
            "cursorHeight": 25,
            "cursorShape": "bar",
            "experimental.retroTerminalEffect": true,
            "font": 
            {
                "face": "Cascadia Mono",
                "size": 12,
                "weight": "normal"
            },
            "opacity": 98,
            "useAcrylic": false
        },
        "list": 
        [
            {
                "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoLogo",
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "hidden": false,
                "name": "Windows PowerShell"
            },
            {
                "commandline": "%SystemRoot%\\System32\\cmd.exe",
                "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}",
                "hidden": false,
                "name": "Command Prompt"
            },
            {
                "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
                "hidden": false,
                "name": "PowerShell",
                "source": "Windows.Terminal.PowershellCore"
            },
            {
                "guid": "{b453ae62-4e3d-5e58-b989-0a998ec441b8}",
                "hidden": false,
                "name": "Azure Cloud Shell",
                "source": "Windows.Terminal.Azure"
            },
            {
                "guid": "{86b4c868-3d18-59e6-9bef-15e8cebc4c20}",
                "hidden": false,
                "name": "Developer Command Prompt for VS 18",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "guid": "{39c5954f-1a08-504f-be47-e934deff2235}",
                "hidden": false,
                "name": "Developer PowerShell for VS 18",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "guid": "{2ece5bfe-50ed-5f3a-ab87-5cd4baafed2b}",
                "hidden": false,
                "name": "Git Bash",
                "source": "Git"
            }
        ]
    },
    "schemes": 
    [
        {
            "background": "#000000",
            "black": "#0C0C0C",
            "blue": "#0037DA",
            "brightBlack": "#767676",
            "brightBlue": "#3B78FF",
            "brightCyan": "#61D6D6",
            "brightGreen": "#16C60C",
            "brightPurple": "#B4009E",
            "brightRed": "#E74856",
            "brightWhite": "#F2F2F2",
            "brightYellow": "#F9F1A5",
            "cursorColor": "#FFFFFF",
            "cyan": "#3A96DD",
            "foreground": "#FFFFFF",
            "green": "#13A10E",
            "name": "Campbell (modified)",
            "purple": "#881798",
            "red": "#C50F1F",
            "selectionBackground": "#FFFFFF",
            "white": "#CCCCCC",
            "yellow": "#C49C00"
        },
        {
            "background": "#012456",
            "black": "#0C0C0C",
            "blue": "#0037DA",
            "brightBlack": "#767676",
            "brightBlue": "#3B78FF",
            "brightCyan": "#61D6D6",
            "brightGreen": "#16C60C",
            "brightPurple": "#B4009E",
            "brightRed": "#E74856",
            "brightWhite": "#F2F2F2",
            "brightYellow": "#F9F1A5",
            "cursorColor": "#FFFFFF",
            "cyan": "#3A96DD",
            "foreground": "#CCCCCC",
            "green": "#13A10E",
            "name": "Campbell Powershell (modified)",
            "purple": "#881798",
            "red": "#C50F1F",
            "selectionBackground": "#FFFFFF",
            "white": "#CCCCCC",
            "yellow": "#C49C00"
        },
        {
            "background": "#141414",
            "black": "#000000",
            "blue": "#0575D8",
            "brightBlack": "#817E7E",
            "brightBlue": "#688DFD",
            "brightCyan": "#32E0FB",
            "brightGreen": "#37E57B",
            "brightPurple": "#ED6FE9",
            "brightRed": "#FF643B",
            "brightWhite": "#D3D8D9",
            "brightYellow": "#FCCD1A",
            "cursorColor": "#37E57B",
            "cyan": "#1DB6BB",
            "foreground": "#BAB7B6",
            "green": "#60B442",
            "name": "Dimidium (modified)",
            "purple": "#AF5ED2",
            "red": "#CF494C",
            "selectionBackground": "#FFFFFF",
            "white": "#BAB7B6",
            "yellow": "#DB9C11"
        }
    ],
    "themes": [],
    "useAcrylicInTabRow": false
}
'@

# Step 2: Configure settings.json
try {
    # Create backup silently if settings.json exists
    if (Test-Path $settingsPath) {
        $backupPath = "$settingsPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $settingsPath $backupPath -Force
    } else {
        $settingsDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }
    }
    
    # Validate and write content to file
    $jsonObject = $jsonContent | ConvertFrom-Json
    $prettyJson = $jsonObject | ConvertTo-Json -Depth 10
    $prettyJson | Set-Content -Path $settingsPath -Encoding UTF8 -Force
    
    Write-Log '+' "SUCCESS: settings.json has been configured successfully."
    Write-Log '+' "Windows Terminal is ready to use."
    exit 0
    
} catch {
    Write-Log '-' "ERROR: Failed to write settings.json."
    Write-Log '-' "Details: $_"
    exit 1
}