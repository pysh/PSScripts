# Определяем структуру папок
$baseDir = $PSScriptRoot
$dictDir = Join-Path $baseDir "dict"
$inDir = Join-Path $baseDir "in"
$reportsDir = Join-Path $baseDir "reports"
$archDir = Join-Path $baseDir "arch"

# Создаем папки, если их нет
foreach ($dir in ($dictDir, $inDir, $reportsDir, $archDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

# Загружаем Сущности.csv и фильтруем данные для qRIS
$entities = Import-Csv (Join-Path $dictDir "Сущности.csv") -Delimiter ','
$qRIS = $entities | Where-Object {
    $_.'Тип' -eq 'IT-система' -and $_.'Тип ЦС' -eq 'Прикладная'
} | Select-Object 'РИС ИД', 'Общепринятое короткое название', 'Идентификационный код системы'

# Загружаем Общебанк.csv
$OBank = Import-Csv (Join-Path $dictDir "Общебанк.csv") -Delimiter ';'

# Создаем хеш-таблицы для быстрого поиска
$qRIS_map = @{}
$qRIS | ForEach-Object {
    $qRIS_map[$_.'Идентификационный код системы'] = $_
}

$OBank_map = @{}
$OBank | ForEach-Object {
    $OBank_map[$_.'рис ID'] = $_
}

# Обрабатываем все CSV файлы в папке in
Get-ChildItem $inDir -Filter "*.csv" | ForEach-Object {
    $inputFile = $_.FullName
    $fileName = $_.Name
    $reportFile = Join-Path $reportsDir "report_$fileName"
    $archFile = Join-Path $archDir $fileName

    Write-Host "Обработка файла: $fileName"

    try {
        # Чтение входного файла
        $RO2907 = Import-Csv $inputFile -Delimiter ';'

        # Выполняем JOIN операции
        $result = $RO2907 | ForEach-Object {
            $ris_code = $_.'РИС код'
            $qris_item = $qRIS_map[$ris_code]
            
            if ($qris_item) {
                $ob_item = $OBank_map[$qris_item.'РИС ИД']
                
                [PSCustomObject]@{
                    'рис ID'   = $qris_item.'РИС ИД'
                    'Название' = $ob_item.Название
                    'Команда'  = $ob_item.Команда
                    'Всего'    = $_.'Всего'
                    'Описано'  = $_.'Описано'
                }
            }
        }

        # Сортировка и экспорт отчета
        $result | Sort-Object Команда, 'рис ID' |
            Export-Csv $reportFile -Delimiter ';' -Encoding UTF8 -NoTypeInformation

        # Перемещаем обработанный файл в архив
        Move-Item $inputFile $archFile -Force

        Write-Host "Файл обработан. Отчет: $reportFile"
    }
    catch {
        Write-Host "Ошибка при обработке файла $fileName : $_" -ForegroundColor Red
    }
}

Write-Host "Обработка завершена. Проверьте папку reports." -ForegroundColor Green