function ConvertTo-OpusAudio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job,
        
        [int]$ParallelThreads = $global:Config.Processing.DefaultThreads
    )

    try {
        Write-Log "Начало обработки аудиодорожек" -Severity Information -Category 'Audio'
        $audioTracks = Get-AudioTrackInfo -VideoFilePath $Job.VideoPath
        $Job.AudioOutputs = [System.Collections.Generic.List[object]]::new()
        $audioPath = Join-Path -Path $Job.WorkingDir -ChildPath "audio"
        
        if (-not (Test-Path -LiteralPath $audioPath -PathType Container)) {
            New-Item -Path $audioPath -ItemType Directory -Force | Out-Null
            Write-Log "Создана директория для аудиофайлов: $audioPath" -Severity Verbose -Category 'Audio'
        }

        # Подготовка данных для параллельного выполнения
        $tools = $global:VideoTools.Clone()
        $bitrates = $global:Config.Encoding.Audio.Bitrates
        $keepTempFiles = $global:Config.Processing.KeepTempFiles

        # Параллельная обработка аудиодорожек
        Write-Log "Начало параллельной конвертации в Opus (потоков: $ParallelThreads)" -Severity Information -Category 'Audio'
        $audioTracks | Sort-Object $_.Index | ForEach-Object -Parallel {
            function Get-SafeFileName {
                [CmdletBinding()]
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
            $keepTempFiles = $using:keepTempFiles

            $opusFileName = (
                "aID{0}_[{1}]_{{`{2`}}}{3}{4}.opus" -f 
                ([int]$track.Index).ToString('d2'),
                $track.Language,
                $track.Title,
                ($track.Default ? '+' : '-'),
                ($track.Forced ? 'Forced' : '')
            )
            # Write-Host "opusFileName: ${opusFileName}"
            $opusFileName = Get-SafeFileName -FileName $opusFileName
            Write-Host "Safe opusFileName: ${opusFileName}"
            $opusOutput = Join-Path -Path $audioPath -ChildPath $opusFileName
            
            if (-not (Test-Path -LiteralPath $opusOutput -PathType Leaf)) {
                $tempAudio = [IO.Path]::ChangeExtension($opusOutput, "tmp.flac")
                
                try {
                    # Извлечение аудиодорожки
                    $ffmpegParams = @(
                        "-y", "-hide_banner", "-loglevel", "error",
                        "-i", $job.VideoPath,
                        "-map", "0:a:$($track.Index-1)",
                        "-c:a", "flac",
                        $tempAudio
                    )
                    
                    & $tools.FFmpeg $ffmpegParams
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
                    
                    $opusParams = @(
                        "--quiet", "--vbr", "--bitrate", $bitRate
                        $(if ($track.Title) { "--title", "$($track.Title)" })
                        $(if ($track.Language) { "--comment", "language=$($track.Language)" })
                        $tempAudio, $opusOutput
                    )
                    
                    & $tools.OpusEnc @opusParams
                    if ($LASTEXITCODE -ne 0) {
                        throw "Ошибка кодирования Opus (код $LASTEXITCODE)"
                    }
                }
                finally {
                    if (-not $keepTempFiles -and (Test-Path -LiteralPath $tempAudio)) {
                        Remove-Item -LiteralPath $tempAudio -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            # Возвращаем объект с полной информацией о дорожке
            [PSCustomObject]@{
                Path     = $opusOutput
                Index    = $track.Index
                Language = $track.Language
                Title    = $track.Title
                Default  = $track.Default
                Forced   = $track.Forced
                Channels = $track.Channels
                Codec    = "opus"
            }
        } -ThrottleLimit $ParallelThreads | Sort-Object { $_.Index } | ForEach-Object {
            $Job.AudioOutputs.Add($_)
            $Job.TempFiles.Add($_.Path)
        }

        Write-Log "Успешно обработано $($Job.AudioOutputs.Count) аудиодорожек" -Severity Success -Category 'Audio'
        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке аудио: $_" -Severity Error -Category 'Audio'
        throw
    }
}

Export-ModuleMember -Function ConvertTo-OpusAudio