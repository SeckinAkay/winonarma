<#
.ÖZET
Gelişmiş Bakım, Optimizasyon ve Onarım Aracı V-01
Seçkin Akay tarafından düzenlendi ve güncellendi | Güncelleme: 2026-09-26
Kaynaklar - Açık kaynak geliştiricisi Steve projelerinden ve Google Gemini sohbet ajanlarından yararlanıldı.
.AÇIKLAMA
MSP saha ve uzaktan kullanımına yönelik, otomatik Windows 10/11 disk alanı geri kazanımı ve bütünlük onarımı aracı. 
Dell SupportAssist anlık görüntülerini (snapshots), tarayıcı, Office ve GPU önbelleklerini, Geri Dönüşüm Kutusu'nu, 
Teslimat İyileştirme (Delivery Optimization) verilerini, yükleyici önbelleğini, arama dizinini ve eski Windows.old klasörünü temizler; 
Windows Update veritabanını sıfırlar; DISM ve SFC onarımlarını gerçekleştirir; hazırda bekletme dosyasını kaldırır; 
ayrıca SSD TRIM işlemini uygularken her aşamada geri kazanılan disk alanı miktarını raporlar.

V-01 kapsam değişikliği: gizlilik/telemetri sıkılaştırma (eski Bölge 1), tarayıcı sıkılaştırma/uBlock
(eski Bölge 2) ve OEM/yazılım gereksiz bileşen temizliği (eski Bölge 3) kapsamdan çıkarıldı. 
Yalnızca temizlik ve onarım işlemlerini kapsar; canlı ve yönetilen uç noktalarda çalıştırılması güvenlidir.
.PARAMETER DryRun
Salt okunur tahmin modu. Herhangi bir değişiklik yapmaz; yıkıcı nitelikteki tüm adımlar atlanır
ve bunun yerine her bir hedef için boyutlandırma yapılarak, kategori bazında geri kazanılacak
tahmini alan miktarı ile öngörülen toplam boş alan bilgisi raporlanır. Disk uyarısı üzerine işlem yapmadan önce kullanın.
#>
param([switch]$DryRun)
$_fver   = "| V-01"
#Bölge Koşma Öncesi Kontrolleri
# ============================================================================
# Kutu çizim karakterlerinin doğru görüntülenmesi için UTF-8 çıktısını zorla
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Elevation Required: Please run as Administrator."
    Exit
}
# Etkin Windows hizmet işlemini algıla - sonlandırma.
# TiWorker/DISM'nin servis işlemi sırasında zorla sonlandırılması, bileşen deposunu bozar, bu da
# bu durumda onarım bölgesinin onarım yapması gerekirdi. Bunun yerine, onarım gerekliliğini tespit edip işlemi atlıyoruz.
$ServicingActive = $null -ne (Get-Process -Name "TiWorker", "DISM" -ErrorAction SilentlyContinue)
if ($ServicingActive) {
    Write-Host "[Pre-Flight] Windows servicing active (TiWorker/DISM running). Repair steps will be skipped." -ForegroundColor Yellow
}

# WMI/CIM geçişini yönetmeye yardımcı
function Get-SystemData {
    param([string]$Class)
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell 6/7, CIM kullanmalıdır.
        return Get-CimInstance -ClassName $Class -ErrorAction SilentlyContinue
    } else {
        # PowerShell 5.1 her ikisini de kullanabilir; ancak CIM tercih edilir.
        return Get-CimInstance -ClassName $Class -ErrorAction SilentlyContinue
    }
}
# Standartlaştırılmış Konsol Çıktısı
$script:StepRow = 0
$script:LastStepMessage = ""

function Write-StepUpdate {
    param([string]$Message, [switch]$Success, [switch]$Reprint, [string]$CustomInfo)
    $isDone = $Success -or ($CustomInfo -eq "[ATLANDI]")
    
    # Başlık iletisini saklayın
    if ($Message -match '^\[[\d.]+/') { $script:LastStepMessage = $Message }
    $printMsg = if ($Message) { $Message } else { $script:LastStepMessage }

    # Boyama Mantığı
    $writeMsg = {
        param([string]$msg, [bool]$done)
        if ($done -and $msg -match '^(\[[\d./]+\])(\s+.+)$') {
            Write-Host $Matches[1] -NoNewline -ForegroundColor DarkGray
            Write-Host $Matches[2] -NoNewline -ForegroundColor White
        } else {
            Write-Host $msg -NoNewline -ForegroundColor Cyan
        }
    }

    if ($Message -and -not $isDone) {
        # BİR ADIMA BAŞLAMA: Daha sonra geri dönebilmek için mevcut imleç satırını kaydet
        $script:StepRow = [Console]::CursorTop
        & $writeMsg $printMsg $false
        Write-Host "" # İmleci bir sonraki satıra taşıyın; böylece UYARILARIN yerleşebileceği bir alan olur.
    } 
    elseif ($isDone) {
        # BİR ADIMI TAMAMLAMA: Camgöbeği (Cyan) metnin üzerine yazmak için kaydedilen satıra geri dönün.
        $currentPos = [Console]::CursorTop
        [Console]::SetCursorPosition(0, $script:StepRow)
        
        # Orijinal Camgöbeği çizgiyi temizleyin
        Write-Host (" " * $script:Width) -NoNewline
        [Console]::SetCursorPosition(0, $script:StepRow)
        
        # Satırı "Tamamlandı" (Gri/Beyaz) stilinde yeniden yazdırın.
        & $writeMsg $printMsg $true

        # Özel Bilgi Ekle (Kaydedilen MB/GB)
        if ($CustomInfo) {
            if ($CustomInfo -eq "[ATLANDI]") {
                $tag = "[ATLANDI]"
                $currentCol = [Console]::CursorLeft
                $targetCol  = $script:Width - $tag.Length
                if ($targetCol -gt $currentCol) { Write-Host (" " * ($targetCol - $currentCol)) -NoNewline }
                Write-Host $tag -ForegroundColor Yellow
            } elseif ($CustomInfo.StartsWith("(Saved:")) {
                Write-Host " $CustomInfo" -NoNewline -ForegroundColor Red
            } elseif ($CustomInfo.StartsWith("(Est:")) {
                Write-Host " $CustomInfo" -NoNewline -ForegroundColor Magenta
            } else {
                Write-Host " $CustomInfo" -NoNewline -ForegroundColor Gray
            }
        }

        # Nihai Başarı Etiketi (konsol genişliğine göre sağa hizalı)
        if ($Success) {
            $tag = if ($script:DryRun) { "[EST]" } else { "[TAMAM]" }
            $currentCol = [Console]::CursorLeft
            $targetCol  = $script:Width - $tag.Length
            if ($targetCol -gt $currentCol) { Write-Host (" " * ($targetCol - $currentCol)) -NoNewline }
            Write-Host $tag -ForegroundColor $(if ($script:DryRun) { "Magenta" } else { "Green" })
        }

        # İmleci önceki konumuna (ortaya çıkan uyarıların altına) geri getirin.
        if ($currentPos -gt $script:StepRow) {
            [Console]::SetCursorPosition(0, $currentPos)
        #} else {
        #    Write-Host ""
        }
    }
}
# Hizmet Yönetimi Yardımcısı
function Start-ServiceSilent {
    param([string]$ServiceName)
    Start-Service $ServiceName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $Timer = 0
    while ((Get-Service $ServiceName).Status -ne 'Running' -and $Timer -lt 15) {
        Start-Sleep -Seconds 1
        $Timer++
    }
}
# Deneme amaçlı boyut tahmincisi (salt okunur; eksik yolları ve joker karakterleri işler)
function Get-PathSize {
    param([string]$Path)
    try {
        $sum = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [int64]$sum
    } catch { return 0 }
}
# Adım adım deneme raporu: Tahmini bir etiket yazdırır ve toplamı hesaplar.
function Write-DryEstimate {
    param([int64]$Bytes)
    if ($Bytes -gt 0) {
        $s = if ($Bytes -ge 1GB) { "{0:N2} GB" -f ($Bytes / 1GB) } else { "{0:N2} MB" -f ($Bytes / 1MB) }
        Write-StepUpdate -Success -CustomInfo "(Est: $s)"
    } else {
        Write-StepUpdate -Success -CustomInfo "Est: 0 MB"
    }
    if (-not $script:EstYieldBytes) { $script:EstYieldBytes = 0 }
    $script:EstYieldBytes = [int64]$script:EstYieldBytes + [int64]$Bytes
}
# Ortam Kurulumu
# Çıktı yardımcılarının görebilmesi için DryRun'ı betik kapsamında erişilebilir kılın
$script:DryRun = [bool]$DryRun
$Drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$StartSpace = $Drive.FreeSpace
$TotalSize = $Drive.Size
# Kümülatif verimi (bayt) başlat
if (-not $TotalYieldBytes) { $TotalYieldBytes = 0 }
$script:EstYieldBytes = 0
# TotalSize'ın geçerli olduğundan emin olun
$TotalSize = [double]$TotalSize
$script:RegionHistory = @()
if ($TotalSize -le 0) { throw "TotalSize is zero or undefined. Aborting." }

