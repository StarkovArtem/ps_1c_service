# Скрипт управления RAS сервером 1С

param(
    [string]$Action = "status",
    [string]$ServiceName = "1C_RAS_Server",
    [int]$Port = 1545
)

function Show-Header {
    Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan
    Write-Host "УПРАВЛЕНИЕ RAS СЕРВЕРОМ 1С" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
}

function Show-Status {
    param([string]$ServiceName, [int]$Port)
    
    Show-Header
    Write-Host "`n[СЛУЖБА]" -ForegroundColor Yellow
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        
        $statusColor = if ($service.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host "  Имя: $($service.Name)" -ForegroundColor White
        Write-Host "  Статус: $($service.Status)" -ForegroundColor $statusColor
        Write-Host "  Тип запуска: $($service.StartType)" -ForegroundColor White
        Write-Host "  Отображаемое имя: $($service.DisplayName)" -ForegroundColor White
        
        # Проверка процесса
        $process = Get-Process -Name "ras" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Host "  Процесс: Запущен (PID: $($process.Id))" -ForegroundColor Green
        } else {
            Write-Host "  Процесс: Не запущен" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "  Служба '$ServiceName' не найдена" -ForegroundColor Red
        return
    }
    
    Write-Host "`n[СЕТЬ]" -ForegroundColor Yellow
    # Проверка порта
    try {
        $tcpTest = Test-NetConnection -ComputerName localhost -Port $Port -InformationLevel Quiet
        
        if ($tcpTest) {
            Write-Host "  Порт ${Port}: Открыт и принимает подключения" -ForegroundColor Green
        } else {
            Write-Host "  Порт ${Port}: Закрыт или не отвечает" -ForegroundColor Red
        }
        
        # Статистика подключений
        $connections = netstat -an | Select-String ":${Port}"
        $activeConnections = ($connections | Measure-Object).Count
        Write-Host "  Активных подключений: $activeConnections" -ForegroundColor White
        
    } catch {
        Write-Host "  Ошибка проверки порта: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Start-RASService {
    param([string]$ServiceName)
    
    Show-Header
    try {
        Write-Host "`nЗапуск службы $ServiceName..." -ForegroundColor Yellow
        Start-Service -Name $ServiceName -ErrorAction Stop
        Write-Host "Служба успешно запущена" -ForegroundColor Green
        Start-Sleep -Seconds 2
        Show-Status -ServiceName $ServiceName
    } catch {
        Write-Host "Ошибка запуска службы: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Stop-RASService {
    param([string]$ServiceName)
    
    Show-Header
    try {
        Write-Host "`nОстановка службы $ServiceName..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -ErrorAction Stop
        Write-Host "Служба успешно остановлена" -ForegroundColor Green
    } catch {
        Write-Host "Ошибка остановки службы: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Restart-RASService {
    param([string]$ServiceName)
    
    Show-Header
    Write-Host "`nПерезапуск службы $ServiceName..." -ForegroundColor Yellow
    Stop-RASService -ServiceName $ServiceName
    Start-Sleep -Seconds 3
    Start-RASService -ServiceName $ServiceName
}

function Show-Logs {
    param([string]$LogPath = "C:\ProgramData\1C\ras\logs\ras.log")
    
    Show-Header
    Write-Host "`n[ПРОСМОТР ЛОГОВ]" -ForegroundColor Yellow
    
    $possiblePaths = @(
        "C:\ProgramData\1C\ras\logs\ras.log",
        "C:\Program Files\1C\RAS\ras.log",
        "$env:ProgramFiles\1C\RAS\ras.log"
    )
    
    $foundLog = $null
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $foundLog = $path
            break
        }
    }
    
    if ($foundLog) {
        Write-Host "Файл логов: $foundLog" -ForegroundColor White
        Write-Host "`nПоследние 20 строк лога:`n" -ForegroundColor Yellow
        
        try {
            if ((Get-Item $foundLog).Length -gt 0) {
                Get-Content $foundLog -Tail 20 -ErrorAction Stop
                Write-Host "`nДля просмотра логов в реальном времени используйте: Get-Content '$foundLog' -Wait" -ForegroundColor Gray
            } else {
                Write-Host "Файл логов пуст" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Ошибка чтения логов: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Файл логов не найден. Возможные пути:" -ForegroundColor Red
        foreach ($path in $possiblePaths) {
            Write-Host "  • $path" -ForegroundColor Gray
        }
        Write-Host "`nУбедитесь, что служба RAS была запущена хотя бы один раз." -ForegroundColor Yellow
    }
}

function Show-ServiceInfo {
    param([string]$ServiceName)
    
    Show-Header
    Write-Host "`n[ПОДРОБНАЯ ИНФОРМАЦИЯ О СЛУЖБЕ]" -ForegroundColor Yellow
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        
        # Получаем детальную информацию через WMI
        $serviceWmi = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'"
        
        if ($serviceWmi) {
            Write-Host "  Имя службы: $($serviceWmi.Name)" -ForegroundColor White
            Write-Host "  Отображаемое имя: $($serviceWmi.DisplayName)" -ForegroundColor White
            Write-Host "  Описание: $($serviceWmi.Description)" -ForegroundColor White
            Write-Host "  Состояние: $($serviceWmi.State)" -ForegroundColor White
            Write-Host "  Статус: $($serviceWmi.Status)" -ForegroundColor White
            Write-Host "  Путь: $($serviceWmi.PathName)" -ForegroundColor White
            Write-Host "  Тип запуска: $($serviceWmi.StartMode)" -ForegroundColor White
            Write-Host "  Учетная запись: $($serviceWmi.StartName)" -ForegroundColor White
        }
        
        # Проверяем конфигурацию через sc.exe
        Write-Host "`n[КОНФИГУРАЦИЯ СЛУЖБЫ]" -ForegroundColor Yellow
        $config = sc.exe qc $ServiceName 2>&1
        Write-Host $config -ForegroundColor Gray
        
    } catch {
        Write-Host "  Не удалось получить информацию о службе: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-Usage {
    Show-Header
    Write-Host "`nИспользование:" -ForegroundColor Yellow
    Write-Host "  .\manage-1c-ras.ps1 status           - Показать статус службы и порта" -ForegroundColor White
    Write-Host "  .\manage-1c-ras.ps1 start            - Запустить службу" -ForegroundColor White
    Write-Host "  .\manage-1c-ras.ps1 stop             - Остановить службу" -ForegroundColor White
    Write-Host "  .\manage-1c-ras.ps1 restart          - Перезапустить службу" -ForegroundColor White
    Write-Host "  .\manage-1c-ras.ps1 logs             - Показать логи службы" -ForegroundColor White
    Write-Host "  .\manage-1c-ras.ps1 info             - Подробная информация о службе" -ForegroundColor White
    Write-Host "  .\manage-1c-ras.ps1 help             - Показать эту справку" -ForegroundColor White
    
    Write-Host "`nПараметры:" -ForegroundColor Yellow
    Write-Host "  -ServiceName <имя>                   - Имя службы (по умолчанию: 1C_RAS_Server)" -ForegroundColor White
    Write-Host "  -Port <порт>                         - Порт RAS сервера (по умолчанию: 1545)" -ForegroundColor White
    
    Write-Host "`nПримеры:" -ForegroundColor Yellow
    Write-Host "  .\manage-1c-ras.ps1 start" -ForegroundColor Gray
    Write-Host "  .\manage-1c-ras.ps1 status -Port 1540" -ForegroundColor Gray
    Write-Host "  .\manage-1c-ras.ps1 logs" -ForegroundColor Gray
    Write-Host "  .\manage-1c-ras.ps1 info -ServiceName MyRASService" -ForegroundColor Gray
    
    Write-Host "`nПримечание:" -ForegroundColor Yellow
    Write-Host "  Для некоторых операций могут потребоваться права администратора" -ForegroundColor White
}

# Проверка прав администратора для определенных операций
function Test-AdminForAction {
    param([string]$Action)
    
    $adminActions = @("start", "stop", "restart")
    
    if ($adminActions -contains $Action.ToLower()) {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host "`nВНИМАНИЕ: Для выполнения команды '$Action' требуются права администратора!" -ForegroundColor Red
            Write-Host "Запустите скрипт от имени администратора.`n" -ForegroundColor Yellow
            return $false
        }
    }
    return $true
}

# Обработка команд
switch ($Action.ToLower()) {
    "start" { 
        if (Test-AdminForAction -Action $Action) {
            Start-RASService -ServiceName $ServiceName 
        }
    }
    "stop" { 
        if (Test-AdminForAction -Action $Action) {
            Stop-RASService -ServiceName $ServiceName 
        }
    }
    "restart" { 
        if (Test-AdminForAction -Action $Action) {
            Restart-RASService -ServiceName $ServiceName 
        }
    }
    "status" { Show-Status -ServiceName $ServiceName -Port $Port }
    "logs" { Show-Logs }
    "info" { Show-ServiceInfo -ServiceName $ServiceName }
    "help" { Show-Usage }
    default { 
        Write-Host "Неизвестная команда: $Action" -ForegroundColor Red
        Show-Usage
    }
}

# Показать подсказку для неадминистративных команд
if ($Action -eq "status" -or $Action -eq "logs" -or $Action -eq "info") {
    Write-Host "`nДля управления службой (запуск/остановка) запустите скрипт от имени администратора" -ForegroundColor Gray
}