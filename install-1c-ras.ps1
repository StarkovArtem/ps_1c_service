# Скрипт установки RAS сервера 1С на Windows
# Автоматически запрашивает повышение прав

param(
    [string]$RASPort = "1545",
    [string]$InstallPath = "C:\Program Files\1C\RAS",
    [string]$LogPath = "C:\ProgramData\1C\ras\logs",
    [string]$ServiceName = "1C_RAS_Server",
    [string]$ClusterInstance = "localhost"
)

# Функции для вывода
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Cyan
}

# Функция проверки и запроса повышения прав
function Request-AdminElevation {
    # Проверяем, запущен ли скрипт от администратора
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Для установки RAS сервера требуются права Администратора"
        Write-Info "Запрашиваю повышение прав..."
        
        # Получаем путь к текущему скрипту
        $scriptPath = $MyInvocation.MyCommand.Path
        
        # Создаем новый процесс PowerShell с правами администратора
        $startProcess = Start-Process -FilePath "powershell.exe" `
                                     -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`" -RASPort $RASPort -InstallPath `"$InstallPath`" -LogPath `"$LogPath`" -ServiceName `"$ServiceName`" -ClusterInstance `"$ClusterInstance`"" `
                                     -Verb RunAs `
                                     -Wait `
                                     -PassThru
        
        if ($startProcess.ExitCode -eq 0) {
            Write-Success "Установка завершена успешно!"
        } else {
            Write-Error "Установка завершилась с ошибкой. Код выхода: $($startProcess.ExitCode)"
        }
        
        exit
    } else {
        Write-Success "Скрипт запущен с правами Администратора"
    }
}

# Проверка установки платформы 1С
function Test-1CInstalled {
    Write-Info "Проверка установки платформы 1С..."
    
    $registryPaths = @(
        "HKLM:\SOFTWARE\1C\1Cv8",
        "HKLM:\SOFTWARE\WOW6432Node\1C\1Cv8",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.DisplayName -like "*1C*Enterprise*" -or $item.Publisher -like "*1C*") {
                    Write-Success "Найдена установленная платформу 1С: $($item.DisplayName)"
                    return $true
                }
            }
        }
    }
    
    # Дополнительная проверка в Program Files
    $possiblePaths = @(
        "${env:ProgramFiles}\1cv8",
        "${env:ProgramFiles(x86)}\1cv8"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Success "Найдена директория 1С: $path"
            return $true
        }
    }
    
    return $false
}

# Поиск пути к платформе 1С
function Get-1CPlatformPath {
    Write-Info "Поиск исполняемых файлов 1С..."
    
    $possiblePaths = @(
        "${env:ProgramFiles}\1cv8\*\bin",
        "${env:ProgramFiles(x86)}\1cv8\*\bin"
    )
    
    foreach ($pathPattern in $possiblePaths) {
        $paths = Get-ChildItem -Path $pathPattern -ErrorAction SilentlyContinue
        foreach ($path in $paths) {
            $rasPath = "$path\ras.exe"
            if (Test-Path $rasPath) {
                Write-Success "Найден ras.exe: $rasPath"
                return $path.FullName
            }
        }
    }
    
    return $null
}

# Создание директорий
function Create-Directories {
    param(
        [string]$InstallPath,
        [string]$LogPath
    )
    
    Write-Info "Создание рабочих директорий..."
    
    # Создание основной директории установки
    if (!(Test-Path $InstallPath)) {
        try {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
            Write-Success "Создана директория: $InstallPath"
        } catch {
            throw "Не удалось создать директорию $InstallPath : $($_.Exception.Message)"
        }
    } else {
        Write-Info "Директория уже существует: $InstallPath"
    }
    
    # Создание директории логов
    if (!(Test-Path $LogPath)) {
        try {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
            Write-Success "Создана директория логов: $LogPath"
        } catch {
            throw "Не удалось создать директорию логов $LogPath : $($_.Exception.Message)"
        }
    } else {
        Write-Info "Директория логов уже существует: $LogPath"
    }
}