$StartUsagePct = [Math]::Round(((($TotalSize - $StartSpace) / $TotalSize) * 100), 2)
$LastRegionSpace = $Drive.FreeSpace # Adım adım raporlama için kayan referans noktası
$CS = Get-CimInstance Win32_ComputerSystem
$Vendor = $CS.Manufacturer
$IsVM = ($Vendor -match "QEMU|VMware|Virtual|Hyper-V")
# --- Özel tasarım mimari sergileme ünitesi ---
$Sys = Get-SystemData Win32_ComputerSystem
$Baseboard = Get-SystemData Win32_BaseBoard
# Kural: Üretici ve Model aynıysa (tipik olarak "O.E.M. Tarafından Doldurulacak" durumunda olduğu gibi),
# Anakart Üreticisi ve Ürünü bilgilerine başvurulur.
if ($Sys.Manufacturer -eq $Sys.Model) {
    $ArchitectureDisplay = "$($Baseboard.Manufacturer) $($Baseboard.Product)"
} else {
    $ArchitectureDisplay = "$($Sys.Manufacturer) $($Sys.Model)"
}
$OS = Get-SystemData Win32_OperatingSystem
$WinVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion
$CS = Get-SystemData Win32_LogicalDisk | Where-Object { $_.DeviceID -eq 'C:' }
# RMM/VSA'da hız sağlamak için standart ilerleme çubuklarını devre dışı bırakın.
$ProgressPreference = 'SilentlyContinue'

Clear-Host
$script:Width    = 90
$LineCol   = "DarkCyan"
$MainCol   = "DarkYellow"
$BorderCol = "Cyan"
$ArtCol    = "White"
$AccentCol = "Yellow"
$DimCol    = "DarkGray"
$InfoCol      = "Cyan"
function Write-HLine {
    param(
        [string]$Style = "dashed",
        [int]$Width    = $script:Width
    )
    if ($Style -eq "dashed") {
        $line = ("- " * [math]::Ceiling($Width / 2)).Substring(0, $Width)
    } else {
        $line = "━" * $Width
    }
    $colors = @(
        [ConsoleColor]$BorderCol,
        [ConsoleColor]$ArtCol,
        [ConsoleColor]$AccentCol,
        [ConsoleColor]$DimCol
    )
    $useConsole = $true
    try { $saved = [Console]::ForegroundColor } catch { $useConsole = $false }
    $i = 0
    foreach ($char in $line.ToCharArray()) {
        if ($char -eq ' ') {
            $fg = [ConsoleColor]$DimCol
        } else {
            $fg = $colors[$i % $colors.Count]
            $i++
        }
        if ($useConsole) {
            [Console]::ForegroundColor = $fg
            [Console]::Write($char)
        } else {
            Write-Host $char -NoNewline -ForegroundColor $fg
        }
    }
    if ($useConsole) {
        [Console]::ForegroundColor = $saved
        [Console]::WriteLine()
    } else {
        Write-Host ""
    }
}

# Başlık Sanatı ve Mantığı
$_pfx  = "█  "
$_art1 = "╔═╗ ╦╔═ ╔═╗ ╦ ╦ "
$_art2 = "╠═╣ ╠╩╗ ╠═╣ ╚╦╝ "
$_art3 = "╩ ╩ ╩ ╩ ╩ ╩  ╩  "
$_artW = [Math]::Max($_art1.Length, [Math]::Max($_art2.Length, $_art3.Length))
$_art1 = $_art1.PadRight($_artW); $_art2 = $_art2.PadRight($_artW); $_art3 = $_art3.PadRight($_artW)
$_fillW = $script:Width - $_pfx.Length - $_artW
$_title = "Akay Bilgisayar - Gelişmiş Bakım, Optimizasyon ve Onarım Aracı"

