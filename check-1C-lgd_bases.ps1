#  Set-ExecutionPolicy RemoteSigned -Scope Process -Force
# Путь к файлу кластера
$clstFile = "C:\Program Files\1cv8\srvinfo\reg_1541\1CV8Clst.lst"
# Базовый путь к папкам с логами
$logBasePath = "C:\Program Files\1cv8\srvinfo\reg_1541"

# Проверяем существование файла
if (-not (Test-Path $clstFile)) {
    Write-Host "Файл кластера не найден: $clstFile" -ForegroundColor Red
    exit
}

# Читаем файл как текст и парсим GUID баз
$content = Get-Content $clstFile -Raw

# Регулярное выражение для поиска GUID баз
$pattern = '\{[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12},"[^"]*","[^"]*","[^"]*"'
$matches = [regex]::Matches($content, $pattern)

$bases = @()
foreach ($match in $matches) {
    $parts = $match.Value -split ','
    $guid = $parts[0].Trim('{')
    $base_code = $parts[1].Trim('"')
    $name = $parts[2].Trim('"')
    $bases += [PSCustomObject]@{
        GUID = $guid
        Base_code= $base_code
        Name = $name
    }
}

Write-Host "Найдено баз в кластере: $($bases.Count)`n"

Write-Host "Проверка баз на использование формата LGD (наличие 1cv8.lgd):"
Write-Host "-----------------------------------------------------"

$lgdBases = @()

foreach ($base in $bases) {
    $lgdFile = Join-Path -Path $logBasePath -ChildPath "$($base.GUID)\1Cv8Log\1cv8.lgd"
    
    if (Test-Path $lgdFile -PathType Leaf) {
        $lgdBases += $base
        Write-Host "База '$($base.Name)' ($($base.GUID)) использует формат LGD" -ForegroundColor Green
    }
}

Write-Host "`nИтоговый список баз с форматом LGD:"
Write-Host "-------------------------------------"
if ($lgdBases.Count -gt 0) {
    $lgdBases | Format-Table -AutoSize
} else {
    Write-Host "Не найдено ни одной базы с форматом LGD" -ForegroundColor Yellow
}

# Статистика
Write-Host "`nСтатистика:"
Write-Host "Всего баз в кластере: $($bases.Count)"
Write-Host "Из них используют LGD: $($lgdBases.Count)"