# Создание службы RAS - ИСПРАВЛЕННАЯ ВЕРСИЯ
function Install-RASService {
    param(
        [string]$PlatformPath,
        [string]$Port,
        [string]$ServiceName,
        [string]$ClusterInstance
    )
    
    $rasExePath = "$PlatformPath\ras.exe"
    
    Write-Info "Установка службы RAS..."
    Write-Info "Исполняемый файл: $rasExePath"
    
    # Удаление существующей службы (если есть)
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Warning "Служба $ServiceName уже существует. Останавливаю и удаляю..."
        try {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        } catch {
            Write-Warning "Не удалось остановить службу: $($_.Exception.Message)"
        }
        
        # Удаляем службу через sc.exe
        Write-Info "Удаление службы $ServiceName..."
        $deleteResult = sc.exe delete $ServiceName 2>&1
        Start-Sleep -Seconds 3
        Write-Info "Результат удаления службы: $deleteResult"
    }
    
    # СПОСОБ 1: Используем New-Service (более надежный в PowerShell)
    Write-Info "Создание службы через New-Service..."
    
    try {
        # Формируем команду для RAS
        $arguments = "cluster --service --port=$Port $ClusterInstance"
        
        Write-Info "Параметры запуска: $arguments"
        
        # Создаем службу через New-Service
        $service = New-Service -Name $ServiceName `
                              -BinaryPathName "`"$rasExePath`" $arguments" `
                              -DisplayName "1C:Enterprise RAS Server" `
                              -Description "1C:Enterprise 8.3 Remote Administration Server. Port: $Port" `
                              -StartupType "Automatic" `
                              -ErrorAction Stop
        
        Write-Success "Служба $ServiceName успешно создана через New-Service"
        return $true
        
    } catch {
        Write-Warning "Не удалось создать службу через New-Service: $($_.Exception.Message)"
        Write-Info "Пробуем альтернативный способ через sc.exe..."
        
        # СПОСОБ 2: Альтернативный способ через sc.exe
        try {
            # Правильный формат для sc.exe: одна пара кавычек вокруг всего пути
            $binPath = "`"$rasExePath`" cluster --service --port=$Port $ClusterInstance"
            
            Write-Info "Создание службы через sc.exe..."
            Write-Info "Команда: sc create $ServiceName binPath= $binPath start= auto"
            
            # Создаем службу
            $createResult = sc.exe create $ServiceName binPath= $binPath start= auto 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Служба успешно создана через sc.exe"
                
                # Настраиваем дополнительные параметры
                sc.exe config $ServiceName DisplayName= "1C:Enterprise RAS Server" 2>&1 | Out-Null
                sc.exe description $ServiceName "1C:Enterprise 8.3 Remote Administration Server. Port: $Port" 2>&1 | Out-Null
                
                return $true
            } else {
                Write-Error "Ошибка создания службы. Код: $LASTEXITCODE"
                Write-Error "Результат: $createResult"
                return $false
            }
            
        } catch {
            Write-Error "Не удалось создать службу через sc.exe: $($_.Exception.Message)"
            return $false
        }
    }
}