Write-Host $_pfx -ForegroundColor $LineCol -NoNewline; Write-Host $_art1 -ForegroundColor $ArtCol -NoNewline; Write-Host ("-" * $_fillW) -ForegroundColor $LineCol
Write-Host $_pfx -ForegroundColor $LineCol -NoNewline; Write-Host $_art2 -ForegroundColor $ArtCol -NoNewline; Write-Host "$_title" -ForegroundColor $MainCol
Write-Host $_pfx -ForegroundColor $LineCol -NoNewline; Write-Host $_art3 -ForegroundColor $ArtCol -NoNewline; Write-Host ("-" * $_fillW) -ForegroundColor $LineCol
# Sistem Bilgisi Başlığı
# Renk ayrımı yapılmış Sistem Bilgisi (Camgöbeği Etiketler, Sarı Veriler)
Write-Host "Cihaz Adı           : " -ForegroundColor $InfoCol -NoNewline; Write-Host "$($env:COMPUTERNAME)" -ForegroundColor Yellow
Write-Host "Sistem Mimarisi     : " -ForegroundColor $InfoCol -NoNewline; Write-Host "$ArchitectureDisplay" -ForegroundColor Yellow
Write-Host "İşletim Sistemi     : " -ForegroundColor $InfoCol -NoNewline; Write-Host "$($OS.Caption) ($WinVer)" -ForegroundColor Yellow
$StartUsedGB = [Math]::Round(($TotalSize - $StartSpace) / 1GB, 2)
$StartTotalGB = [Math]::Round($TotalSize / 1GB, 0)
$DiskColor = if ($StartUsagePct -ge 90) { "Red" } elseif ($StartUsagePct -ge 80) { "DarkYellow" } else { "Green" }
Write-Host "Disk Kullanımı      : " -ForegroundColor $InfoCol -NoNewline; Write-Host "${StartUsedGB}GB Used of ${StartTotalGB}GB ($StartUsagePct%)" -ForegroundColor $DiskColor
Write-HLine -Style dashed
if ($DryRun) {
    Write-Host "      Mode: DRY RUN - estimate only, no changes will be made" -ForegroundColor Magenta
}
if ($IsVM) {
    Write-Host "      Mode: Virtual Machine" -ForegroundColor Yellow 
}
#endregion

