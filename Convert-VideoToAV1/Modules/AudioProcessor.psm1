<#
.SYNOPSIS
    Модуль для обработки аудиодорожек в формате Opus
.DESCRIPTION
    Обрабатывает аудиодорожки из видеофайлов: перекодирует в Opus или копирует без перекодирования
    с поддержкой многопоточной обработки и обрезки по времени.
#>

function ConvertTo-OpusAudio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Job,
        [int]$ParallelThreads = $global:Config.Processing.DefaultThreads
    )

    try {
        Write-Log "Начало обработки аудиодорожек" -Severity Information -Category 'Audio'
        
        # Определяем режим копирования аудио (с учетом переопределения параметром)
        $CopyAudioMode = $global:Config.Encoding.Audio.CopyAudio
        
        # Если параметр CopyAudio передан в Job, переопределяем
        if ($Job.ContainsKey('CopyAudioOverride')) {
            $CopyAudioMode = $Job.CopyAudioOverride
            Write-Log "Режим CopyAudio переопределен: $CopyAudioMode" -Severity Information -Category 'Audio'
        }
        
        Write-Log "Режим обработки аудио: $(if ($CopyAudioMode) { 'копирование' } else { 'перекодирование в Opus' })" `
            -Severity Information -Category 'Audio'
        
        # Получаем информацию об аудиодорожках
        $audioTracks = Get-AudioTrackInfo -VideoFilePath $Job.VideoPath
        
        $Job.AudioOutputs = [System.Collections.Generic.List[object]]::new()
        $audioPath = Join-Path -Path $Job.WorkingDir -ChildPath "audio"
        
        if (-not (Test-Path -LiteralPath $audioPath -PathType Container)) {
            New-Item -Path $audioPath -ItemType Directory -Force | Out-Null
        }

        # Подготовка данных для параллельного выполнения
        $tools = $global:VideoTools.Clone()
        $bitrates = $global:Config.Encoding.Audio.Bitrates
        $keepTempAudioFiles = $global:Config.Processing.keepTempAudioFiles
        
        # Используем $CopyAudioMode для параллельного блока
        $copyAudio = $CopyAudioMode

        # Параметры обрезки
        $trimParams = Get-TrimParametersForAudio -Job $Job
        
        # Параллельная обработка
        $audioTracks | ForEach-Object -Parallel {
            $track = $_
            $audioPath = $using:audioPath
            $tools = $using:tools
            $bitrates = $using:bitrates
            $job = $using:Job
            $keepTempAudioFiles = $using:keepTempAudioFiles
            $trimParams = $using:trimParams
            $copyAudio = $using:copyAudio  # Используем локальную переменную

            $outputFileName = if ($copyAudio) {
                # Используем оригинальный кодек для имени файла при копировании
                $extension = Get-AudioExtension -CodecName $track.CodecName
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
                Invoke-AudioTrackProcess `
                    -Job $job `
                    -Track $track `
                    -OutputFile $audioOutput `
                    -Tools $tools `
                    -Bitrates $bitrates `
                    -TrimParams $trimParams `
                    -CopyAudio $copyAudio `
                    -KeepTempFiles $keepTempAudioFiles
            }
            else {
                Write-Verbose "Аудиофайл уже существует: $([IO.Path]::GetFileName($audioOutput))"
            }

            # Возвращаем объект с информацией о дорожке
            Get-AudioTrackResult -Track $track -OutputFile $audioOutput -CopyAudio $copyAudio
            
        } -ThrottleLimit $ParallelThreads | Sort-Object { $_.Index } | ForEach-Object {
            $Job.AudioOutputs.Add($_)
            $Job.TempFiles.Add($_.Path)
        }

        # Анализируем статистику обработки
        $processingStats = Get-AudioProcessingStatistics -AudioOutputs $Job.AudioOutputs
        
        if ($copyAudio) {
            Write-Log "Успешно скопировано $($processingStats.CopiedTracks) аудиодорожек (без перекодировки)" `
                -Severity Success -Category 'Audio'
        } else {
            if ($processingStats.OpusExtracted -gt 0) {
                Write-Log "Извлечено $($processingStats.OpusExtracted) Opus дорожек (без перекодировки)" `
                    -Severity Information -Category 'Audio'
            }
            if ($processingStats.OpusConverted -gt 0) {
                Write-Log "Перекодировано $($processingStats.OpusConverted) дорожек в Opus" `
                    -Severity Information -Category 'Audio'
            }
            Write-Log "Всего обработано $($processingStats.TotalTracks) аудиодорожек" -Severity Success -Category 'Audio'
        }
        
        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке аудио: $_" -Severity Error -Category 'Audio'
        throw
    }
}

