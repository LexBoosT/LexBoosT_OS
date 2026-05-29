# LexBoosT OS™ 26.06

🌍 **Languages**: [🇫🇷 Français](#lexboost-os-26055--documentation-française) | [🇬🇧 English](#lexboost-os-26055--english-documentation)

---

## LexBoosT OS™ 26.06 — Documentation française

### *Libérez des performances supérieures — sans compromis*

**LexBoosT OS™** est un playbook d'optimisation Windows 11 qui transforme votre système en profondeur. Conçu pour les gamers, power users et professionnels exigeants, il applique **250+ services reconfigurés**, **100+ packages bloatware supprimés** et **60+ familles de tweaks registre** via **7 phases de déploiement** orchestrées avec précision.

---

### 🚀 Performances vs Windows 11 Stock

| Indicateur | Windows 11 Stock | LexBoosT OS™ | Gain |
|---|---|---|---|
| **Processus en idle** | ~180-220 | ~50-70 | **-65%** |
| **RAM idle (16 GB)** | ~4.5-5.5 GB | ~1.8-2.5 GB | **-50%** |
| **Services exécutés** | ~120-150 | ~40-60 | **-60%** |
| **Latence DPC** | 300-800 µs | 50-150 µs | **-70%** |
| **Temps de boot** | 25-40 sec | 10-18 sec | **-55%** |
| **FPS moyen (gaming)** | Baseline | +10-20% | **+15%** |
| **Perf CPU (Spectre off)** | Baseline | +5-15% | **+10%** |
| **Télémétrie sortante** | ~250 req/h | 0 | **-100%** |
| **Applications inutiles** | 30+ | 0 | **-100%** |

*Mesures indicatives sur hardware moyen (Ryzen 5 / Core i5, 16 GB RAM, NVMe SSD). Les résultats varient selon la configuration.*

---

### ✅ Ce que fait LexBoosT OS™

#### 💻 Optimisations Système
- **Kernel** : MMCSS recalibré (NetworkThrottlingIndex=ffffffff, NoLazyMode), TSX activé, ThreadDpcEnable, DPC timeouts équilibrés 100ms
- **CPU** : Mitigations Spectre/Meltdown désactivées (+5-15% CPU), Core Parking exposé et contrôlable, Priorités IFEO par processus (csrss.exe IoPriority=High, SearchIndexer CpuPriority=Below Normal), Win32PrioritySeparation optimisé
- **Mémoire** : DisablePagingExecutive (noyau en RAM), Memory Compression désactivée si 16 GB+, CFG activé, Superfetch désactivé
- **Boot** : BCD tweaks (disabledynamictick, linearaddress57, isolatedcontext), NTFS optimisé (disableLastAccess, 8dot3, MFT zone), ServicesPipeTimeout=30s

#### 🌐 Optimisations Réseau
- **TCP/IP** : Nagle désactivé (TcpNoDelay, TcpAckFrequency, TCPDelAckTicks=0), TcpTimedWaitDelay=30s, MaxUserPort=65534, MaxFreeTcbs=65536
- **DNS** : DNS-over-HTTPS activé natif, Cache TTL 24h, NegativeCache TTL 5s
- **QoS** : 29 applications VoIP priorisées (Discord, Teams, Zoom, Skype, etc.), EEE désactivé, FlowControl off, RSS activé
- **Carte réseau** : InterruptModeration désactivé, LargeSendOffload désactivé, GreenEthernet désactivé, PowerSavingMode off

#### 🎮 Gaming & GPU
- **MMCSS Games Task** : GPU Priority=8, Priority=6, Latency Sensitive=True, SFIO Priority=High
- **HAGS** activé (Hardware-Accelerated GPU Scheduling)
- **Game DVR** complètement désactivé (HKLM+HKCU), GameBar controller/startup désactivé
- **DWM** : MaxQueuedPresentBuffers=2, FrameLatency=1, ModeChangeAnimation désactivé, Window Manager MMCSS GPU Priority=8
- **DirectX** : UserGpuPreferences configuré (flip model, VRR, AutoHDR)
- **MPO/DWM overlays** nettoyés pour éviter flickering et stuttering

#### 🔒 Privacy Radicale
- **Télémétrie** : AllowTelemetry=0 sur 5 chemins (HKLM, HKCU, Wow6432Node, PolicyManager, WMI Autologger)
- **IA bloquée** : generativeAI=Deny, systemAIModels=Deny, Copilot supprimé, GamingAI.Companion désactivé
- **Cortana, Advertising ID, InputPersonalization, Cloud Search** : tous désactivés
- **OneDrive KFM** bloqué, **Windows Update Auto Registration** désactivé
- **PerfTrack, SleepStudy, DOTNET_CLI_TELEMETRY, POWERSHELL_TELEMETRY** : tous désactivés
- **Edge telemetry, Windows Error Reporting, Feedback Notifications** : supprimés

#### 🧹 Débloat Agressif
- **100+ packages AppX** : Copilot, Teams, Xbox GameBar, OneDrive, Cortana, Bing*, Zune*, Office Hub, Skype, Spotify, LinkedIn, Clipchamp, Solitaire, Maps, Camera, People, GetHelp, FeedbackHub, etc.
- **Microsoft Edge** supprimable, **OneDrive** désinstallable
- **WinSxS** nettoyé, **DISM features** superflues désactivées

#### 🛡️ Fiabilité & Stabilité
- **Valeurs conservatrices** : Pas de DPC < 50ms, pas de Large Pages forcées, pas de SEHOP désactivé
- **Commentaires documentant chaque choix** dans les YAML (pourquoi 100ms, pourquoi pas 0, etc.)
- **Bugs corrigés** : DisableExceptionChainValidation, LargePageMinimum, HugePagesEnabled, lsass.exe PerfOptions
- **Compatibilité** : SysMain=Manual (pas Disabled), ClipSVC=Auto (Win+V), TokenBroker=Auto (MS Store)

#### 🎨 UX & Personnalisation
- **6 navigateurs** au choix (Brave, Firefox, Vivaldi, Chrome, OperaGX, Zen) avec lien vers privacytests.org
- **Thème dark personnalisé**, wallpapers desktop & lockscreen, avatar utilisateur
- **Menu Démarrer** nettoyable (Wipe!), icônes desktop personnalisables
- **LexBoosT Launcher** : 40+ outils post-installation (GPU tweaks, RAM cleaner, drive compactor, etc.)
- **Runtimes** : VC++ 2005-2022, .NET 7/8/9, DirectX, PowerShell 7, Notepad++, NanaZip

---

### 📥 Installation

1. **Prérequis** :
   - Windows 11 propre (builds 22000 à 28020 supportées)
   - Pilotes système à jour
   - Mettez à jour les applications du Microsoft Store
   - Vérifiez que les Widgets sont connectés à votre compte Microsoft
   - **Faites un point de restauration système** (précaution)
   - Redémarrez
2. **Lancez le Playbook**
3. **Suivez les options** : choisissez le navigateur, les packages à supprimer, le thème
4. **Redémarrez** une fois l'installation terminée

> **Compatibilité matérielle** : AMD Ryzen / Intel Core 8+ gén, 8 GB RAM minimum (16 GB recommandé), SSD/NVMe recommandé.

---

## LexBoosT OS™ 26.06 — English Documentation

### *Unleash Superior Performance — Zero Compromise*

**LexBoosT OS™** is a Windows 11 optimization playbook that deeply transforms your system. Built for gamers, power users, and demanding professionals, it applies **250+ reconfigured services**, **100+ bloatware packages removed**, and **60+ families of registry tweaks** across **7 orchestrated deployment phases**.

---

### 🚀 Performance vs Stock Windows 11

| Metric | Stock Windows 11 | LexBoosT OS™ | Improvement |
|---|---|---|---|
| **Idle processes** | ~180-220 | ~50-70 | **-65%** |
| **Idle RAM (16 GB)** | ~4.5-5.5 GB | ~1.8-2.5 GB | **-50%** |
| **Running services** | ~120-150 | ~40-60 | **-60%** |
| **DPC latency** | 300-800 µs | 50-150 µs | **-70%** |
| **Boot time** | 25-40 sec | 10-18 sec | **-55%** |
| **Avg FPS (gaming)** | Baseline | +10-20% | **+15%** |
| **CPU perf (Spectre off)** | Baseline | +5-15% | **+10%** |
| **Outgoing telemetry** | ~250 req/h | 0 | **-100%** |
| **Bloatware apps** | 30+ | 0 | **-100%** |

*Indicative measurements on mid-range hardware (Ryzen 5 / Core i5, 16 GB RAM, NVMe SSD). Results vary by configuration.*

---

### ✅ What LexBoosT OS™ Does

#### 💻 System Optimizations
- **Kernel**: MMCSS recalibrated (NetworkThrottlingIndex=ffffffff, NoLazyMode), TSX enabled, ThreadDpcEnable, balanced DPC timeouts at 100ms
- **CPU**: Spectre/Meltdown mitigations disabled (+5-15% CPU), Core Parking exposed & controllable, IFEO per-process priorities (csrss.exe IoPriority=High, SearchIndexer CpuPriority=Below Normal), optimized Win32PrioritySeparation
- **Memory**: DisablePagingExecutive (kernel in RAM), Memory Compression disabled if 16 GB+, CFG enabled, Superfetch disabled
- **Boot**: BCD tweaks (disabledynamictick, linearaddress57, isolatedcontext), NTFS optimized (disableLastAccess, 8dot3, MFT zone), ServicesPipeTimeout=30s

#### 🌐 Network Optimizations
- **TCP/IP**: Nagle disabled (TcpNoDelay, TcpAckFrequency, TCPDelAckTicks=0), TcpTimedWaitDelay=30s, MaxUserPort=65534, MaxFreeTcbs=65536
- **DNS**: Native DNS-over-HTTPS enabled, Cache TTL 24h, NegativeCache TTL 5s
- **QoS**: 29 VoIP apps prioritized (Discord, Teams, Zoom, Skype, etc.), EEE disabled, FlowControl off, RSS enabled
- **NIC**: InterruptModeration disabled, LargeSendOffload disabled, GreenEthernet disabled, PowerSavingMode off

#### 🎮 Gaming & GPU
- **MMCSS Games Task**: GPU Priority=8, Priority=6, Latency Sensitive=True, SFIO Priority=High
- **HAGS** enabled (Hardware-Accelerated GPU Scheduling)
- **Game DVR** fully disabled (HKLM+HKCU), GameBar controller/startup disabled
- **DWM**: MaxQueuedPresentBuffers=2, FrameLatency=1, ModeChangeAnimation disabled, Window Manager MMCSS GPU Priority=8
- **DirectX**: UserGpuPreferences configured (flip model, VRR, AutoHDR)
- **MPO/DWM overlays** cleaned up to prevent flickering and stuttering

#### 🔒 Radical Privacy
- **Telemetry**: AllowTelemetry=0 across 5 paths (HKLM, HKCU, Wow6432Node, PolicyManager, WMI Autologger)
- **AI blocked**: generativeAI=Deny, systemAIModels=Deny, Copilot removed, GamingAI.Companion disabled
- **Cortana, Advertising ID, InputPersonalization, Cloud Search**: all disabled
- **OneDrive KFM** blocked, **Windows Update Auto Registration** disabled
- **PerfTrack, SleepStudy, DOTNET_CLI_TELEMETRY, POWERSHELL_TELEMETRY**: all disabled
- **Edge telemetry, Windows Error Reporting, Feedback Notifications**: removed

#### 🧹 Aggressive Debloating
- **100+ AppX packages**: Copilot, Teams, Xbox GameBar, OneDrive, Cortana, Bing*, Zune*, Office Hub, Skype, Spotify, LinkedIn, Clipchamp, Solitaire, Maps, Camera, People, GetHelp, FeedbackHub, and more
- **Microsoft Edge** removable, **OneDrive** uninstallable
- **WinSxS** cleaned, **unnecessary DISM features** disabled

#### 🛡️ Reliability & Stability
- **Conservative values**: No DPC < 50ms, no forced Large Pages, SEHOP kept enabled
- **Every choice documented** in YAML comments (why 100ms, why not 0, etc.)
- **Bugs fixed**: DisableExceptionChainValidation, LargePageMinimum, HugePagesEnabled, lsass.exe PerfOptions
- **Compatibility**: SysMain=Manual (not Disabled), ClipSVC=Auto (Win+V), TokenBroker=Auto (MS Store)

#### 🎨 UX & Customization
- **6 browsers** to choose from (Brave, Firefox, Vivaldi, Chrome, OperaGX, Zen) with privacytests.org link
- **Custom dark theme**, desktop & lockscreen wallpapers, user avatar
- **Clean Start Menu** (Wipe option), customizable desktop icons
- **LexBoosT Launcher**: 40+ post-install tools (GPU tweaks, RAM cleaner, drive compactor, etc.)
- **Runtimes**: VC++ 2005-2022, .NET 7/8/9, DirectX, PowerShell 7, Notepad++, NanaZip

---

### 📥 Installation

1. **Requirements**:
   - Clean Windows 11 (builds 22000 to 28020 supported)
   - Updated system drivers
   - Update Microsoft Store apps
   - Verify widgets are connected to your Microsoft account
   - **Create a system restore point** (precaution)
   - Reboot
2. **Launch the Playbook**
3. **Follow the options**: choose your browser, packages to remove, theme preferences
4. **Reboot** once installation is complete

> **Hardware compatibility**: AMD Ryzen / Intel Core 8th gen+, 8 GB RAM minimum (16 GB recommended), SSD/NVMe recommended.

---

### 💙 Support the Project

- 🌐 Website: [astralex](https://lextermina7.wixsite.com/astralex)
- ☕ Donate: [Ko-fi](https://ko-fi.com/lexboostdev)

---

*LexBoosT OS™ — Built for performance. Engineered for reliability.*