# Настройка брандмауэра
function Configure-Firewall {
    param([string]$Port, [string]$ServiceName)
    
    Write-Info "Настройка правил брандмауэра для порта $Port..."
    
    $ruleNameTCP = "1C RAS Server TCP-$Port"
    
    try {
        # Удаляем существующие правила
        Remove-NetFirewallRule -DisplayName $ruleNameTCP -ErrorAction SilentlyContinue
        
        # Создаем правило для TCP
        New-NetFirewallRule -DisplayName $ruleNameTCP `
                           -Direction Inbound `
                           -Protocol TCP `
                           -LocalPort $Port `
                           -Action Allow `
                           -Profile Domain,Private,Public `
                           -Enabled True `
                           -ErrorAction Stop
        
        Write-Success "Создано правило брандмауэра для TCP/$Port"
        
    } catch {
        Write-Warning "Не удалось настроить брандмауэр: $($_.Exception.Message)"
        Write-Warning "Возможно, потребуется настроить брандмауэр вручную"
    }
}

# Проверка работы службы
function Test-RASService {
    param([string]$ServiceName, [string]$Port)
    
    Write-Info "Проверка работы службы..."
    Start-Sleep -Seconds 5
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        $statusColor = if ($service.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "Статус службы: $($service.Status)" -ForegroundColor $statusColor
        
        if ($service.Status -ne "Running") {
            Write-Warning "Служба не запущена. Пытаюсь запустить..."
            
            try {
                Start-Service -Name $ServiceName -ErrorAction Stop
                Start-Sleep -Seconds 3
                $service = Get-Service -Name $ServiceName
                Write-Host "Новый статус службы: $($service.Status)" -ForegroundColor $(if($service.Status -eq "Running"){"Green"}else{"Red"})
            } catch {
                Write-Warning "Не удалось запустить службу автоматически: $($_.Exception.Message)"
            }
            
            if ($service.Status -ne "Running") {
                Write-Error "Не удалось запустить службу."
                return $false
            }
        }
        
        # Проверка сетевого подключения
        Write-Info "Проверка сетевого порта $Port..."
        $tcpTest = Test-NetConnection -ComputerName localhost -Port $Port -InformationLevel Quiet
        
        if ($tcpTest) {
            Write-Success "Порт ${Port}: Открыт и принимает подключения" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Порт ${Port}: Закрыт или не отвечает" -ForegroundColor Yellow
            
            # Дополнительная диагностика
            Write-Info "Диагностика проблемы..."
            
            # Проверяем, слушает ли процесс порт
            $listening = netstat -an | Select-String ":$Port\s"
            if ($listening) {
                Write-Success "Порт $Port слушается системой"
            } else {
                Write-Warning "Порт $Port не слушается"
            }
            
            # Проверяем процесс RAS
            $rasProcess = Get-Process -Name "ras" -ErrorAction SilentlyContinue
            if ($rasProcess) {
                Write-Success "Процесс RAS запущен (PID: $($rasProcess.Id))"
            } else {
                Write-Warning "Процесс RAS не найден"
            }
            
            return $false
        }
        
    } catch {
        Write-Error "Ошибка при проверке службы: $($_.Exception.Message)"
        return $false
    }
}

# Проверка логов службы
function Check-ServiceLogs {
    param([string]$ServiceName)
    
    Write-Info "Проверка логов службы..."
    
    try {
        # Получаем события службы за последние 10 минут
        $events = Get-WinEvent -LogName System -MaxEvents 20 | Where-Object {
            $_.TimeCreated -gt (Get-Date).AddMinutes(-10) -and 
            ($_.Message -like "*$ServiceName*" -or $_.Message -like "*ras*" -or $_.Message -like "*1C*")
        }
        
        if ($events) {
            Write-Warning "Найдены события в системном логе:"
            foreach ($event in $events) {
                $level = switch ($event.Level) {
                    "Error" { "ERROR" }
                    "Warning" { "WARNING" } 
                    "Information" { "INFO" }
                    default { "OTHER" }
                }
                Write-Host "  $($event.TimeCreated) [$level]: $($event.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Info "В системном логе нет событий, связанных со службой"
        }
    } catch {
        Write-Warning "Не удалось прочитать системные логи: $($_.Exception.Message)"
    }
}

# Основная логика установки
function Start-Installation {
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "УСТАНОВКА RAS СЕРВЕРА 1С:ПРЕДПРИЯТИЕ" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "Порт: $RASPort" -ForegroundColor Yellow
    Write-Host "Директория: $InstallPath" -ForegroundColor Yellow
    Write-Host "Логи: $LogPath" -ForegroundColor Yellow
    Write-Host "Служба: $ServiceName" -ForegroundColor Yellow
    Write-Host "Кластер: $ClusterInstance" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "`n"
    
    # Запрос подтверждения
    $confirm = Read-Host "Продолжить установку? (Y/N)"
    if ($confirm -notmatch '^[YyДд]') {
        Write-Info "Установка отменена пользователем"
        exit 0
    }
    
    try {
        # Проверка платформы 1С
        if (-not (Test-1CInstalled)) {
            throw "Платформа 1С:Предприятие не найдена. Установите сначала платформу 1С."
        }
        
        # Поиск пути к платформе
        $platformPath = Get-1CPlatformPath
        if (-not $platformPath) {
            throw "Не удалось найти ras.exe. Проверьте установку платформы 1С."
        }
        
        # Создание директорий
        Create-Directories -InstallPath $InstallPath -LogPath $LogPath
        
        # Установка службы (убрал лишние параметры)
        $serviceCreated = Install-RASService -PlatformPath $platformPath `
                                           -Port $RASPort `
                                           -ServiceName $ServiceName `
                                           -ClusterInstance $ClusterInstance
        
        if (-not $serviceCreated) {
            throw "Не удалось создать службу"
        }
        
        # Настройка брандмауэра
        Configure-Firewall -Port $RASPort -ServiceName $ServiceName
        
        # Запуск службы
        Write-Info "Запуск службы $ServiceName..."
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Success "Служба успешно запущена"
        } catch {
            Write-Warning "Не удалось запустить службу автоматически: $($_.Exception.Message)"
            Write-Info "Проверяем логи системы..."
            Check-ServiceLogs -ServiceName $ServiceName
        }
        
        # Проверка работы
        Start-Sleep -Seconds 3
        if (Test-RASService -ServiceName $ServiceName -Port $RASPort) {
            Write-Host "`n" + ("=" * 60) -ForegroundColor Green
            Write-Success "УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
            Write-Host ("=" * 60) -ForegroundColor Green
            Write-Host "`nСлужба RAS готова к работе:"
            Write-Host "• Имя службы: $ServiceName" -ForegroundColor White
            Write-Host "• Порт: $RASPort" -ForegroundColor White
            Write-Host "• Кластер: $ClusterInstance" -ForegroundColor White
            Write-Host "• Статус: Запущена" -ForegroundColor White
            Write-Host "`nДля проверки выполните:" -ForegroundColor Yellow
            Write-Host "  Test-NetConnection -ComputerName localhost -Port $RASPort" -ForegroundColor Gray
            Write-Host "`n"
        } else {
            Write-Warning "Служба установлена, но есть проблемы с запуском или подключением"
            Write-Host "Проверьте логи и настройки вручную" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Error "Ошибка при установке: $($_.Exception.Message)"
        Write-Error "Подробности: $($_.Exception.StackTrace)"
        
        # Дополнительная диагностика
        Check-ServiceLogs -ServiceName $ServiceName
        exit 1
    }
}

# Точка входа скрипта
try {
    # Запрашиваем повышение прав
    Request-AdminElevation
    
    # Запускаем установку
    Start-Installation
    
} catch {
    Write-Error "Критическая ошибка: $($_.Exception.Message)"
    exit 1
}