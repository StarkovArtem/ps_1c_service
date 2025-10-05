# Конфигурация
$LogFolderPath = "C:\Program Files\1cv8\srvinfo"
$MaxSizeMB = 500
$LogExtensions = @("*.lgp", "*.lgx")

# Параметры обработки
$DeleteOverSize = $false  # true - удалять файлы превышающие лимит, false - только показывать
$MoveTo = ""  # UNC-путь к сетевой папке для перемещения (например: "\\server\logs\1C")
$NetworkLogin = ""  # Логин для доступа к сетевой папке
$NetworkPassword = ""  # Пароль для доступа к сетевой папке

# Функция для проверки прав администратора
function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Функция для запуска с повышенными правами
function Start-Elevated {
    param([string]$ScriptPath)
    
    if (-not (Test-Administrator)) {
        Write-Host "Запуск с повышенными правами..." -ForegroundColor Yellow
        $arguments = "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        Start-Process PowerShell -Verb RunAs -ArgumentList $arguments -Wait
        exit
    }
}

# Функция для проверки прав на удаление файла
function Test-FileDeleteAccess {
    param([string]$FilePath)
    
    try {
        $file = Get-Item $FilePath -ErrorAction Stop
        $acl = Get-Acl $file.FullName
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        # Проверяем права на запись
        $accessRules = $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])
        foreach ($rule in $accessRules) {
            if ($rule.IdentityReference -eq $currentUser -or 
                $rule.IdentityReference -like "BUILTIN\Administrators" -or
                $rule.IdentityReference -like "NT AUTHORITY\SYSTEM") {
                if (($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete) -eq [System.Security.AccessControl.FileSystemRights]::Delete -and
                    $rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
                    return $true
                }
            }
        }
        return $false
    }
    catch {
        return $false
    }
}

