<#
.SYNOPSIS
    Модуль для обработки видео
#>

function ConvertTo-Av1Video {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        $Job.ScriptFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).vpy"
        $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).lwi"
        $Job.VideoOutput = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).ivf"

        if (-not (Test-Path -LiteralPath $Job.VideoOutput -PathType Leaf)) {
            # Определяем, является ли видео HDR/DV
            $isHDR = Test-VideoHDR -VideoPath $Job.VideoPath
            Write-Log "Видео является HDR/DV: $isHDR" -Severity Information -Category 'Video'

            # Выбираем шаблон в зависимости от типа видео
            if ($isHDR) {
                # $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "temp"
                $templateContent = $global:Config.Templates.VapourSynth.HDRtoSDRScript
            } else {
                # $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).lwi"
                $templateContent = $global:Config.Templates.VapourSynth.MainScript
            }
            Write-Log "Cachefile: $($Job.CacheFile)" -Severity Debug -Category 'Video'
            
            Write-Log "Определение параметров обрезки..." -Severity Verbose -Category 'Video'
            if (($null -eq $Job.CropParams) -or `
                    ($null -eq $Job.CropParams.Left -and $null -eq $Job.CropParams.Right -and $null -eq $Job.CropParams.Top -and $null -eq $Job.CropParams.Bottom) ) {
                $Job.CropParams = Get-VideoCropParameters -InputFile $Job.VideoPath
                Write-Log "Параметры обрезки: $($Job.CropParams | Out-String)" -Severity Verbose -Category 'Video'
            } else {
                Write-Log "Параметры обрезки уже заданы: $($Job.CropParams | Out-String)" -Severity Verbose -Category 'Video'
            }
            
            # Генерация скрипта с учетом HDR/DV
            $trimScript = ""
            if ($Job.TrimStartSeconds -gt 0) {
                $startFrame = [math]::Round($Job.TrimStartSeconds * $Job.FrameRate)
                $endFrame = if ($Job.TrimDurationSeconds -gt 0) {
                    [math]::Round(($Job.TrimStartSeconds + $Job.TrimDurationSeconds) * $Job.FrameRate)
                } else { 0 }
                
                if ($endFrame -gt 0) {
                    $trimScript = "clip = core.std.Trim(clip, first=$startFrame, last=$endFrame)`n"
                } else {
                    $trimScript = "clip = core.std.Trim(clip, first=$startFrame)`n"
                }
            }
            
            $scriptContent = $templateContent
            $scriptContent = $scriptContent.Replace('{%VideoPath%}', $Job.VideoPath)
            $scriptContent = $scriptContent.Replace('{%CacheFile%}', $Job.CacheFile)
            $scriptContent = $scriptContent.Replace('{%trimScript%}', $trimScript)
            $scriptContent = $scriptContent.Replace('{%CropParams.Left%}', $Job.CropParams.Left)
            $scriptContent = $scriptContent.Replace('{%CropParams.Right%}', $Job.CropParams.Right)
            $scriptContent = $scriptContent.Replace('{%CropParams.Top%}', $Job.CropParams.Top)
            $scriptContent = $scriptContent.Replace('{%CropParams.Bottom%}', $Job.CropParams.Bottom)

            Write-Log "Создание скрипта VapourSynth (HDR: $isHDR)" -Severity Information -Category 'Video'
            Set-Content -LiteralPath $Job.ScriptFile -Value $scriptContent -Force
            $Job.TempFiles.Add($Job.ScriptFile)
            $Job.TempFiles.Add($Job.CacheFile)
            
            # Получение информации о видео
            $vpyInfo = Get-VideoScriptInfo -ScriptPath $Job.ScriptFile
            $Job.VPYInfo = $vpyInfo
            Write-Log "Информация о видео: $($vpyInfo | Sort-Object -Stable | Out-String)" -Severity Verbose -Category 'Video'

            # Кодирование с выбранным энкодером
            $vspipeArgs = @('-c', 'y4m', $Job.ScriptFile, '-')
            $encArgs = @(
                '--output', $Job.VideoOutput,
                '--input', '-'
            )
            
            # Добавляем параметр --frames с количеством кадров из VPY скрипта
            if ($vpyInfo.Frames -gt 0) {
                $encArgs = @('--frames', $vpyInfo.Frames) + $encArgs
                Write-Log "Добавлен параметр --frames со значением $($vpyInfo.Frames)" -Severity Verbose -Category 'Encoding'
            }
            
            # Добавляем специфичные параметры энкодера
            $encArgs = $Job.EncoderParams + $encArgs
            
            Write-Log "Запуск энкодера: $($Job.EncoderPath) $($encArgs -join ' ')" -Severity Debug -Category 'Encoding'
<# 
            & $global:VideoTools.VSPipe $vspipeArgs | & $Job.EncoderPath $encArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Ошибка кодирования AV1 энкодером $($Job.Encoder) (код $LASTEXITCODE)"
            }
