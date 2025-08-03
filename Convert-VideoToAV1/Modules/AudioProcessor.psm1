<#
.SYNOPSIS
    Модуль для обработки аудио с параллельной конвертацией
#>

function ConvertTo-OpusAudio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job,
        
        [switch]$KeepTempFiles = $false,
        [int]$ParallelThreads = 10
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

        # Параллельная обработка аудиодорожек
        Write-Log "Начало параллельной конвертации в Opus (потоков: $ParallelThreads)" -Severity Information -Category 'Audio'
        $tracks = $audioTracks | Sort-Object {$_.Index} | ForEach-Object -Parallel {
            $track = $_
            $audioPath = $using:audioPath
            $global:VideoTools = $using:global:VideoTools
            $KeepTempFiles = $using:KeepTempFiles
            $Job = $using:Job

            $opusOutput = Join-Path -Path $audioPath -ChildPath (
                "aID{0}_[{1}]_{{`{2`}}}{3}{4}.opus" -f 
                ([int]$track.Index).ToString('d2'),
                $track.Language,
                $track.Title,
                ($track.Default ? '+' : '-'),
                ($track.Forced ? 'Forced' : '')
            )
            
            if (-not (Test-Path -LiteralPath $opusOutput -PathType Leaf)) {
                $tempAudio = [IO.Path]::ChangeExtension($opusOutput,"tmp.flac")
                
                try {
                    # Извлечение аудиодорожки
                    $ffmpegParams = @(
                        "-y", "-hide_banner", "-loglevel", "error",
                        "-i", $Job.VideoPath,
                        "-map", "0:a:$($track.Index-1)",
                        "-c:a", "flac",
                        $tempAudio
                    )
                    
                    & $global:VideoTools.FFmpeg $ffmpegParams
                    if ($LASTEXITCODE -ne 0) {
                        throw "Ошибка извлечения аудио (код $LASTEXITCODE)"
                    }

                    # Конвертация в Opus
                    $bitRate = switch ($track.Channels) {
                        { $_ -le 2 } { "160"; break }
                        { $_ -le 6 } { "320"; break }
                        default      { "384" }
                    }
                    
                    $opusParams = @(
                        "--quiet", "--vbr", "--bitrate", $bitRate
                        $(if ($track.Title) { "--title", "$($track.Title)" })
                        $(if ($track.Language) { "--comment", "language=$($track.Language)" })
                        $tempAudio, $opusOutput
                    )
                    
                    & $global:VideoTools.OpusEnc @opusParams
                    if ($LASTEXITCODE -ne 0) {
                        throw "Ошибка кодирования Opus (код $LASTEXITCODE)"
                    }
                    Write-Host "Создана аудиодорожка: $_"
                }
                finally {
                    if (-not $KeepTempFiles -and (Test-Path -LiteralPath $tempAudio)) {
                        Remove-Item -LiteralPath $tempAudio -Force -ErrorAction SilentlyContinue
                    }
                }
            } else {
                Write-Host "Аудио существует, пропускаем: $_"
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
        } -ThrottleLimit $ParallelThreads
        $tracks | Sort-Object {$_.Index} | ForEach-Object {
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