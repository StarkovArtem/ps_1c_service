function Show-Menu {
    Clear-Host
    Write-Host "=========================================="
    Write-Host "           ГЛАВНОЕ МЕНЮ                   "
    Write-Host "=========================================="
    Write-Host "                                          "
    Write-Host "1 - Скачать и установить скрипты          "
    Write-Host "0 - Выход                                 "
    Write-Host "                                          "
    Write-Host "=========================================="
}

function Test-ValidPath {
    param([string]$Path)
    
    try {
        # Проверяем, является ли путь допустимым
        $testPath = [System.IO.Path]::GetFullPath($Path)
        
        # Проверяем, что путь абсолютный
        if (-not [System.IO.Path]::IsPathRooted($Path)) {
            return $false
        }
        
        # Проверяем наличие недопустимых символов
        $invalidChars = [System.IO.Path]::GetInvalidPathChars()
        foreach ($char in $invalidChars) {
            if ($Path.Contains($char)) {
                return $false
            }
        }
        
        return $true
    }
    catch {
        return $false
    }
}

function Download-Project {
    param([string]$InstallPath)
    
    Write-Host "`nНачинаем загрузку проекта..."
    
    try {
        # Создаем папку, если она не существует
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
            Write-Host "Создана папка: $InstallPath"
        }
        
        # URL для скачивания ZIP-архива с GitHub
        $zipUrl = "https://github.com/StarkovArtem/ps_1c_service/archive/refs/heads/main.zip"
        $tempZip = Join-Path $env:TEMP "ps_1c_service_main.zip"
        $extractPath = Join-Path $env:TEMP "ps_1c_service_extract"
        
        # Очищаем временные файлы
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
        
        Write-Host "Скачиваем архив..."
        
        # Скачиваем ZIP-архив
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($zipUrl, $tempZip)
        $webClient.Dispose()
        
        Write-Host "Распаковываем архив..."
        
        # Распаковываем архив
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $extractPath)
        
        # Находим распакованную папку
        $sourceFolder = Get-ChildItem $extractPath -Directory | Select-Object -First 1
        
        if ($sourceFolder) {
            Write-Host "Копируем файлы в $InstallPath..."
            
            # Копируем все файлы из распакованной папки в целевую
            Copy-Item -Path "$($sourceFolder.FullName)\*" -Destination $InstallPath -Recurse -Force
            
            Write-Host "`nПроект успешно установлен в: $InstallPath"
            Write-Host "Файлы проекта:"
            Get-ChildItem $InstallPath | ForEach-Object { Write-Host "  - $($_.Name)" }
        }
        else {
            Write-Host "Ошибка: не удалось найти файлы в архиве"
            return $false
        }
        
        # Очищаем временные файлы
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
        
        return $true
    }
    catch {
        Write-Host "Ошибка при загрузке проекта: $($_.Exception.Message)"
        return $false
    }
}

function Get-InstallPath {
    Clear-Host
    Write-Host "=========================================="
    Write-Host "      ВЫБОР КАТАЛОГА УСТАНОВКИ           "
    Write-Host "=========================================="
    Write-Host "                                          "
    
    # Показываем путь по умолчанию как редактируемое поле
    $defaultPath = "C:\ps_1c_service"
    $userInput = Read-Host "Путь установки" -Default $defaultPath
    
    # Если пользователь не ввел ничего, используем путь по умолчанию
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $userInput = $defaultPath
    }
    
    # Проверяем корректность пути
    if (Test-ValidPath -Path $userInput) {
        return $userInput
    }
    else {
        Write-Host "`nОШИБКА: Введен некорректный путь!      "
        Write-Host "Пожалуйста, введите правильный путь      "
        Write-Host "в формате Windows                        "
        Write-Host "Например: C:\MyFolder\ps_scripts        "
        Write-Host "                                          "
        
        $choice = Read-Host "Повторить ввод? (Y/Н)           "
        if ($choice -eq "Y" -or $choice -eq "y" -or $choice -eq "Д" -or $choice -eq "д") {
            return Get-InstallPath
        }
        else {
            return $null
        }
    }
}

# Главный цикл программы
do {
    Show-Menu
    $choice = Read-Host "`nВыберите пункт меню              "
    
    switch ($choice) {
        "1" {
            $installPath = Get-InstallPath
            if ($installPath) {
                Write-Host "`nВыбран путь: $installPath       "
                Write-Host "Начинаем установку...            "
                $result = Download-Project -InstallPath $installPath
                if ($result) {
                    Write-Host "`nУстановка завершена успешно!    "
                }
                else {
                    Write-Host "`nУстановка завершена с ошибками. "
                }
            }
            else {
                Write-Host "Установка отменена из-за         "
                Write-Host "некорректного пути.              "
            }
            
            Write-Host "`nНажмите Enter для продолжения..."
            Read-Host
        }
        "0" {
            Write-Host "`nЗавершение работы...              "
            exit
        }
        default {
            Write-Host "`nНеверный выбор. Пожалуйста,       "
            Write-Host "выберите 0 или 1.                   "
            Start-Sleep -Seconds 2
        }
    }
} while ($true)