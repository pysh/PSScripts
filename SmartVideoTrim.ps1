    # Импортируем инструменты из tools.ps1
    # Убедитесь, что путь к tools.ps1 корректен
    . "$(Split-Path -Path $MyInvocation.MyCommand.Path -Parent)\tools.ps1"


# /SmartVideoTrim.ps1

function Get-VideoSmartTrim {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [Parameter(Mandatory = $true)]
        [string[]]$CutIntervals,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [switch]$KeepOriginalMetadata = $false
    )

    # Проверка существования входного файла
    if (-not (Test-Path -LiteralPath $InputFile)) {
        throw "Input file does not exist: '$InputFile'."
    }

    # Получение информации о видео
    $videoStats = Get-VideoStats -VideoPath $InputFile
    $FPS = $videoStats.FPS

    function Get-KeyFrames {
        param ([string]$file)

        try {
            $allFramesOutput = & ffprobe -v error -select_streams v:0 `
                -count_packets `
                -show_entries packet=pts_time,flags `
                -of csv=p=0 "$file"

            $allFrames = $allFramesOutput | ForEach-Object {
                $parts = $_ -split ','
                @{
                    PtsTime = [double]$parts[0]
                    FrameNumber = [math]::Floor([double]$parts[0] * $FPS)
                    IsKeyFrame = $parts[1] -match 'K'
                }
            }

            if ($allFrames.Count -gt 0) {
                $lastFrameIndex = $allFrames.Count - 1
                $allFrames[$lastFrameIndex].IsKeyFrame = $true
            }

            Write-Host ($allFrames | Where-Object { $_.IsKeyFrame }) -ForegroundColor Magenta
            return $allFrames | Where-Object { $_.IsKeyFrame }
        }
        catch {
            throw "Error getting key frames: $_"
        }
    }

    # Получение ключевых кадров
    $keyFrames = Get-KeyFrames -file $InputFile

    # Обработка интервалов
    $results = @()
    foreach ($interval in $CutIntervals) {
        $frames = $interval -split '-'
        $startFrame = [int]$frames[0]
        $endFrame = [int]$frames[1]

        # Найти ближайшие ключевые кадры
        $startKeyFrame = $keyFrames | Where-Object { $_.FrameNumber -ge $startFrame } | Select-Object -First 1
        $endKeyFrame = $keyFrames | Where-Object { $_.FrameNumber -le $endFrame } | Select-Object -Last 1

        # Определение частей для обработки
        if ($startFrame -ne $startKeyFrame.FrameNumber) {
            $results += @{
                StartFrame = $startFrame
                EndFrame = $startKeyFrame.FrameNumber
                Type = 'recode'
            }
        }

        if ($startKeyFrame.FrameNumber -ne $endKeyFrame.FrameNumber) {
            $results += @{
                StartFrame = $startKeyFrame.FrameNumber
                EndFrame = $endKeyFrame.FrameNumber
                Type = 'copy'
            }
        }

        if ($endFrame -ne $endKeyFrame.FrameNumber) {
            $results += @{
                StartFrame = $endKeyFrame.FrameNumber
                EndFrame = $endFrame
                Type = 'recode'
            }
        }
    }

    # Опциональная генерация выходных файлов
    if ($OutputPath) {
        $outputFiles = @()
        foreach ($part in $results) {
            $outputFile = "{0}_trim_{1:000000}_{2:000000}.mkv" -f 
                [System.IO.Path]::GetFileNameWithoutExtension($InputFile),
                $part.StartFrame,
                $part.EndFrame

            $ffmpegArgs = @(
                "-hide_banner"
                # "-nostats"
                "-i", $InputFile,
                "-ss", ($part.StartFrame / $FPS),
                "-to", ($part.EndFrame / $FPS),
                "-c:a copy"
                "-map", "0"
            )

            if ($part.Type -eq 'copy') {
                $ffmpegArgs += "-c:v:0", "copy"
            } elseif ($part.Type -eq 'recode') {
                $ffmpegArgs += "-c:v:0", "libx265"  # Default behavior, can be adjusted if needed
            }

            if ($KeepOriginalMetadata) {
                $ffmpegArgs += "-map_metadata", "0"
            }

            $ffmpegArgs += (Join-Path $OutputPath $outputFile)

            Write-Host "ffmpeg $($ffmpegArgs -join ' ')" -ForegroundColor DarkCyan
            # & ffmpeg @ffmpegArgs
            $outputFiles += $outputFile
        }

        return @{
            Parts = $results
            OutputFiles = $outputFiles
        }
    }

    return $results
}

Clear-Host
Get-VideoSmartTrim `
    -InputFile 'y:\.temp\YT_y\Стыдно знать - 20250212 - Горох vs Косицын.mkv' `
    -CutIntervals @("491-1591", "50704-51149") `
    -OutputPath 'y:\.temp\YT_y\out'
| Select-Object StartFrame, EndFrame, Type