#>
            # Выбор метода пайпа
            $vspipeMethod = $global:Config.Processing.VSPipeMethod
            Write-Log "Используется метод пайпа: $vspipeMethod" -Severity Information -Category 'Encoding'
            
            switch ($vspipeMethod.ToLower()) {
                "ffmpeg" {
                    Invoke-VSPipeWithFFmpeg -ScriptPath $Job.ScriptFile -EncoderPath $Job.EncoderPath -EncoderArgs $encArgs
                }
                "vspipe" {
                    Invoke-VSPipeWithVSPipe -ScriptPath $Job.ScriptFile -EncoderPath $Job.EncoderPath -EncoderArgs $encArgs
                }
                default {
                    Write-Log "Неизвестный метод пайпа: $vspipeMethod. Используется vspipe по умолчанию." -Severity Warning -Category 'Encoding'
                    Invoke-VSPipeWithVSPipe -ScriptPath $Job.ScriptFile -EncoderPath $Job.EncoderPath -EncoderArgs $encArgs
                }
            }

            $Job.TempFiles.Add($Job.VideoOutput)
            Write-Log "Видео успешно закодировано энкодером $($Job.Encoder)" -Severity Success -Category 'Video'
            
            # Сравнение количества кадров VPY скрипта и закодированного видео
            $encodedVideoInfo = Get-VideoStats -VideoFilePath $Job.VideoOutput
            if ($vpyInfo.Frames -eq $encodedVideoInfo.FrameCount) {
                Write-Log "Проверка кадров: OK - VPY скрипт ( $($vpyInfo.Frames) кадров ) = закодированное видео ( $($encodedVideoInfo.FrameCount) кадров )" -Severity Success -Category 'Video'
            } else {
                Write-Log "ПРЕДУПРЕЖДЕНИЕ: Несоответствие количества кадров! VPY скрипт: $($vpyInfo.Frames), закодированное видео: $($encodedVideoInfo.FrameCount)" -Severity Warning -Category 'Video'
            }
        }
        else {
            Write-Log "Пропуск кодирования видео" -Severity Verbose -Category 'Video'
        }

        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке видео энкодером $($Job.Encoder): $_" -Severity Error -Category 'Video'
        throw
    }
}

function Invoke-VSPipeWithVSPipe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$EncoderPath,
        [Parameter(Mandatory)][string[]]$EncoderArgs
    )
    
    try {
        $vspipeArgs = @('-c', 'y4m', $ScriptPath, '-')
        Write-Log "Запуск vspipe: $($global:VideoTools.VSPipe) $($vspipeArgs -join ' ')" -Severity Debug -Category 'Encoding'
        
        & $global:VideoTools.VSPipe @vspipeArgs | & $EncoderPath @EncoderArgs
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка кодирования (код $LASTEXITCODE)"
        }
    }
    catch {
        Write-Log "Ошибка при использовании vspipe: $_" -Severity Error -Category 'Encoding'
        throw
    }
}

function Invoke-VSPipeWithFFmpeg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$EncoderPath,
        [Parameter(Mandatory)][string[]]$EncoderArgs
    )
    
    try {
        # Получаем информацию о скрипте для настройки ffmpeg
        # $vpyInfo = Get-VideoScriptInfo -ScriptPath $ScriptPath
        
        # Формируем аргументы ffmpeg
        # $ffmpegArgs = @(
        #     '-hide_banner',
        #     '-loglevel', 'error',
        #     '-stats',
        #     '-f', 'vapoursynth',
        #     '-i', $ScriptPath,
        #     '-f', 'yuv4mpegpipe',
        #     '-strict -1',
        #     '-'
        # )

        $ffmpegArgs = @(
            "-y", "-hide_banner", "-loglevel", "error", "-nostats"
            '-f', 'vapoursynth',
            "-i", $ScriptPath,
            "-f", "yuv4mpegpipe",
            "-strict", -1,
            "-"
        )
        
        # Добавляем параметры fps, если доступны
        # if ($vpyInfo.FPS) {
        #     $fps = Convert-FpsToDouble -FpsString $vpyInfo.FPS
        #     $ffmpegArgs += '-r', $fps.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        # }
        
        Write-Log "Запуск ffmpeg: $($global:VideoTools.FFmpeg) $($ffmpegArgs -join ' ')" -Severity Debug -Category 'Encoding'
        
        & $global:VideoTools.FFmpeg @ffmpegArgs | & $EncoderPath @EncoderArgs
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка кодирования (код $LASTEXITCODE)"
        }
        
        Write-Log "FFmpeg пайп успешно завершен" -Severity Information -Category 'Encoding'
    }
    catch {
        Write-Log "Ошибка при использовании ffmpeg: $_" -Severity Error -Category 'Encoding'
        throw
    }
}

Export-ModuleMember -Function ConvertTo-Av1Video, Invoke-VSPipeWithVSPipe, Invoke-VSPipeWithFFmpeg