#region 1. Anlık Görüntü ve Depolama Temizliği
# ============================================================================
Write-StepUpdate "[01/08] Anlık Görüntüler,Bellek ve Ara Dizini temizleniyor..."
$RegionEst = [int64]0
# Dell SupportAssist Remediation anlık görüntü (snapshot) temizleme işlemi
# SupportAssist OS Recovery, sistem onarım anlık görüntülerini
# SARemediation\SystemRepair\{Snapshots,Backup} altında saklar; otomatik temizleme
# işlemi duraksadığında bu klasörler 20-80 GB boyuta ulaşabilir. Hizmeti durdurun,
# yalnızca anlık görüntü içeriğini (tüm dizin yapısını değil, böylece kurulum
# çalışmaya devam eder) temizleyin ve ardından hizmeti yeniden başlatın.
# Bu işlem, SupportAssist yeni bir anlık görüntü oluşturana kadar yerel
# OS-recovery anlık görüntülerini kaldırır.
if ($Vendor -like "*Dell*" -and -not $IsVM) {
    $SARoot = "C:\ProgramData\Dell\SARemediation\SystemRepair"
    if (Test-Path $SARoot) {
        if ($DryRun) {
            foreach ($Sub in @("Snapshots", "Backup")) { $RegionEst += Get-PathSize (Join-Path $SARoot $Sub) }
        } else {
            # Anlık görüntüleri (snapshot) açık tutan Dell SupportAssist / düzeltme hizmetlerini durdurun
            $SASvcs = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "SupportAssist*" -or $_.DisplayName -like "*SupportAssist*" }
            foreach ($SASvc in $SASvcs) {
                try { Stop-Service $SASvc.Name -Force -ErrorAction Stop -WarningAction SilentlyContinue } catch { }
            }
            foreach ($Sub in @("Snapshots", "Backup")) {
                $SAPath = Join-Path $SARoot $Sub
                if (Test-Path $SAPath) {
                    # Anlık görüntü dosyaları gizli/sistem/korumalı: öznitelikleri soyun, ardından içerikleri silin (klasörü saklayın)
                    Start-Process "cmd.exe" -ArgumentList "/c attrib -h -s -r `"$SAPath\*`" /S /D & del /s /f /q `"$SAPath\*`"" -WindowStyle Hidden -Wait
                }
            }
            # Durdurduğumuz hizmetleri yeniden başlatın
            foreach ($SASvc in $SASvcs) {
                Start-Service $SASvc.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            }
        }
    }
}
# Teslimat Optimizasyonu
$DOCache = "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
if (Test-Path $DOCache) {
    if ($DryRun) {
        $RegionEst += Get-PathSize $DOCache
    } else {
        Remove-Item "$DOCache\*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- Arama Dizinini Sıfırla ---
$SearchPath = "C:\ProgramData\Microsoft\Search\Data\Applications\Windows"
if ($DryRun) {
    if (Test-Path $SearchPath) { $RegionEst += Get-PathSize $SearchPath }
} else {
    $SvcName = "WSearch"
    $Svc = Get-Service $SvcName -ErrorAction SilentlyContinue
    if ($Svc -and $Svc.Status -ne 'Stopped') {
        Stop-Service $SvcName -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $RetryCount = 0
        while ((Get-Service $SvcName).Status -ne 'Stopped' -and $RetryCount -lt 10) {
            $dots = '.' * (($RetryCount % 3) + 1)
            $savedRow = [Console]::CursorTop
            [Console]::SetCursorPosition(0, $script:StepRow)
            Write-Host ("$($script:LastStepMessage) [Stopping WSearch$dots]").PadRight($script:Width) -NoNewline -ForegroundColor Cyan
            [Console]::SetCursorPosition(0, $savedRow)
            Start-Sleep -Seconds 2
            $RetryCount++
        }
        # Temiz adım satırını geri yükle ("[Stopping WSearch...]" son ekini kaldır)
        [Console]::SetCursorPosition(0, $script:StepRow)
        Write-Host $script:LastStepMessage.PadRight($script:Width) -NoNewline -ForegroundColor Cyan
        [Console]::SetCursorPosition(0, $script:StepRow + 1)
        if ((Get-Service $SvcName).Status -ne 'Stopped') {
            Get-Process "SearchIndexer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $SearchPath) { 
        # DÜZELTME: `cmd /c del` kullanımı, PowerShell'deki `ArgumentException` hatasını atlatır. 
        # Özyinelemeli silme işlemi sırasında dosyalar kaybolursa.
        Start-Process "cmd.exe" -ArgumentList "/c del /s /f /q `"$SearchPath\*`"" -WindowStyle Hidden -Wait
    }
    Start-Service $SvcName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}

# Windows Installer Önbelleği (90 günden eski, sahipsiz paketler)
$InstallerPath = "C:\Windows\Installer"
if (Test-Path $InstallerPath) {
    $InstalledProducts = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.LocalPackage } | Select-Object -ExpandProperty LocalPackage
    $OrphanPkgs = Get-ChildItem $InstallerPath -Filter "*.ms[ip]" -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notin $InstalledProducts -and $_.LastWriteTime -lt (Get-Date).AddDays(-90) }
    if ($DryRun) {
        $OrphanSum = ($OrphanPkgs | Measure-Object -Property Length -Sum).Sum
        if ($OrphanSum) { $RegionEst += [int64]$OrphanSum }
    } else {
        $OrphanPkgs | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# --- Windows.old temizliği (yaş sınırlamalı) ---
# Yalnızca özellik güncellemesi geri alma penceresi kapandıktan sonra kaldırın.
# Canlı bir geri alma yolu. DISM aracılığıyla gerçek zaman aralığını okuyun; 14 güne geri dönün.
if (Test-Path "C:\Windows.old") {
    $OldAgeDays = ((Get-Date) - (Get-Item "C:\Windows.old").LastWriteTime).TotalDays
    $UninstallWindow = 14
    try {
        $DismWin = & DISM.exe /Online /Get-OSUninstallWindow 2>$null
        $WinLine = $DismWin | Select-String -Pattern 'Uninstall Window\D+(\d+)'
        if ($WinLine) { $UninstallWindow = [int]$WinLine.Matches[0].Groups[1].Value }
    } catch { }

    if ($OldAgeDays -gt $UninstallWindow) {
        if ($DryRun) {
            $RegionEst += Get-PathSize "C:\Windows.old"
        } else {
            # Windows.old klasörünün silinebilmesi için önceki yükleme korumasını kaldırın.
            & DISM.exe /Online /Remove-OSUninstall /NoRestart *>&1 | Out-Null

            # cleanmgr tamamen atlanıyor: -WindowStyle Hidden'ı yok sayıyor (kontrolsüz bir işlem başlatıyor)
            # (alt işlem) etkileşimli oturumlarda kullanıcı arayüzünü gösterir ve sessizce başarısız olur.
            # SYSTEM/LiveConnect ortamı. rd /s /q komutu,daha büyük bir etkiye sahiptir.
            # fDerin dizin yapıları için Remove-Item -Recurse komutundan daha hızlıdır.
            $rdProc = Start-Process "cmd.exe" -ArgumentList "/c rd /s /q `"C:\Windows.old`"" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
            if ($rdProc) {
                $rdProc | Wait-Process -Timeout 1800 -ErrorAction SilentlyContinue
                if (-not $rdProc.HasExited) { $rdProc | Stop-Process -Force -ErrorAction SilentlyContinue }
            }

            # Yedek yöntem: rd komutu kilitli dosyalara denk gelirse, sahipliği al ve bir kez daha dene.
            if (Test-Path "C:\Windows.old") {
                & takeown /F "C:\Windows.old" /R /A /D Y 2>$null | Out-Null
                & icacls "C:\Windows.old" /grant Administrators:F /T /C /Q 2>$null | Out-Null
                Start-Process "cmd.exe" -ArgumentList "/c rd /s /q `"C:\Windows.old`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            }
        }
    }
}

# --- Bölge 1: sonuçlandırma ve biriktirme ---
if ($DryRun) {
    Write-DryEstimate $RegionEst
} else {
    $CurrentDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $CurrentSpace = [int64]$CurrentDrive.FreeSpace
    if ($null -eq $LastRegionSpace) { $LastRegionSpace = $CurrentSpace }
    $RegionSavedBytes = [int64]($CurrentSpace - $LastRegionSpace)
    if ($RegionSavedBytes -gt 0) {
        $SavedStr = if ($RegionSavedBytes -ge 1GB) { "{0:N2} GB" -f ($RegionSavedBytes / 1GB) } else { "{0:N2} MB" -f ($RegionSavedBytes / 1MB) }
        Write-StepUpdate -Success -CustomInfo "(Saved: $SavedStr)"
    } else {
        Write-StepUpdate -Success -CustomInfo "Saved: 0 MB"
        $RegionSavedBytes = 0
    }
    if (-not $script:TotalYieldBytes) { $script:TotalYieldBytes = 0 }
    $script:TotalYieldBytes = [int64]$script:TotalYieldBytes
    if ($RegionSavedBytes -gt 0) { $script:TotalYieldBytes += $RegionSavedBytes }
    if (-not $script:RegionHistory) { $script:RegionHistory = @() }
    $script:RegionHistory += [pscustomobject]@{ Region = 'Region1'; Bytes = $RegionSavedBytes; Time = (Get-Date) }
    $LastRegionSpace = $CurrentSpace
}
#endregion

#region 2. Derin Önbellek Temizleme
# ============================================================================
Write-StepUpdate "[02/08] Tarayıcı, Office ve GPU önbellekleri temizleniyor..."
$RegionEst = [int64]0
$GlobalCaches = @("C:\Windows\Temp\*", "C:\Windows\Prefetch\*", "C:\Windows\SystemTemp\*")
foreach ($P in $GlobalCaches) {
    if (Test-Path $P) {
        if ($DryRun) { $RegionEst += Get-PathSize $P }
        else { Remove-Item $P -Recurse -Force -ErrorAction SilentlyContinue | Out-Null }
    }
}
Get-ChildItem "C:\Users" -Directory | ForEach-Object {
    $UP = $_.FullName
    $ShaderPaths = @("$UP\AppData\Local\D3DSCache", "$UP\AppData\Local\AMD\DxCache", "$UP\AppData\Local\NVIDIA\GLCache")
    $OffPaths = @("$UP\AppData\Local\Microsoft\Office\16.0\OfficeFileCache", "$UP\AppData\Local\Microsoft\Office\OTele")
    $TargetDirs = @(
        "$UP\AppData\Local\Google\Chrome\User Data\*\Cache\*",
        "$UP\AppData\Local\Microsoft\Edge\User Data\*\Cache\*",
        "$UP\AppData\Local\Mozilla\Firefox\Profiles\*\cache2\*",
        "$UP\AppData\Local\BraveSoftware\Brave-Browser\User Data\*\Cache\*",
        "$UP\AppData\Local\Opera Software\Opera Stable\Cache\*",
        "$UP\AppData\Local\Temp\*"
    )
    $OutlookPath = "$UP\AppData\Local\Microsoft\Outlook"
    if ($DryRun) {
        foreach ($OP in $OffPaths) { $RegionEst += Get-PathSize $OP }
        if (Test-Path $OutlookPath) {
            $NstSum = (Get-ChildItem $OutlookPath -Filter "*.nst" -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($NstSum) { $RegionEst += [int64]$NstSum }
        }
        foreach ($SP in $ShaderPaths) { $RegionEst += Get-PathSize $SP }
        foreach ($T in $TargetDirs) { $RegionEst += Get-PathSize $T }
    } else {
        # Office ve Outlook (NST) Temizliği
        foreach ($OP in $OffPaths) { if (Test-Path $OP) { Remove-Item $OP -Recurse -Force -ErrorAction SilentlyContinue } }
        # Outlook NST (Arama Dizini) dosyaları
        if (Test-Path $OutlookPath) {
            Get-ChildItem $OutlookPath -Filter "*.nst" -Force | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        # GPU Gölgelendirici Önbellekleri
        foreach ($SP in $ShaderPaths) { if (Test-Path $SP) { Remove-Item "$SP\*" -Recurse -Force -ErrorAction SilentlyContinue } }
        foreach ($T in $TargetDirs) { 
            if (Test-Path $T) { 
                try {
                    Remove-Item $T -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable DeleteError
                    # VSA KARARLILIĞI: RMM kalp atışı ve disk nefes alıp verme olanak tanımak için kısa bir duraklama.
                    Start-Sleep -Milliseconds 50
                } catch {
                    continue
                }
            } 
        }
    }
}
# --- Bölge 2: kesinleştirme ---
if ($DryRun) {
    Write-DryEstimate $RegionEst
} else {
    $CurrentDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $RegionSaved = $CurrentDrive.FreeSpace - $LastRegionSpace
    if ($RegionSaved -gt 0) {
        $SavedStr = if ($RegionSaved -gt 1GB) { "$([math]::Round($RegionSaved / 1GB, 2)) GB" } else { "$([math]::Round($RegionSaved / 1MB, 2)) MB" }
        Write-StepUpdate -Success -CustomInfo "(Saved: $SavedStr)"
    } else {
        Write-StepUpdate -Success
    }
    if ($RegionSaved -gt 0) { $TotalYieldBytes += [int64]$RegionSaved }
    $LastRegionSpace = $CurrentDrive.FreeSpace
}
#endregion

#region 3. Geri Dönüşüm Kutusu'nu Boşaltma
# ============================================================================
Write-StepUpdate "[03/08] Geri Dönüşüm Kutusu boşaltılıyor (tüm kullanıcılar)..."
# Birim başına depolama alanındaki işlem, her kullanıcının Geri Dönüşüm Kutusu'nu temizler
# SYSTEM/LiveConnect altında gözden kaçan mevcut kimliğin çöp kutusunu boşaltır.
# Oturum açmış kullanıcının silinmiş dosyaları (disk uyarısı durumunda genellikle en büyük ve hızlı çözüm).
# Windows, klasörü otomatik olarak yeniden oluşturur.
if ($DryRun) {
    $RegionEst = Get-PathSize "C:\`$Recycle.Bin"
    Write-DryEstimate $RegionEst
} else {
    if (Test-Path "C:\`$Recycle.Bin") {
        Start-Process "cmd.exe" -ArgumentList "/c rd /s /q `"C:\`$Recycle.Bin`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
    }
    $CurrentDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $RegionSaved = $CurrentDrive.FreeSpace - $LastRegionSpace
    if ($RegionSaved -gt 0) {
        $SavedStr = if ($RegionSaved -gt 1GB) { "$([math]::Round($RegionSaved / 1GB, 2)) GB" } else { "$([math]::Round($RegionSaved / 1MB, 2)) MB" }
        Write-StepUpdate -Success -CustomInfo "(Saved: $SavedStr)"
    } else {
        Write-StepUpdate -Success
    }
    if ($RegionSaved -gt 0) { $TotalYieldBytes += [int64]$RegionSaved }
    $LastRegionSpace = $CurrentDrive.FreeSpace
}
#endregion

#region 4. Windows Update Veritabanını Sıfırlama
# ============================================================================
Write-StepUpdate "[04/08] Windows Update Veritabanı Sıfırlanıyor..."
# KONTROL: Yeniden başlatma bekleniyorsa, SoftwareDistribution büyük olasılıkla kilitlidir. 
# Betiğin takılmasını önlemek için atla.
$PendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

if ($PendingReboot) {
    Write-StepUpdate -CustomInfo "[ATLANDI]"
    Write-Host "        (Yeniden başlatma bekleniyor - SD kilitli)" -ForegroundColor DarkYellow
} elseif ($DryRun) {
    $RegionEst = Get-PathSize "C:\Windows\SoftwareDistribution"
    Write-DryEstimate $RegionEst
} else {
    # VSA bağlantı kesilmelerini önlemek için bu listeden "Bits" kaldırıldı.
    $Svcs = @("Wuauserv", "CryptSvc", "Msiserver")
    foreach ($S in $Svcs) { Stop-Service $S -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null }
    
    if (Test-Path "C:\Windows\SoftwareDistribution") { 
        Remove-Item "C:\Windows\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null 
    }
    
    foreach ($S in $Svcs) { 
        Set-Service $S -StartupType Automatic -ErrorAction SilentlyContinue | Out-Null
        Start-ServiceSilent $S
    }   

    # --- Bölgesel Tasarrufları Hesapla ---
    $CurrentDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $RegionSaved = $CurrentDrive.FreeSpace - $LastRegionSpace
    if ($RegionSaved -gt 0) {
        $SavedStr = if ($RegionSaved -gt 1GB) { "$([math]::Round($RegionSaved / 1GB, 2)) GB" } else { "$([math]::Round($RegionSaved / 1MB, 2)) MB" }
        Write-StepUpdate -Success -CustomInfo "(Saved: $SavedStr)"
    } else {
        Write-StepUpdate -Success
    }
    if ($RegionSaved -gt 0) { $TotalYieldBytes += [int64]$RegionSaved }
    $LastRegionSpace = $CurrentDrive.FreeSpace
}
#endregion

#region 5. Onarım ve Bütünlük
# ============================================================================
if ($IsVM) { [System.GC]::Collect() }
Write-Progress -Activity "Cleaning up" -Completed

# Onarım öncesi: kararlılık kontrolü – yalnızca uyarı verin; yalnızca 'PendingRename' (bekleyen yeniden adlandırma) durumu nedeniyle asla atlamayın.
# (PendingFileRenameOperations, Windows/kurulum programları tarafından düzenli olarak yeniden oluşturulur ve)
# (DISM veya SFC'yi engellemez). Deneme çalıştırması (dry run), etkin bakım ve yeniden başlatma gerektiren bekleyen işlemler ise bu işlemi atlar.
$SkipRepair = $false
$PendingRename = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
$HasPendingRename = $null -ne $PendingRename
if ($DryRun) {
    Write-Host "        [i] Deneme çalıştırması - DISM ve SFC onarım adımları atlandı (değişiklik yapılmadı)." -ForegroundColor Magenta
}
elseif ($PendingReboot) {
    Write-Host "        [!] Yeniden başlatma bekleniyor - DISM ve SFC onarım adımları atlanacak." -ForegroundColor DarkYellow
}
elseif ($ServicingActive) {
    Write-Host "        [!] Windows bakım (TiWorker/DISM çalışıyor)-DISM ve SFC onarım adımları atlanacak." -ForegroundColor DarkYellow
}
elseif ($HasPendingRename) {
    Write-Host "        [!] PendingFileRenameOperations bulundu - onarım adımları atlanıyor." -ForegroundColor DarkYellow
}
# TrustedInstaller'ın kullanılabilir olduğundan emin olun (DISM Hata 87 / SFC hatalarını önler)
if (-not $SkipRepair -and -not $DryRun) {
    $TI = Get-Service -Name "TrustedInstaller" -ErrorAction SilentlyContinue
    if ($TI.StartType -eq 'Disabled') { Set-Service -Name "TrustedInstaller" -StartupType Manual }
    if ($TI.Status -ne 'Running') { Start-Service -Name "TrustedInstaller" -ErrorAction SilentlyContinue }
}
if (-not $SkipRepair) {
# Yardımcı: Konsol satırlarını $startRow'dan mevcut satıra kadar temizle, ardından bir adım sonucunu yeniden yazdır.
    function Clear-AndReprintStep {
        param([int]$StartRow, [string]$Message, [switch]$Success, [string]$CustomInfo)
        try {
            $endRow = [Console]::CursorTop
            $width  = $script:Width
            for ($r = $StartRow; $r -le $endRow; $r++) {
                [Console]::SetCursorPosition(0, $r)
                [Console]::Write(' ' * $width)
            }
            [Console]::SetCursorPosition(0, $StartRow)
        } catch {}
        if ($Success) { Write-StepUpdate $Message -Success }
        elseif ($CustomInfo -eq "[ATLANDI]") { Write-StepUpdate $Message -CustomInfo "[ATLANDI]" }
        elseif ($CustomInfo -match '^\[FAILED') {
            # Adım etiketini gri, açıklamayı beyaz, hatayı kırmızı renkte yazdırın.
            if ($Message -match '^(\[[\d./]+\])(\s+.+)$') {
                Write-Host $Matches[1] -NoNewline -ForegroundColor DarkGray
                Write-Host $Matches[2] -NoNewline -ForegroundColor White
            } else { Write-Host $Message -NoNewline -ForegroundColor White }
            $tag = $CustomInfo
            $currentCol = [Console]::CursorLeft
            $targetCol  = $script:Width - $tag.Length
            if ($targetCol -gt $currentCol) { Write-Host (" " * ($targetCol - $currentCol)) -NoNewline }
            Write-Host $tag -ForegroundColor Red
        }
        elseif ($CustomInfo -eq "[WARNING]") {
            # Adım etiketini gri, açıklamayı beyaz, uyarıyı sarı renkte yazdırın.
            if ($Message -match '^(\[[\d./]+\])(\s+.+)$') {
                Write-Host $Matches[1] -NoNewline -ForegroundColor DarkGray
                Write-Host $Matches[2] -NoNewline -ForegroundColor White
            } else { Write-Host $Message -NoNewline -ForegroundColor White }
            $tag = $CustomInfo
            $currentCol = [Console]::CursorLeft
            $targetCol  = $script:Width - $tag.Length
            if ($targetCol -gt $currentCol) { Write-Host (" " * ($targetCol - $currentCol)) -NoNewline }
            Write-Host $tag -ForegroundColor Yellow
        }
        elseif ($CustomInfo) { Write-StepUpdate $Message -CustomInfo $CustomInfo }
    }
# Yardımcı: Ham .NET Console API'sini kullanarak arabellekteki konsol tuş vuruşlarını temizler (PSReadLine'ı atlar).
    function Clear-InputBuffer { try { while ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null } } catch {} }
    # cmd.exe'yi ve geride bıraktığı tüm DISM/TiWorker alt süreçlerini sonlandırır.
    function Stop-DismTree {
        Get-Process -Name "DISM","TiWorker" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # DISM işlemi sonlandıktan sonra TiWorker'ın kapanması için 5 saniye bekleyin,(handle) serbest bırakmak sonlandırın.
    function Stop-TiWorker {
        $tw = Get-Process -Name "TiWorker" -ErrorAction SilentlyContinue
        if ($tw) {
            $tw | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
            Get-Process -Name "TiWorker" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
        }
    }
# --- ADIM 5: RestoreHealth ---
            Clear-InputBuffer
            $S72 = "[05/08] DISM Sağlığı Geri Yükle..."
            Write-StepUpdate $S72 -CustomInfo "[ESC İLE ÇIKIŞ]"
            $Row72 = try { [Console]::CursorTop - 1 } catch { -1 }

            if ($DryRun -or $PendingReboot -or $HasPendingRename -or $ServicingActive) {
                Clear-AndReprintStep -StartRow $Row72 -Message $S72 -CustomInfo "[ATLANDI]"
            }
            else {
                $DismSpin = [char[]]@('|','/','-','\')
                $DismTmp1 = [System.IO.Path]::GetTempFileName()

                # Doğrudan .NET Process'ini kullanın; Start-Process -PassThru, $null ExitCode döndürür.
                # -RedirectStandardOutput ile birlikte kullanıldığında; dosya yönlendirmesi için komutu cmd.exe içinde çalıştırın.
                $psi1 = New-Object System.Diagnostics.ProcessStartInfo
                $psi1.FileName               = "cmd.exe"
                $psi1.Arguments              = "/c dism.exe /Online /Cleanup-Image /RestoreHealth /NoRestart > `"$DismTmp1`" 2>&1"
                $psi1.UseShellExecute        = $false
                $psi1.CreateNoWindow         = $true
                $psi1.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $Proc1 = [System.Diagnostics.Process]::Start($psi1)

                $Skipped1 = $false
                $DismSpinIdx1 = 0
                $DismTimer1 = [Diagnostics.Stopwatch]::StartNew()

                while (-not $Proc1.HasExited) {
                    try {
                        if ([Console]::KeyAvailable) {
                            $Key = [Console]::ReadKey($true)
                            if ($Key.Key -eq [ConsoleKey]::Escape) {
                                try { $Proc1.Kill() } catch {}
                                Stop-DismTree
                                $Skipped1 = $true
                                break
                            }
                        }
                    } catch {}
                    try {
                        [Console]::SetCursorPosition(0, $Row72)
                        $EscHint = "[ESC İLE ÇIKIŞ]"
                        $Width = $script:Width
                        $Left = "$S72 $($DismSpin[$DismSpinIdx1 % 4]) $($DismTimer1.Elapsed.ToString('mm\:ss'))"
                        $Spaces = [Math]::Max(1, $Width - $Left.Length - $EscHint.Length)
                        [Console]::ForegroundColor = [ConsoleColor]::Cyan
                        [Console]::Write($Left + (' ' * $Spaces))
                        [Console]::ForegroundColor = [ConsoleColor]::DarkGray
                        [Console]::Write($EscHint)
                        [Console]::ResetColor()
                    } catch {}
                    $DismSpinIdx1++
                    Start-Sleep -Milliseconds 250
                }
                $DismTimer1.Stop()

                if (-not $Skipped1) {
                    $Proc1.WaitForExit()
                    Stop-TiWorker
                }
                $ExitCode1 = $Proc1.ExitCode
                try { $Proc1.Dispose() } catch {}
                Remove-Item $DismTmp1 -Force -ErrorAction SilentlyContinue

                if ($Skipped1) {
                    Clear-AndReprintStep -StartRow $Row72 -Message $S72 -CustomInfo "[ATLANDI]"
                }
                elseif ($ExitCode1 -in @(0, 3010)) {
                    Clear-AndReprintStep -StartRow $Row72 -Message $S72 -Success
                }
                else {
                    Clear-AndReprintStep -StartRow $Row72 -Message $S72 -CustomInfo "[FAILED:0x$($ExitCode1.ToString('X'))]"
                }
            }

# --- ADIM 6: DISM Bileşen Temizliği ---
            $S73 = "[06/08] DISM Bileşen Temizleme..."
            Write-StepUpdate $S73 -CustomInfo "[ESC İLE ÇIKIŞ]"
            $Row73 = try { [Console]::CursorTop - 1 } catch { -1 }

            if ($DryRun -or $PendingReboot -or $HasPendingRename -or $ServicingActive) {
                Clear-AndReprintStep -StartRow $Row73 -Message $S73 -CustomInfo "[ATLANDI]"
            }
            else {
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                Stop-Service bits -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                Stop-Service TrustedInstaller -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                Start-Service TrustedInstaller -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                Start-Sleep -Seconds 3

                Clear-InputBuffer

                $DismTmp2 = [System.IO.Path]::GetTempFileName()

                $psi2 = New-Object System.Diagnostics.ProcessStartInfo
                $psi2.FileName               = "cmd.exe"
                $psi2.Arguments              = "/c dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart > `"$DismTmp2`" 2>&1"
                $psi2.UseShellExecute        = $false
                $psi2.CreateNoWindow         = $true
                $psi2.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $Proc2 = [System.Diagnostics.Process]::Start($psi2)

                $Skipped2 = $false
                $DismSpinIdx2 = 0
                $DismTimer2 = [Diagnostics.Stopwatch]::StartNew()

                while (-not $Proc2.HasExited) {
                    try {
                        if ([Console]::KeyAvailable) {
                            $Key = [Console]::ReadKey($true)
                            if ($Key.Key -eq [ConsoleKey]::Escape) {
                                try { $Proc2.Kill() } catch {}
                                Stop-DismTree
                                $Skipped2 = $true
                                break
                            }
                        }
                    } catch {}
                    try {
                        [Console]::SetCursorPosition(0, $Row73)
                        $EscHint = "[ESC to skip]"
                        $Width = $script:Width
                        $Left = "$S73 $($DismSpin[$DismSpinIdx2 % 4]) $($DismTimer2.Elapsed.ToString('mm\:ss'))"
                        $Spaces = [Math]::Max(1, $Width - $Left.Length - $EscHint.Length)
                        [Console]::ForegroundColor = [ConsoleColor]::Cyan
                        [Console]::Write($Left + (' ' * $Spaces))
                        [Console]::ForegroundColor = [ConsoleColor]::DarkGray
                        [Console]::Write($EscHint)
                        [Console]::ResetColor()
                    } catch {}
                    $DismSpinIdx2++
                    Start-Sleep -Milliseconds 250
                }
                $DismTimer2.Stop()

                if (-not $Skipped2) {
                    $Proc2.WaitForExit()
                    Stop-TiWorker
                }
                $ExitCode2 = $Proc2.ExitCode
                try { $Proc2.Dispose() } catch {}
                Remove-Item $DismTmp2 -Force -ErrorAction SilentlyContinue

                Start-Service bits -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                Start-Service wuauserv -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

                if ($Skipped2) {
                    Clear-AndReprintStep -StartRow $Row73 -Message $S73 -CustomInfo "[ATLANDI]"
                }
                elseif ($ExitCode2 -in @(0, 3010)) {
                    Clear-AndReprintStep -StartRow $Row73 -Message $S73 -Success
                }
                else {
                    Clear-AndReprintStep -StartRow $Row73 -Message $S73 -CustomInfo "[FAILED:0x$($ExitCode2.ToString('X'))]"
                }
            }

# --- ADIM 7: SFC /scannow ---
            $S74 = "[07/08] SFC /scannow..."
            Write-StepUpdate $S74 -CustomInfo "[ESC İLE ÇIKIŞ]"
            $Row74 = try { [Console]::CursorTop - 1 } catch { -1 }

            if ($DryRun -or $PendingReboot -or $HasPendingRename -or $ServicingActive) {
                Clear-AndReprintStep -StartRow $Row74 -Message $S74 -CustomInfo "[ATLANDI]"
            }
            else {
                Clear-InputBuffer
                $SfcTmp = [System.IO.Path]::GetTempFileName()

                # sfc.exe Unicode yazar; güvenilir bir çıkış kodu elde etmek için cmd yönlendirmesiyle yakalayın.
                $psi3 = New-Object System.Diagnostics.ProcessStartInfo
                $psi3.FileName               = "cmd.exe"
                $psi3.Arguments              = "/c sfc.exe /scannow > `"$SfcTmp`" 2>&1"
                $psi3.UseShellExecute        = $false
                $psi3.CreateNoWindow         = $true
                $psi3.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $Proc3 = [System.Diagnostics.Process]::Start($psi3)

                $Skipped3 = $false
                $SfcSpinIdx = 0
                $SfcTimer = [Diagnostics.Stopwatch]::StartNew()

                while (-not $Proc3.HasExited) {
                    try {
                        if ([Console]::KeyAvailable) {
                            $Key = [Console]::ReadKey($true)
                            if ($Key.Key -eq [ConsoleKey]::Escape) {
                                try { $Proc3.Kill() } catch {}
                                Get-Process -Name "sfc" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                                $Skipped3 = $true
                                break
                            }
                        }
                    } catch {}
                    try {
                        [Console]::SetCursorPosition(0, $Row74)
                        $EscHint = "[ESC to skip]"
                        $Width = $script:Width
                        $Left = "$S74 $($DismSpin[$SfcSpinIdx % 4]) $($SfcTimer.Elapsed.ToString('mm\:ss'))"
                        $Spaces = [Math]::Max(1, $Width - $Left.Length - $EscHint.Length)
                        [Console]::ForegroundColor = [ConsoleColor]::Cyan
                        [Console]::Write($Left + (' ' * $Spaces))
                        [Console]::ForegroundColor = [ConsoleColor]::DarkGray
                        [Console]::Write($EscHint)
                        [Console]::ResetColor()
                    } catch {}
                    $SfcSpinIdx++
                    Start-Sleep -Milliseconds 250
                }
                $SfcTimer.Stop()

                if (-not $Skipped3) {
                    $Proc3.WaitForExit()
                }
                $ExitCode3 = $Proc3.ExitCode
                try { $Proc3.Dispose() } catch {}
                Remove-Item $SfcTmp -Force -ErrorAction SilentlyContinue

                if ($Skipped3) {
                    Clear-AndReprintStep -StartRow $Row74 -Message $S74 -CustomInfo "[ATLANDI]"
                }
                elseif ($ExitCode3 -in @(0, 1)) {
                    Clear-AndReprintStep -StartRow $Row74 -Message $S74 -Success
                }
                elseif ($ExitCode3 -eq 2) {
                    Clear-AndReprintStep -StartRow $Row74 -Message $S74 -CustomInfo "[WARNING]"
                }
                else {
                    Clear-AndReprintStep -StartRow $Row74 -Message $S74 -CustomInfo "[FAILED:0x$($ExitCode3.ToString('X'))]"
                }
            }
}
if (-not $DryRun) {
    $CurrentSpace = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
    $RegionSaved = $CurrentSpace - $LastRegionSpace
    if ($RegionSaved -gt 0) { $TotalYieldBytes += [int64]$RegionSaved }
    $LastRegionSpace = $CurrentSpace
}
#endregion

#region 6. Nihai Optimizasyon
# ============================================================================
Write-StepUpdate "[08/08] Ağ, Hazırda Bekletme ve SSD TRIM işlemleri tamamlanıyor..."
if ($DryRun) {
    # powercfg /h off komutu hiberfil.sys dosyasının kapladığı alanı geri kazandırır; dosyanın mevcut boyutunu tahmin edin.
    $HibBytes = [int64]0
    if (Test-Path "C:\hiberfil.sys") {
        try { $HibBytes = [int64](Get-Item "C:\hiberfil.sys" -Force -ErrorAction SilentlyContinue).Length } catch { $HibBytes = 0 }
    }
    Write-DryEstimate $HibBytes
} else {
    & ipconfig.exe /flushdns | Out-Null
    & powercfg.exe /h off | Out-Null
    try { Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue | Out-Null } catch { }
    Write-StepUpdate -Success
}

# --- NİHAİ ÖZET ---
# Disk bilgilerinin ve toplam boyutun geçerli olduğundan emin olun.
$FinalDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$TotalSize = [double]$TotalSize
if ($TotalSize -le 0) { throw "TotalSize is zero or undefined. Aborting final summary." }

if (-not $script:TotalYieldBytes) { $script:TotalYieldBytes = 0 }
$script:TotalYieldBytes = [int64]$script:TotalYieldBytes
if (-not $script:EstYieldBytes) { $script:EstYieldBytes = 0 }
$script:EstYieldBytes = [int64]$script:EstYieldBytes

$FinalFree = [int64]$FinalDrive.FreeSpace
$FinalUsedPct = [Math]::Round(((($TotalSize - $FinalFree) / $TotalSize) * 100), 2)
$FinalUsedGB = [Math]::Round(($TotalSize - $FinalFree) / 1GB, 2)
$FinalTotalGB = [Math]::Round($TotalSize / 1GB, 0)
$FinalColor = if ($FinalUsedPct -ge 90) { "Red" } elseif ($FinalUsedPct -ge 80) { "DarkYellow" } else { "Green" }

Write-HLine -Style dashed
if ($DryRun) {
    # Projected free space if the estimated reclaim were applied
    $ProjFree = [int64]($FinalFree + $script:EstYieldBytes)
    $ProjUsedPct = [Math]::Round(((($TotalSize - $ProjFree) / $TotalSize) * 100), 2)
    $ProjColor = if ($ProjUsedPct -ge 90) { "Red" } elseif ($ProjUsedPct -ge 80) { "DarkYellow" } else { "Green" }
    if ($script:EstYieldBytes -ge 1GB) { $EstStr = "{0:N2} GB" -f ($script:EstYieldBytes / 1GB) } else { $EstStr = "{0:N2} MB" -f ($script:EstYieldBytes / 1MB) }

    Write-Host "Current Disk Usage  : " -NoNewline -ForegroundColor $InfoCol
    Write-Host "$FinalUsedGB GB used of $FinalTotalGB GB ($FinalUsedPct%)" -ForegroundColor $FinalColor
    Write-Host "Est. Recoverable    : " -NoNewline -ForegroundColor $InfoCol
    Write-Host "$EstStr" -ForegroundColor Magenta
    Write-Host "Projected After Run : " -NoNewline -ForegroundColor $InfoCol
    Write-Host "$([Math]::Round(($TotalSize - $ProjFree) / 1GB, 2)) GB used of $FinalTotalGB GB ($ProjUsedPct%)" -ForegroundColor $ProjColor
} else {
    if ($script:TotalYieldBytes -ge 1GB) { $TotalStr = "{0:N2} GB" -f ($script:TotalYieldBytes / 1GB) } else { $TotalStr = "{0:N2} MB" -f ($script:TotalYieldBytes / 1MB) }
    Write-Host "Nihai Disk Kullanımı    : " -NoNewline -ForegroundColor $InfoCol
    Write-Host "$FinalUsedGB GB used of $FinalTotalGB GB ($FinalUsedPct%)" -ForegroundColor $FinalColor
    Write-Host "Yer Kazanıldı           : " -NoNewline -ForegroundColor $InfoCol
    Write-Host "$TotalStr" -ForegroundColor Yellow
}
# Footer
$_sfx   = "█"
$_ffillW = $script:Width - $_artW - 1 - $_sfx.Length
$_footer = if ($DryRun) { "  DRY RUN COMPLETE" } else { "  BAKIM TAMAMLANDI" }
$_fpad   = " " * [Math]::Max(0, ($_ffillW - $_footer.Length - $_fver.Length))

Write-Host ("-" * $_ffillW) -ForegroundColor $LineCol -NoNewline; Write-Host " $_art1" -ForegroundColor $ArtCol -NoNewline; Write-Host $_sfx -ForegroundColor $LineCol
Write-Host "$_footer$_fpad$_fver" -ForegroundColor $MainCol -NoNewline; Write-Host " $_art2" -ForegroundColor $ArtCol -NoNewline; Write-Host $_sfx -ForegroundColor $LineCol
Write-Host ("-" * $_ffillW) -ForegroundColor $LineCol -NoNewline; Write-Host " $_art3" -ForegroundColor $ArtCol -NoNewline; Write-Host $_sfx -ForegroundColor $LineCol
#endregion
