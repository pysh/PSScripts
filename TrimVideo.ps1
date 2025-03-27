# Импортируем функции из tools.ps1
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1'

function Get-KeyFrames {
    param (
        [string]$videoPath
    )

    # Получаем информацию о видео для определения FPS
    $videoStats = Get-VideoStats -VideoPath $videoPath
    $fps = $videoStats.FPS

    # Получение ключевых кадров
    $framesJSON = & ffprobe -v error -select_streams v:0 -count_packets -show_entries "packet=pts_time,pts,flags" -of json "$videoPath" 2>&1
    $framesOutput = ($framesJSON | ConvertFrom-Json).packets | Sort-Object pts -Unique |
    Select-Object @{l = "pts_time"; e = { [double]$_.pts_time } },
    flags, pts,
    @{l = "Frame"; e = { [math]::Round($_.pts * $fps / 1000) } }

    # Последний кадр всегда ключевой
    $lastFrameIdx = $framesOutput.Count
    if ($lastFrameIdx -gt 0) {
        $framesOutput[$lastFrameIdx-1].flags = 'KKK'
    }

    # Фильтруем только ключевые кадры
    $keyFrames = $framesOutput | Where-Object { $_.flags -match ".*K.*" }

    Clear-Variable "framesJSON", "framesOutput"
    return $keyFrames
}

function Parse-FrameIntervals {
    param (
        [string[]]$Intervals,
        [int]$TotalFrames
    )

    return $Intervals | ForEach-Object {
        $parts = $_ -split '-'

        $start = if ($parts[0] -eq '') { 0 } else { [int]$parts[0] }
        $end = if ($parts.Count -eq 1 -or $parts[1] -eq '') { $TotalFrames - 1 } else { [int]$parts[1] }

        @{
            Start = $start
            End   = $end
        }
    }
}

function Trim-Video {
    param (
        [string]$videoPath,
        [string[]]$Intervals
    )

    # Получаем статистику видео один раз
    $videoStats = Get-VideoStats -VideoPath $videoPath

    # Получаем ключевые кадры
    $keyFrames = Get-KeyFrames -videoPath $videoPath

    # Парсим интервалы
    $parsedIntervals = Parse-FrameIntervals -Intervals $Intervals -TotalFrames $videoStats.Frames

    $results = @()

    foreach ($interval in $parsedIntervals) {
        $startFrame = $interval.Start
        $endFrame = $interval.End

        # Находим ближайшие ключевые кадры
        $startKeyFrame = $keyFrames.Frame |
        Where-Object { $_ -ge $startFrame } |
        Select-Object -First 1

        $endKeyFrame = $keyFrames.Frame |
        Where-Object { $_ -le $endFrame } |
        Select-Object -Last 1

        Write-Host "frames:   ", $startFrame, $endFrame -ForegroundColor Cyan
        Write-Host "keyframes:", $startKeyFrame, $endKeyFrame -ForegroundColor Blue

        # Добавляем сегменты
        if ($startKeyFrame -ne $startFrame) {
            $results += @{
                "frameStart"= $startFrame
                "frameEnd"  = $endFrame
                "trimStart" = $startFrame
                "trimEnd"   = $startKeyFrame # - 1
                "trimType"  = "recode1"
            }
        } else {
                $startFrame = $startKeyFrame
        }

        # Добавляем основной сегмент
        $results += @{
            "frameStart"= $startFrame
            "frameEnd"  = $endFrame
            "trimStart" = $startKeyFrame
            "trimEnd"   = $endKeyFrame
            "trimType" = "copy"
            #"trimType"  = $(if ($startKeyFrame -eq $startFrame -and $endKeyFrame -eq $endFrame) { "copy" } else { "recode2" })
        }

        # Добавляем последний сегмент, если нужно перекодирование
        if ($endKeyFrame -ne $endFrame) {
            $results += @{
                "frameStart"= $startFrame
                "frameEnd"  = $endFrame
                "trimStart" = $endKeyFrame + 1
                "trimEnd"   = $endFrame
                "trimType"  = "recode2"
            }
        }
    }

    return $results | Select-Object frameStart, frameEnd, trimStart, trimEnd, trimType
}

# Функция для выполнения обрезки видео
function Execute-VideoTrim {
    param (
        [string]$videoPath,
        [string[]]$Intervals,
        [string]$OutputPath
    )

    $trimParts = Trim-Video -videoPath $videoPath -Intervals $Intervals
    $tempFiles = @()
    $n = 0

    foreach ($part in $trimParts) {
        $startFrame = $part.trimStart
        $endFrame = $part.trimEnd
        $type = $part.trimType
        $n++

        #$tempFile = Join-Path -Path ([System.IO.Path]::GetDirectoryName($OutputPath)) -ChildPath ("{0:00000}_{1}" -f $n, [System.IO.File]::GetFileName($OutputPath))
        $tempFile = Join-Path -Path (Split-Path -Path $OutputPath -Parent) -ChildPath ("{0:00000}_{1}" -f $n, (Split-Path -Path $OutputPath -Leaf))
        $tempFiles += $tempFile

        $ffmpegArgs = @(
            '-y -hide_banner'
            "-ss $(($startFrame / 25)) -to $(($endFrame / 25))"
            "-i `"$($videoPath)`""
            if ($type -eq "copy") {
                "-c:a copy -map 0:v -c copy"
            } else {
                "-c:a copy -map 0:v -c:v libx264 -preset fast"
            }
            $("$tempFile")
        )

        Invoke-Executable -sExeFile 'ffmpeg' -cArgs $ffmpegArgs.Split(' ')
    }

    # Объединение временных файлов
    $fileListPath = [System.IO.Path]::GetTempFileName()
    $tempFiles | ForEach-Object { "file '$_'" } | Set-Content $fileListPath

    $finalArgs = "-f concat -safe 0 -i `"$fileListPath`" -c copy `"$OutputPath`""
    Invoke-Executable -sExeFile 'ffmpeg' -cArgs $finalArgs.Split(' ')

    # Очистка временных файлов
    Remove-Item $tempFiles -Force
    Remove-Item $fileListPath -Force
}

# Пример использования
$videoFilePath = $videoPath = "y:\.temp\YT_y\Стыдно знать - 20250212 - Горох vs Косицын.mkv"
$intervals = @("-491", "1591-50704", "51149-")
$outputPath = "y:\.temp\YT_y\out\trimmed_video.mkv"

Execute-VideoTrim -videoPath $videoFilePath -Intervals $intervals -OutputPath $outputPath
# $trim = Trim-Video -videoPath $videoFilePath -Intervals $intervals
# $trim | Select-Object frameStart, frameEnd, trimStart, trimEnd, trimType, @{l = "length"; e = { $_.trimEnd - $_.trimStart + 1} } | Format-Table -AutoSize