# Функция для установки прав на файл
function Set-FilePermissions {
    param([string]$FilePath)
    
    try {
        $acl = Get-Acl $FilePath
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        # Добавляем права на полный доступ для текущего пользователя
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        
        $acl.AddAccessRule($accessRule)
        Set-Acl -Path $FilePath -AclObject $acl
        return $true
    }
    catch {
        Write-Host "    Ошибка установки прав на файл $FilePath : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Функция для безопасного удаления файла
function Remove-FileSafely {
    param([System.IO.FileInfo]$File)
    
    try {
        # Проверяем права перед удалением
        if (-not (Test-FileDeleteAccess -FilePath $File.FullName)) {
            Write-Host "    Недостаточно прав для удаления $($File.Name). Попытка установки прав..." -ForegroundColor Yellow
            
            if (Set-FilePermissions -FilePath $File.FullName) {
                Write-Host "    Права установлены успешно для $($File.Name)" -ForegroundColor Green
            } else {
                Write-Host "    Не удалось установить права для $($File.Name)" -ForegroundColor Red
                return $false
            }
        }
        
        # Пытаемся удалить файл
        Remove-Item -Path $File.FullName -Force -ErrorAction Stop
        Write-Host "    Удален: $($File.Name)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "    Ошибка удаления $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
        
        # Альтернативная попытка через cmd
        try {
            Write-Host "    Альтернативная попытка удаления через cmd..." -ForegroundColor Yellow
            $result = cmd /c "del /F /Q `"$($File.FullName)`"" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    Удален (через cmd): $($File.Name)" -ForegroundColor Green
                return $true
            } else {
                Write-Host "    Не удалось удалить даже через cmd: $($File.Name)" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "    Критическая ошибка удаления: $($File.Name)" -ForegroundColor Red
            return $false
        }
    }
}

# Функция для подключения сетевого диска
function Connect-NetworkDrive {
    param([string]$UNC, [string]$Login, [string]$Password)
    
    if ([string]::IsNullOrEmpty($UNC)) {
        return $null
    }
    
    try {
        # Создаем временную букву диска
        $driveLetter = "Z"
        
        # Если диск уже подключен - отключаем
        if (Test-Path "${driveLetter}:") {
            net use ${driveLetter}: /delete /y 2>&1 | Out-Null
        }
        
        if ([string]::IsNullOrEmpty($Login)) {
            # Подключение без учетных данных (с текущими правами)
            net use "${driveLetter}:" $UNC 2>&1 | Out-Null
        } else {
            # Подключение с указанием учетных данных
            $netPass = $Password | ConvertTo-SecureString -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($Login, $netPass)
            New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $UNC -Credential $credential -Scope Global 2>&1 | Out-Null
        }
        
        if (Test-Path "${driveLetter}:") {
            Write-Host "Сетевой диск подключен: $UNC -> ${driveLetter}:" -ForegroundColor Green
            return $driveLetter
        } else {
            Write-Host "Ошибка подключения сетевого диска: $UNC" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "Ошибка при подключении сетевого диска: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Функция для отключения сетевого диска
function Disconnect-NetworkDrive {
    param([string]$DriveLetter)
    
    if (-not [string]::IsNullOrEmpty($DriveLetter)) {
        try {
            net use "${DriveLetter}:" /delete /y 2>&1 | Out-Null
            Write-Host "Сетевой диск отключен: ${DriveLetter}:" -ForegroundColor Green
        }
        catch {
            Write-Host "Ошибка при отключении сетевого диска: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Функция для перемещения файлов в сетевую папку
function Move-FilesToNetwork {
    param([array]$Files, [string]$NetworkPath, [string]$SourceFolder)
    
    $movedCount = 0
    $movedSize = 0
    
    # Создаем подпапку с именем исходной папки и датой
    $folderName = (Get-Item $SourceFolder).Parent.Name
    $dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $targetFolder = Join-Path $NetworkPath "$folderName`_$dateStamp"
    
    try {
        if (-not (Test-Path $targetFolder)) {
            New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
        }
        
        foreach ($file in $Files) {
            try {
                $targetPath = Join-Path $targetFolder $file.Name
                
                # Проверяем права перед перемещением
                if (-not (Test-FileDeleteAccess -FilePath $file.FullName)) {
                    Write-Host "    Недостаточно прав для перемещения $($file.Name). Попытка установки прав..." -ForegroundColor Yellow
                    Set-FilePermissions -FilePath $file.FullName
                }
                
                Move-Item -Path $file.FullName -Destination $targetPath -Force
                Write-Host "    Перемещен: $($file.Name) -> $targetFolder" -ForegroundColor Green
                $movedCount++
                $movedSize += $file.Length
            }
            catch {
                Write-Host "    Ошибка перемещения $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        return @{
            Count = $movedCount
            SizeMB = [math]::Round($movedSize / 1MB, 2)
            Folder = $targetFolder
        }
    }
    catch {
        Write-Host "Ошибка при создании папки назначения: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Count = 0; SizeMB = 0; Folder = "" }
    }
}

# Функция для получения размера папки в МБ
function Get-FolderSize {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        return 0
    }
    
    $size = (Get-ChildItem -Path $Path -Recurse -File | 
             Where-Object { $_.Extension -in @('.lgp', '.lgx') } | 
             Measure-Object -Property Length -Sum).Sum
    
    return [math]::Round($size / 1MB, 2)
}

# Функция для получения файлов для удаления
function Get-FilesToDelete {
    param([string]$FolderPath, [double]$CurrentSizeMB)
    
    if ($CurrentSizeMB -le $MaxSizeMB) {
        return @()
    }
    
    # Получаем все файлы логов и сортируем по дате создания (старые первыми)
    $logFiles = Get-ChildItem -Path $FolderPath -Recurse -File | 
                Where-Object { $_.Extension -in @('.lgp', '.lgx') } |
                Sort-Object CreationTime
    
    $filesToDelete = @()
    $sizeToFreeMB = $CurrentSizeMB - $MaxSizeMB
    $freedSize = 0
    
    foreach ($file in $logFiles) {
        if ($freedSize -lt $sizeToFreeMB) {
            $filesToDelete += $file
            $freedSize += $file.Length / 1MB
        } else {
            break
        }
    }
    
    return $filesToDelete
}

# Основная логика
try {
    # Проверяем права администратора
    if (-not (Test-Administrator) -and ($DeleteOverSize -or (-not [string]::IsNullOrEmpty($MoveTo)))) {
        Write-Host "Требуются права администратора для удаления/перемещения файлов" -ForegroundColor Yellow
        Write-Host "Перезапускаем скрипт с повышенными правами..." -ForegroundColor Yellow
        Start-Elevated -ScriptPath $MyInvocation.MyCommand.Path
        exit
    }
    
    Write-Host "Управление логами 1С" -ForegroundColor Green
    Write-Host "====================" -ForegroundColor Green
    Write-Host "Папка с логами: $LogFolderPath"
    Write-Host "Максимальный размер: $MaxSizeMB MB"
    Write-Host "Режим удаления: $DeleteOverSize"
    Write-Host "Перемещение в: $(if ([string]::IsNullOrEmpty($MoveTo)) { 'Не задано' } else { $MoveTo })"
    Write-Host "Права администратора: $(if (Test-Administrator) { 'Да' } else { 'Нет' })" -ForegroundColor $(if (Test-Administrator) { "Green" } else { "Yellow" })
    Write-Host ""
    
    # Подключаем сетевой диск если указан путь для перемещения
    $networkDrive = $null
    if (-not [string]::IsNullOrEmpty($MoveTo)) {
        $networkDrive = Connect-NetworkDrive -UNC $MoveTo -Login $NetworkLogin -Password $NetworkPassword
        if (-not $networkDrive) {
            Write-Host "Невозможно продолжить: ошибка подключения к сетевой папке" -ForegroundColor Red
            exit 1
        }
    }
    
    # Находим все папки с логами
    $logFolders = Get-ChildItem -Path $LogFolderPath -Directory -Recurse | 
                  Where-Object { $_.Name -eq "1Cv8Log" }
    
    if ($logFolders.Count -eq 0) {
        Write-Host "Папки с логами не найдены!" -ForegroundColor Red
        if ($networkDrive) { Disconnect-NetworkDrive -DriveLetter $networkDrive }
        exit 1
    }
    
    $totalFreedSpace = 0
    $totalMovedSpace = 0
    $hasFilesToDelete = $false
    
    foreach ($logFolder in $logFolders) {
        $parentFolder = $logFolder.Parent.Name
        $folderSizeMB = Get-FolderSize -Path $logFolder.FullName
        
        Write-Host "Папка: $parentFolder" -ForegroundColor Cyan
        Write-Host "  Полный путь: $($logFolder.FullName)"
        Write-Host "  Текущий размер: $folderSizeMB MB"
        
        if ($folderSizeMB -gt $MaxSizeMB) {
            Write-Host "  Статус: ПРЕВЫШЕНИЕ ЛИМИТА" -ForegroundColor Red
            
            $filesToDelete = Get-FilesToDelete -FolderPath $logFolder.FullName -CurrentSizeMB $folderSizeMB
            $spaceToFreeMB = [math]::Round(($folderSizeMB - $MaxSizeMB), 2)
            
            Write-Host "  Необходимо освободить: $spaceToFreeMB MB"
            Write-Host "  Файлов для обработки: $($filesToDelete.Count)"
            
            if ($filesToDelete.Count -gt 0) {
                $hasFilesToDelete = $true
                $processSizeMB = [math]::Round(($filesToDelete | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
                
                Write-Host "  Будет обработано: $processSizeMB MB" -ForegroundColor Yellow
                Write-Host "  Файлы для обработки:"
                
                foreach ($file in $filesToDelete) {
                    Write-Host "    - $($file.Name) ($([math]::Round($file.Length/1MB, 2)) MB) [$($file.CreationTime)]"
                }
                
                # Обработка файлов в зависимости от режима
                if ($networkDrive) {
                    # Режим перемещения в сетевую папку
                    Write-Host "  ПЕРЕМЕЩЕНИЕ ФАЙЛОВ В СЕТЕВУЮ ПАПКУ..." -ForegroundColor Blue
                    $networkPath = "${networkDrive}:"
                    $moveResult = Move-FilesToNetwork -Files $filesToDelete -NetworkPath $networkPath -SourceFolder $logFolder.FullName
                    Write-Host "  Перемещено файлов: $($moveResult.Count) ($($moveResult.SizeMB) MB)" -ForegroundColor Green
                    $totalMovedSpace += $moveResult.SizeMB
                    
                } elseif ($DeleteOverSize) {
                    # Режим удаления
                    Write-Host "  УДАЛЕНИЕ ФАЙЛОВ..." -ForegroundColor Red
                    
                    $deletedCount = 0
                    foreach ($file in $filesToDelete) {
                        if (Remove-FileSafely -File $file) {
                            $deletedCount++
                            $totalFreedSpace += $file.Length / 1MB
                        }
                    }
                    Write-Host "  Удалено файлов: $deletedCount" -ForegroundColor Green
                }
            }
        } else {
            Write-Host "  Статус: В ПРЕДЕЛАХ ЛИМИТA" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    # Отключаем сетевой диск если был подключен
    if ($networkDrive) {
        Disconnect-NetworkDrive -DriveLetter $networkDrive
    }
    
    # Итоговая информация
    Write-Host "ИТОГИ ОБРАБОТКИ:" -ForegroundColor Magenta
    if ($networkDrive) {
        Write-Host "Перемещено логов: $([math]::Round($totalMovedSpace, 2)) MB" -ForegroundColor Green
    } elseif ($DeleteOverSize) {
        Write-Host "Освобождено места: $([math]::Round($totalFreedSpace, 2)) MB" -ForegroundColor Green
    } elseif ($hasFilesToDelete) {
        Write-Host "Для удаления файлов установите `$DeleteOverSize = `$true" -ForegroundColor Yellow
        Write-Host "или укажите сетевую папку в `$MoveTo для перемещения логов" -ForegroundColor Yellow
    } else {
        Write-Host "Превышений лимита не обнаружено." -ForegroundColor Green
    }
}
catch {
    Write-Host "Ошибка выполнения скрипта: $($_.Exception.Message)" -ForegroundColor Red
    if ($networkDrive) { Disconnect-NetworkDrive -DriveLetter $networkDrive }
    exit 1
}