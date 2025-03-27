# Скрипт для добавления глобального заголовка и обложки к видеофайлам

# Путь к утилите mkvpropedit (убедитесь, что путь корректный)
$mkvPropEditPath = "C:\Program Files\MKVToolNix\mkvpropedit.exe"

# Папка с видеофайлами
$videoFolder = "g:\Видео\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\season 02\"

# Путь к обложке (изображение в формате jpg или png)
$coverImagePath = "g:\Видео\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\season 02\cover.jpg"

# Проверка существования утилиты mkvpropedit
if (-not (Test-Path $mkvPropEditPath)) {
    Write-Error "mkvpropedit не найден по пути: $mkvPropEditPath"
    exit
}

# Получаем все видеофайлы MKV в указанной папке
$mkvFiles = Get-ChildItem -Path $videoFolder -Filter *.mkv

if (-not (Test-Path $coverImagePath)) {
    Write-Warning "Файл обложки не найден: $coverImagePath"
}

foreach ($file in $mkvFiles) {
    try {
        # Добавляем глобальный заголовок
        if ($file.BaseName -match '^(.*\d\d-\d\d-\d\d\]).*') {
            $globalTitle = $Matches[1]
            & $mkvPropEditPath $file.FullName --edit info --set title="$globalTitle"
        }

        # Добавляем обложку
        if (Test-Path $coverImagePath) {
            & $mkvPropEditPath $file.FullName --edit cover add "$coverImagePath"
        }

        Write-Host "Обработан файл: $($file.Name)"
    }
    catch {
        Write-Error "Ошибка при обработке файла $($file.Name): $_"
    }
}

Write-Host "Обработка завершена."