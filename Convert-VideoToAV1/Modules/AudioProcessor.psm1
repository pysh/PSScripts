function ConvertTo-OpusAudio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Job,
        [int]$ParallelThreads = $global:Config.Processing.DefaultThreads
    )

    try {
        Write-Log "Начало обработки аудиодорожек" -Severity Information -Category 'Audio'
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
                    
                    Write-Log "Аудио скопировано без перекодировки: $($track.CodecName)" -Severity Verbose -Category 'Audio'
                } else {
                    # Перекодирование в Opus
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
                    }
                    finally {
                        if (-not $keepTempAudioFiles -and (Test-Path -LiteralPath $tempAudio)) {
                            Remove-Item -LiteralPath $tempAudio -Force
                        }
                    }
                }
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
                Codec    = if ($copyAudio) { $track.CodecName } else { "opus" }
            }
        } -ThrottleLimit $ParallelThreads | Sort-Object { $_.Index } | ForEach-Object {
            $Job.AudioOutputs.Add($_)
            $Job.TempFiles.Add($_.Path)
        }

        $action = if ($copyAudio) { "скопировано" } else { "перекодировано" }
        Write-Log "Успешно $action $($Job.AudioOutputs.Count) аудиодорожек" -Severity Success -Category 'Audio'
        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке аудио: $_" -Severity Error -Category 'Audio'
        throw
    }
}

Export-ModuleMember -Function ConvertTo-OpusAudio