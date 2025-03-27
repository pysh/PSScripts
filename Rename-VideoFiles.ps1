# Скрипт переименования видеофайлов по данным TheTV DB
param(
    [string]$FolderPath = "y:\.temp\Сериалы\Зарубежные\Джоан\season 01\out_[SvtAv1EncApp]\",
    [string]$ApiKey = ""
)

# Подключение необходимых библиотек
Add-Type -AssemblyName System.Web.Extensions

function Get-TvShowMetadata {
    param(
        [string]$FileName
    )

    # Логика извлечения информации о сериале
    $seriesName = $FileName -replace '\..*$'
    
    # Вызов API TheTV DB для получения метаданных
    $apiUrl = "https://api.thetvdb.com/search/series?name=$seriesName"
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{
            "Authorization" = "Bearer $ApiKey"
            "Content-Type" = "application/json"
        }

        # Обработка полученных данных
        if ($response.data.Count -gt 0) {
            $seriesId = $response.data[0].id
            return $seriesId
        }
    }
    catch {
        Write-Error "Ошибка при получении метаданных: $_"
    }
}

function Rename-TvShowFile {
    param(
        [string]$FilePath
    )

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $seriesId = Get-TvShowMetadata -FileName $fileName

    if ($seriesId) {
        # Логика формирования нового имени файла
        $episodeDetails = Get-EpisodeDetails -SeriesId $seriesId -FileName $fileName
        
        $newFileName = "{0} - S{1}E{2} - {3}{4}" -f `
            $episodeDetails.SeriesName, 
            $episodeDetails.SeasonNumber, 
            $episodeDetails.EpisodeNumber, 
            $episodeDetails.EpisodeName, 
            [System.IO.Path]::GetExtension($FilePath)

        $newFilePath = Join-Path (Split-Path $FilePath) $newFileName

        # Переименование файла
        # Rename-Item -Path $FilePath -NewName $newFileName
        Write-Host "Переименован файл: $fileName -> $newFileName"
    }
}

function Get-EpisodeDetails {
    param(
        [string]$SeriesId,
        [string]$FileName
    )

    # Извлечение номера сезона и эпизода из имени файла
    $seasonMatch = $FileName -match 'S(\d+)E(\d+)'
    $seasonNumber = $Matches[1]
    $episodeNumber = $Matches[2]

    # Получение деталей эпизода через API TheTV DB
    $apiUrl = "https://api.thetvdb.com/series/$SeriesId/episodes/query?airedSeason=$seasonNumber&airedEpisodeNumber=$episodeNumber"
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{
            "Authorization" = "Bearer $ApiKey"
            "Content-Type" = "application/json"
        }

        if ($response.data.Count -gt 0) {
            return @{
                SeriesName = $response.data[0].seriesName
                SeasonNumber = $seasonNumber
                EpisodeNumber = $episodeNumber
                EpisodeName = $response.data[0].episodeName
            }
        }
    }
    catch {
        Write-Error "Ошибка при получении деталей эпизода: $_"
    }
}

# Основная логика скрипта
function Process-TvShowFolder {
    param(
        [string]$FolderPath
    )

    $videoExtensions = @(".mkv", ".avi", ".mp4", ".mov")
    
    Get-ChildItem -LiteralPath $FolderPath -File | Where-Object {
        $videoExtensions -contains $_.Extension
    } | ForEach-Object {
        Rename-TvShowFile -FilePath $_.FullName
    }
}

# Запуск обработки папки
Process-TvShowFolder -FolderPath $FolderPath