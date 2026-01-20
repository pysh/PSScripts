function ConvertTo-OpusAudio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Job,
        [int]$ParallelThreads = $global:Config.Processing.DefaultThreads
    )

    try {
        Write-Log "Начало обработки аудиодорожек" -Severity Information -Category 'Audio'
        
        # Определяем тип файла для выбора метода извлечения
        $fileExtension = [System.IO.Path]::GetExtension($Job.VideoPath).ToLower()
        $isMP4 = $fileExtension -eq '.mp4'
        
        $audioTracks = if ($isMP4) {
            Get-MP4AudioTrackInfo -VideoFilePath $Job.VideoPath
        } else {
            Get-AudioTrackInfo -VideoFilePath $Job.VideoPath
        }
        
        $Job.AudioOutputs = [System.Collections.Generic.List[object]]::new()
        $audioPath = Join-Path -Path $Job.WorkingDir -ChildPath "audio"
        
        if (-not (Test-Path -LiteralPath $audioPath -PathType Container)) {
            New-Item -Path $audioPath -ItemType Directory -Force | Out-Null
        }

        # Подготовка данных для параллельного выполнения
        $tools = $global:VideoTools.Clone()
        $bitrates = $global:Config.Encoding.Audio.Bitrates
        $keepTempAudioFiles = $global:Config.Processing.keepTempAudioFiles
        $copyAudio = $global:Config.Encoding.Audio.CopyAudio

        # Параметры обрезки
        $trimParams = @()
        if ($Job.TrimStartSeconds -gt 0) {
            $trimParams += '-ss', $Job.TrimStartSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($Job.TrimDurationSeconds -gt 0) {
            $trimParams += '-t', $Job.TrimDurationSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
        }

        # Параллельная обработка
        $audioTracks | ForEach-Object -Parallel {
            function Get-SafeFileName {
                param([string]$FileName)
                if ([string]::IsNullOrWhiteSpace($FileName)) { return [string]::Empty }
                foreach ($char in [IO.Path]::GetInvalidFileNameChars()) {
                    $FileName = $FileName.Replace($char, '_')
                }
                return $FileName
            }

            $track = $_
            $audioPath = $using:audioPath
            $tools = $using:tools
            $bitrates = $using:bitrates
            $job = $using:Job
            $keepTempAudioFiles = $using:keepTempAudioFiles
            $trimParams = $using:trimParams
            $copyAudio = $using:copyAudio

            $outputFileName = if ($copyAudio) {
                # Используем оригинальный кодек для имени файла при копировании
                $extension = switch ($track.CodecName) {
                    'aac' { 'm4a' }
                    'ac3' { 'ac3' }
                    'eac3' { 'eac3' }
                    'dts' { 'dts' }
                    'truehd' { 'thd' }
                    'flac' { 'flac' }
                    'opus' { 'opus' }
                    'mp3' { 'mp3' }
                    default { 'mka' }
                }
                "aID{0}_[{1}]_{{`{2`}}}{3}{4}.{5}" -f 
                ([int]$track.Index).ToString('d2'),
                $track.Language,
                $track.Title,
                ($track.Default ? '+' : '-'),
                ($track.Forced ? 'Forced' : ''),
                $extension
            } else {
                # Используем opus для перекодирования
                "aID{0}_[{1}]_{{`{2`}}}{3}{4}.opus" -f 
                ([int]$track.Index).ToString('d2'),
                $track.Language,
                $track.Title,
                ($track.Default ? '+' : '-'),
                ($track.Forced ? 'Forced' : '')
            }
            
            $outputFileName = Get-SafeFileName -FileName $outputFileName
            $audioOutput = Join-Path -Path $audioPath -ChildPath $outputFileName
            
            if (-not (Test-Path -LiteralPath $audioOutput -PathType Leaf)) {
                if ($copyAudio) {
                    # Копирование аудио без перекодировки
                    $ffmpegArgs = @(
                        "-y", "-hide_banner", "-loglevel", "error",
                        "-i", $job.VideoPath
                        $trimParams
                        "-map", "0:a:$($track.Index-1)",
                        "-c:a", "copy",  # Копируем без перекодировки
                        $audioOutput
                    )
                    
                    & $tools.FFmpeg $ffmpegArgs
                    if ($LASTEXITCODE -ne 0) {
                        throw "Ошибка копирования аудио (код $LASTEXITCODE)"
                    }
                    
                    Write-Verbose "Аудио скопировано без перекодировки: $($track.CodecName)"
                } else {
                    # ОПТИМИЗАЦИЯ: Если исходный кодек уже Opus, просто извлекаем
                    if ($track.CodecName -eq 'opus') {
                        Write-Verbose "Исходная дорожка уже в формате Opus, простое извлечение"
                        
                        $ffmpegArgs = @(
                            "-y", "-hide_banner", "-loglevel", "error",
                            "-i", $job.VideoPath
                            $trimParams
                            "-map", "0:a:$($track.Index-1)",
                            "-c:a", "copy",  # Копируем Opus без перекодировки
                            $audioOutput
                        )
                        
                        & $tools.FFmpeg $ffmpegArgs
                        if ($LASTEXITCODE -ne 0) {
                            throw "Ошибка извлечения Opus (код $LASTEXITCODE)"
                        }
                        
                        Write-Verbose "Opus дорожка успешно извлечена без перекодировки"
                    }
                    # Для других кодеков делаем полное перекодирование
                    else {
                        $tempAudio = [IO.Path]::ChangeExtension($audioOutput, "tmp.flac")
                        
                        try {
                            # Извлечение с обрезкой
                            $ffmpegArgs = @(
                                "-y", "-hide_banner", "-loglevel", "error",
                                "-i", $job.VideoPath
                                $trimParams
                                "-map", "0:a:$($track.Index-1)",
                                "-c:a", "flac",
                                $tempAudio
                            )
                            
                            & $tools.FFmpeg $ffmpegArgs
                            if ($LASTEXITCODE -ne 0) {
                                throw "Ошибка извлечения аудио (код $LASTEXITCODE)"
                            }

                            # Конвертация в Opus
                            $bitRate = if ($track.Channels -le 2) {
                                $bitrates.Stereo
                            }
                            elseif ($track.Channels -le 6) {
                                $bitrates.Surround
                            }
                            else {
                                $bitrates.Multi
                            }
                            
                            $opusArgs = @(
                                "--quiet", "--vbr", "--bitrate", $bitRate
                                $(if ($track.Title) { "--title", "$($track.Title)" })
                                $(if ($track.Language) { "--comment", "language=$($track.Language)" })
                                $tempAudio, $audioOutput
                            )
                            
                            & $tools.OpusEnc @opusArgs
                            if ($LASTEXITCODE -ne 0) {
                                throw "Ошибка кодирования Opus (код $LASTEXITCODE)"
                            }
                            
                            Write-Verbose "Аудио перекодировано в Opus: $($track.CodecName) -> Opus"
                        }
                        finally {
                            if (-not $keepTempAudioFiles -and (Test-Path -LiteralPath $tempAudio)) {
                                Remove-Item -LiteralPath $tempAudio -Force
                            }
                        }
                    }
                }
            }
            else {
                Write-Verbose "Аудиофайл уже существует: $([IO.Path]::GetFileName($audioOutput))"
            }

            # Возвращаем объект
            [PSCustomObject]@{
                Path     = $audioOutput
                Index    = $track.Index
                Language = $track.Language
                Title    = $track.Title
                Default  = $track.Default
                Forced   = $track.Forced
                Channels = $track.Channels
                Codec    = if ($copyAudio) { 
                    $track.CodecName 
                } else { 
                    # Для Opus дорожек определяем, был ли это прямой копи или перекодирование
                    if ($track.CodecName -eq 'opus') { 'opus (extracted)' } else { 'opus (converted)' }
                }
                OriginalCodec = $track.CodecName
            }
        } -ThrottleLimit $ParallelThreads | Sort-Object { $_.Index } | ForEach-Object {
            $Job.AudioOutputs.Add($_)
            $Job.TempFiles.Add($_.Path)
        }

        # Анализируем статистику обработки
        $totalTracks = $Job.AudioOutputs.Count
        $opusExtracted = ($Job.AudioOutputs | Where-Object { $_.Codec -eq 'opus (extracted)' }).Count
        $opusConverted = ($Job.AudioOutputs | Where-Object { $_.Codec -eq 'opus (converted)' }).Count
        $copiedTracks = ($Job.AudioOutputs | Where-Object { $_.Codec -ne 'opus (extracted)' -and $_.Codec -ne 'opus (converted)' }).Count
        
        if ($copyAudio) {
            $action = "скопировано"
            Write-Log "Успешно скопировано $copiedTracks аудиодорожек (без перекодировки)" -Severity Success -Category 'Audio'
        } else {
            if ($opusExtracted -gt 0) {
                Write-Log "Извлечено $opusExtracted Opus дорожек (без перекодировки)" -Severity Information -Category 'Audio'
            }
            if ($opusConverted -gt 0) {
                Write-Log "Перекодировано $opusConverted дорожек в Opus" -Severity Information -Category 'Audio'
            }
            Write-Log "Всего обработано $totalTracks аудиодорожек" -Severity Success -Category 'Audio'
        }
        
        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке аудио: $_" -Severity Error -Category 'Audio'
        throw
    }
}