function Get-AudioTrackInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VideoFilePath)
    
    try {
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams a `
            -show_entries stream=index,codec_name,channels:stream_tags=language,title:disposition=default,forced,comment `
            -of json $VideoFilePath | ConvertFrom-Json
        
        [Console]::OutputEncoding = $originalEncoding
        
        $id = 0
        $result = $ffprobeOutput.streams | ForEach-Object {
            $id++
            [PSCustomObject]@{
                Index     = $id
                CodecName = $_.codec_name
                Channels  = $_.channels
                Language  = $_.tags.language
                Title     = $_.tags.title
                Default   = $_.disposition.default -eq 1
                Forced    = $_.disposition.forced -eq 1
                Comment   = $_.disposition.comment
            }
        }
        
        Write-Log "Найдено $($result.Count) аудиодорожек" -Severity Information -Category 'Audio'
        return $result
    }
    catch {
        Write-Log "Ошибка при получении информации об аудиодорожках: $_" -Severity Error -Category 'Audio'
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
        
        [bool]$CopyAudioMode = $global:Config.Encoding.Audio.CopyAudio
    )
    
    try {
        $audioTracks = Get-AudioTrackInfo -VideoFilePath $VideoPath
        
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

# ============================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (внутренние)
# ============================================

function Get-TrimParametersForAudio {
    [CmdletBinding()]
    param([hashtable]$Job)
    
    $trimParams = @()
    
    if ($Job.TrimStartSeconds -gt 0) {
        $trimParams += '-ss', $Job.TrimStartSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    
    if ($Job.TrimDurationSeconds -gt 0) {
        $trimParams += '-t', $Job.TrimDurationSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    
    return $trimParams
}

function Get-AudioExtension {
    [CmdletBinding()]
    param([string]$CodecName)
    
    switch ($CodecName) {
        'aac'     { 'm4a' }
        'ac3'     { 'ac3' }
        'eac3'    { 'eac3' }
        'dts'     { 'dts' }
        'truehd'  { 'thd' }
        'flac'    { 'flac' }
        'opus'    { 'opus' }
        'mp3'     { 'mp3' }
        default   { 'mka' }
    }
}

function Invoke-AudioTrackProcess {
    [CmdletBinding()]
    param(
        [hashtable]$Job,
        [object]$Track,
        [string]$OutputFile,
        [hashtable]$Tools,
        [hashtable]$Bitrates,
        [array]$TrimParams,
        [bool]$CopyAudio,
        [bool]$KeepTempFiles
    )
    
    if ($CopyAudio) {
        # Копирование аудио без перекодировки
        $ffmpegArgs = @(
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", $Job.VideoPath
            $TrimParams
            "-map", "0:a:$($Track.Index-1)",
            "-c:a", "copy",  # Копируем без перекодировки
            $OutputFile
        )
        
        & $Tools.FFmpeg $ffmpegArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка копирования аудио (код $LASTEXITCODE)"
        }
        
        Write-Verbose "Аудио скопировано без перекодировки: $($Track.CodecName)"
    } else {
        # ОПТИМИЗАЦИЯ: Если исходный кодек уже Opus, просто извлекаем
        if ($Track.CodecName -eq 'opus') {
            Write-Verbose "Исходная дорожка уже в формате Opus, простое извлечение"
            
            $ffmpegArgs = @(
                "-y", "-hide_banner", "-loglevel", "error",
                "-i", $Job.VideoPath
                $TrimParams
                "-map", "0:a:$($Track.Index-1)",
                "-c:a", "copy",  # Копируем Opus без перекодировки
                $OutputFile
            )
            
            & $Tools.FFmpeg $ffmpegArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Ошибка извлечения Opus (код $LASTEXITCODE)"
            }
            
            Write-Verbose "Opus дорожка успешно извлечена без перекодировки"
        }
        # Для других кодеков делаем полное перекодирование
        else {
            $tempAudio = [IO.Path]::ChangeExtension($OutputFile, "tmp.flac")
            
            try {
                # Извлечение с обрезкой
                $ffmpegArgs = @(
                    "-y", "-hide_banner", "-loglevel", "error",
                    "-i", $Job.VideoPath
                    $TrimParams
                    "-map", "0:a:$($Track.Index-1)",
                    "-c:a", "flac",
                    $tempAudio
                )
                
                & $Tools.FFmpeg $ffmpegArgs
                if ($LASTEXITCODE -ne 0) {
                    throw "Ошибка извлечения аудио (код $LASTEXITCODE)"
                }

                # Конвертация в Opus
                $bitRate = Get-BitrateForChannels -Channels $Track.Channels -Bitrates $Bitrates
                
                $opusArgs = @(
                    "--quiet", "--vbr", "--bitrate", $bitRate
                    $(if ($Track.Title) { "--title", "$($Track.Title)" })
                    $(if ($Track.Language) { "--comment", "language=$($Track.Language)" })
                    $tempAudio, $OutputFile
                )
                
                & $Tools.OpusEnc @opusArgs
                if ($LASTEXITCODE -ne 0) {
                    throw "Ошибка кодирования Opus (код $LASTEXITCODE)"
                }
                
                Write-Verbose "Аудио перекодировано в Opus: $($Track.CodecName) -> Opus"
            }
            finally {
                if (-not $KeepTempFiles -and (Test-Path -LiteralPath $tempAudio)) {
                    Remove-Item -LiteralPath $tempAudio -Force
                }
            }
        }
    }
}

function Get-BitrateForChannels {
    [CmdletBinding()]
    param(
        [int]$Channels,
        [hashtable]$Bitrates
    )
    
    if ($Channels -le 2) {
        return $Bitrates.Stereo
    }
    elseif ($Channels -le 6) {
        return $Bitrates.Surround
    }
    else {
        return $Bitrates.Multi
    }
}

function Get-AudioTrackResult {
    [CmdletBinding()]
    param(
        [object]$Track,
        [string]$OutputFile,
        [bool]$CopyAudio
    )
    
    $codec = if ($CopyAudio) { 
        $Track.CodecName 
    } else { 
        # Для Opus дорожек определяем, был ли это прямой копи или перекодирование
        if ($Track.CodecName -eq 'opus') { 'opus (extracted)' } else { 'opus (converted)' }
    }
    
    return [PSCustomObject]@{
        Path     = $OutputFile
        Index    = $Track.Index
        Language = $Track.Language
        Title    = $Track.Title
        Default  = $Track.Default
        Forced   = $Track.Forced
        Channels = $Track.Channels
        Codec    = $codec
        OriginalCodec = $Track.CodecName
    }
}

function Get-AudioProcessingStatistics {
    [CmdletBinding()]
    param([array]$AudioOutputs)
    
    $totalTracks = $AudioOutputs.Count
    $opusExtracted = ($AudioOutputs | Where-Object { $_.Codec -eq 'opus (extracted)' }).Count
    $opusConverted = ($AudioOutputs | Where-Object { $_.Codec -eq 'opus (converted)' }).Count
    $copiedTracks = ($AudioOutputs | Where-Object { 
        $_.Codec -ne 'opus (extracted)' -and $_.Codec -ne 'opus (converted)' 
    }).Count
    
    return @{
        TotalTracks = $totalTracks
        OpusExtracted = $opusExtracted
        OpusConverted = $opusConverted
        CopiedTracks = $copiedTracks
    }
}

Export-ModuleMember -Function ConvertTo-OpusAudio, Get-AudioProcessingRecommendation