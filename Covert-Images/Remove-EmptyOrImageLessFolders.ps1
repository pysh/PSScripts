function Remove-EmptyOrImageLessFolders {
    param (
        [Parameter(Mandatory=$false)]
        [string]$RootPath = 'X:\temp2\xuk\',
        
        [string[]]$ImageExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.webp')
    )

    if (-not (Test-Path -Path $RootPath -PathType Container)) {
        Write-Error "Указанный путь не существует или не является папкой: $RootPath"
        return
    }

    # Получаем все подпапки рекурсивно (сортировка по глубине - от самых вложенных к корню)
    $allFolders = Get-ChildItem -Path $RootPath -Directory -Recurse | 
                Select-Object -Property FullName, @{Name="Depth"; Expression={$_.FullName.Split('\').Count}} |
                Sort-Object -Property Depth -Descending

    foreach ($folder in $allFolders) {
        $folderPath = $folder.FullName

        # Проверяем, содержит ли папка файлы с указанными расширениями
        $hasImages = Get-ChildItem -Path $folderPath -File | 
                    Where-Object { $ImageExtensions -contains $_.Extension.ToLower() } |
                    Select-Object -First 1

        # Если папка пустая или не содержит изображений
        if (-not $hasImages -and -not (Get-ChildItem -Path $folderPath -Force | Select-Object -First 1)) {
            try {
                Write-Host "Удаление пустой/без изображений папки: $folderPath" -ForegroundColor Yellow
                Remove-Item -Path $folderPath -Force -Recurse -ErrorAction Stop
            }
            catch {
                Write-Warning "Не удалось удалить папку $folderPath : $_"
            }
        }
    }

    # Проверяем корневую папку после обработки вложенных
    if (-not (Get-ChildItem -Path $RootPath -Force | Select-Object -First 1)) {
        try {
            Write-Host "Удаление пустой корневой папки: $RootPath" -ForegroundColor Yellow
            Remove-Item -Path $RootPath -Force -Recurse -ErrorAction Stop
        }
        catch {
            Write-Warning "Не удалось удалить корневую папку $RootPath : $_"
        }
    }
    # Write-Host "Очистка завершена." -ForegroundColor Green
}





# Путь к папке с файлами (можно изменить)
$folderPath = "X:\temp2\xuk\"

# Получаем все файлы в папке
$files = Get-ChildItem -Path $folderPath -File -Recurse

# Группируем файлы по первой части имени (до высоты)
$fileGroups = $files | Where-Object { $_.Name -match '(?<g1>.*)_(?<gHeight>\d*)__(?<g3>\d*)(?<gExt>.*)' } |
    Group-Object { $matches.g1 }

[int]$DeletedFileSize=0
foreach ($group in $fileGroups) {
    # Для каждой группы находим файл с максимальной высотой
    $maxHeightFile = $group.Group | ForEach-Object {
        if ($_.Name -match '(?<g1>.*)_(?<gHeight>\d*)__(?<g3>\d*)(?<gExt>.*)') {
            [PSCustomObject]@{
                File = $_
                Height = [int]$matches.gHeight
            }
        }
    } | Sort-Object -Property Height -Descending | Select-Object -First 1

    if ($maxHeightFile) {
        # Удаляем все файлы в группе, кроме файла с максимальной высотой
        $group.Group | Where-Object { $_.FullName -ne $maxHeightFile.File.FullName } | ForEach-Object {
            Write-Host "Удаляем файл: $($_.Name)" -ForegroundColor Magenta
            # Rename-Item -LiteralPath $_.FullName -NewName "$($_.FullName).~todel~"
            $DeletedFileSize += $_.Length
            Remove-Item -Path $_.FullName
        }
        # Write-Host "Оставлен файл: $($maxHeightFile.File.Name)" -ForegroundColor Green
    }
}

Write-Host 'Удаление пустых папок...' -ForegroundColor Cyan
Remove-EmptyOrImageLessFolders -Verbose
Write-Host ("Обработка завершена. Освобождено $($DeletedFileSize/1MB) Мб.") -ForegroundColor Green