function Get-AudioProcessingRecommendation {
    <#
    .SYNOPSIS
        Анализирует аудиодорожки и рекомендует оптимальную стратегию обработки
    .EXAMPLE
        Get-AudioProcessingRecommendation -VideoPath "video.mkv"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoPath,
        
        [bool]$CopyAudioMode = $false
    )
    
    try {
        $fileExtension = [System.IO.Path]::GetExtension($VideoPath).ToLower()
        $isMP4 = $fileExtension -eq '.mp4'
        
        $audioTracks = if ($isMP4) {
            Get-MP4AudioTrackInfo -VideoFilePath $VideoPath
        } else {
            Get-AudioTrackInfo -VideoFilePath $VideoPath
        }
        
        $opusCount = ($audioTracks | Where-Object { $_.CodecName -eq 'opus' }).Count
        $totalCount = $audioTracks.Count
        
        $recommendation = @{
            TotalTracks = $totalCount
            OpusTracks = $opusCount
            OtherTracks = $totalCount - $opusCount
            RecommendedAction = if ($CopyAudioMode) { "copy_all" } else { "optimized" }
            Benefits = @()
        }
        
        if ($CopyAudioMode) {
            $recommendation.Benefits += "Копирование всех дорожек без потерь"
            $recommendation.Benefits += "Максимальное качество звука"
        } elseif ($opusCount -eq $totalCount) {
            $recommendation.RecommendedAction = "extract_all"
            $recommendation.Benefits += "Все дорожки уже в Opus - простое извлечение"
            $recommendation.Benefits += "Нет потерь качества"
            $recommendation.Benefits += "Быстрее в 5-10 раз"
        } elseif ($opusCount -gt 0) {
            $recommendation.RecommendedAction = "mixed"
            $recommendation.Benefits += "$opusCount Opus дорожек будут извлечены без перекодировки"
            $recommendation.Benefits += "$($totalCount - $opusCount) дорожек будут перекодированы в Opus"
            $recommendation.Benefits += "Частичная оптимизация скорости"
        } else {
            $recommendation.RecommendedAction = "convert_all"
            $recommendation.Benefits += "Все дорожки будут перекодированы в Opus"
            $recommendation.Benefits += "Оптимальное сжатие"
        }
        
        # Расчет примерного времени экономии
        if ($opusCount -gt 0 -and -not $CopyAudioMode) {
            # Предполагаем, что извлечение Opus в 10 раз быстрее чем перекодирование
            $timeSaved = [math]::Round($opusCount * 0.9, 2) # 90% времени на каждую Opus дорожку
            $recommendation.EstimatedTimeSavings = "${timeSaved}x быстрее для Opus дорожек"
        }
        
        return [PSCustomObject]$recommendation
    }
    catch {
        Write-Verbose "Ошибка анализа аудио: $_"
        return $null
    }
}

Export-ModuleMember -Function ConvertTo-OpusAudio, Get-AudioProcessingRecommendation