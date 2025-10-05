#  Set-ExecutionPolicy RemoteSigned -Scope Process -Force
# ���� � ����� ��������
$clstFile = "C:\Program Files\1cv8\srvinfo\reg_1541\1CV8Clst.lst"
# ������� ���� � ������ � ������
$logBasePath = "C:\Program Files\1cv8\srvinfo\reg_1541"

# ��������� ������������� �����
if (-not (Test-Path $clstFile)) {
    Write-Host "���� �������� �� ������: $clstFile" -ForegroundColor Red
    exit
}

# ������ ���� ��� ����� � ������ GUID ���
$content = Get-Content $clstFile -Raw

# ���������� ��������� ��� ������ GUID ���
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

Write-Host "������� ��� � ��������: $($bases.Count)`n"

Write-Host "�������� ��� �� ������������� ������� LGD (������� 1cv8.lgd):"
Write-Host "-----------------------------------------------------"

$lgdBases = @()

foreach ($base in $bases) {
    $lgdFile = Join-Path -Path $logBasePath -ChildPath "$($base.GUID)\1Cv8Log\1cv8.lgd"
    
    if (Test-Path $lgdFile -PathType Leaf) {
        $lgdBases += $base
        Write-Host "���� '$($base.Name)' ($($base.GUID)) ���������� ������ LGD" -ForegroundColor Green
    }
}

Write-Host "`n�������� ������ ��� � �������� LGD:"
Write-Host "-------------------------------------"
if ($lgdBases.Count -gt 0) {
    $lgdBases | Format-Table -AutoSize
} else {
    Write-Host "�� ������� �� ����� ���� � �������� LGD" -ForegroundColor Yellow
}

# ����������
Write-Host "`n����������:"
Write-Host "����� ��� � ��������: $($bases.Count)"
Write-Host "�� ��� ���������� LGD: $($lgdBases.Count)"