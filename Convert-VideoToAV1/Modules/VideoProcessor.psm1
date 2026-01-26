<#
.SYNOPSIS
    Модуль для обработки видео
#>

function Test-X265VpySupport {
    [CmdletBinding()]
    param([string]$X265Path)
    
    try {
        # Запускаем x265 с параметром --help и проверяем наличие --input
        $helpOutput = & $X265Path --help 2>&1
        
        # Проверяем, поддерживает ли x265 параметр --input для VPY файлов
        if ($helpOutput -match "--input" -and $helpOutput -match "y4m") {
            Write-Log "x265 поддерживает прямое чтение VPY файлов" -Severity Information -Category 'Video'
            return $true
        }
        else {
            Write-Log "x265 не поддерживает прямое чтение VPY файлов, будет использоваться vspipe" -Severity Warning -Category 'Video'
            return $false
        }
    }
    catch {
        Write-Log "Ошибка проверки поддержки VPY в x265: $_" -Severity Warning -Category 'Video'
        return $false
    }
}

function Get-VapourSynthTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [hashtable]$Parameters
    )
    
    try {
        # Проверяем, является ли путь абсолютным
        if (-not [System.IO.Path]::IsPathRooted($TemplatePath)) {
            # Если путь относительный, получаем абсолютный путь относительно корня скрипта
            $scriptDir = Split-Path -Parent $PSScriptRoot
            $TemplatePath = Join-Path $scriptDir $TemplatePath
        }
        
        if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
            throw "Файл шаблона VapourSynth не найден: $TemplatePath"
        }
        
        $templateContent = Get-Content -LiteralPath $TemplatePath -Raw
        
        # Заменяем все параметры в шаблоне
        foreach ($key in $Parameters.Keys) {
            $placeholder = "{$key}"
            $value = $Parameters[$key]
            $templateContent = $templateContent -replace [regex]::Escape($placeholder), $value
        }
        
        return $templateContent
    }
    catch {
        Write-Log "Ошибка при загрузке шаблона VapourSynth: $_" -Severity Error -Category 'Video'
        throw
    }
}

function ConvertTo-Av1Video {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Job,
        [string]$TemplatePath  # Добавляем параметр для custom template
    )
    
    try {
        # Проверяем, нужно ли перекодировать видео
        $copyVideo = if ($PSBoundParameters.ContainsKey('CopyVideo')) {
            $CopyVideo
        }
        else {
            $global:Config.Encoding.Video.CopyVideo
        }
        
        if ($copyVideo) {
            # Ремуксинг без перекодирования
            Write-Log "Режим ремуксинга видео без перекодирования" -Severity Information -Category 'Video'
            return Invoke-VideoOnlyRemux -Job $Job
        }
        
        # Определяем тип энкодера
        $isAV1Encoder = $Job.Encoder -match 'Av1Enc|Rav1eEnc|AomAv1Enc'
        $isHEVCEncoder = $Job.Encoder -eq 'x265'
        
        # Создаем файлы в зависимости от энкодера
        if ($isAV1Encoder) {
            $Job.ScriptFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).vpy"
            $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).lwi"
            $Job.VideoOutput = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).ivf"
        }
        elseif ($isHEVCEncoder) {
            $Job.ScriptFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).vpy"
            $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).lwi"
            $Job.VideoOutput = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).hevc"
        }
        else {
            throw "Неподдерживаемый энкодер: $($Job.Encoder)"
        }
        
        if (-not (Test-Path -LiteralPath $Job.VideoOutput -PathType Leaf)) {
            # Определяем, является ли видео HDR/DV
            $isHDR = Test-VideoHDR -VideoPath $Job.VideoPath
            Write-Log "Видео является HDR/DV: $isHDR" -Severity Information -Category 'Video'
            
            # 1. Приоритет: Параметр TemplatePath
            $selectedTemplatePath = $null
            if (-not [string]::IsNullOrEmpty($TemplatePath)) {
                if (Test-Path -LiteralPath $TemplatePath -PathType Leaf) {
                    $selectedTemplatePath = $TemplatePath
                    Write-Log "Используется custom template из параметра: $TemplatePath" -Severity Information -Category 'Video'
                }
                else {
                    Write-Log "Предупреждение: Указанный template не найден: $TemplatePath" -Severity Warning -Category 'Video'
                }
            }
            
            # 2. Приоритет: template.vpy в папке с исходным файлом
            if ([string]::IsNullOrEmpty($selectedTemplatePath)) {
                $videoDir = [System.IO.Path]::GetDirectoryName($Job.VideoPath)
                $localTemplatePath = Join-Path -Path $videoDir -ChildPath "template.vpy"
                
                if (Test-Path -LiteralPath $localTemplatePath -PathType Leaf) {
                    $selectedTemplatePath = $localTemplatePath
                    Write-Log "Используется local template.vpy из папки с видео: $localTemplatePath" -Severity Information -Category 'Video'
                }
            }
            
            # 3. Приоритет: Шаблон из конфига
            if ([string]::IsNullOrEmpty($selectedTemplatePath)) {
                # Выбираем шаблон из конфига в зависимости от типа видео и энкодера
                if ($isHDR) {
                    $selectedTemplatePath = $global:Config.Templates.VapourSynth.HDRtoSDRScript
                }
                else {
                    # Для x265 используем специальный шаблон для HD видео
                    if ($isHEVCEncoder) {
                        $selectedTemplatePath = $global:Config.Templates.VapourSynth.MainHDScript
                    }
                    else {
                        $selectedTemplatePath = $global:Config.Templates.VapourSynth.MainScript
                    }
                }
                Write-Log "Используется шаблон из конфига: $selectedTemplatePath" -Severity Debug -Category 'Video'
                
                # Получаем абсолютный путь к шаблону из конфига
                $scriptDir = Split-Path -Parent $PSScriptRoot
                $selectedTemplatePath = Join-Path $scriptDir $selectedTemplatePath
            }
            
            # Проверяем существование выбранного шаблона
            if (-not (Test-Path -LiteralPath $selectedTemplatePath -PathType Leaf)) {
                throw "Файл шаблона не найден: $selectedTemplatePath"
            }
            
            # Определяем параметры обрезки
            if (($null -eq $Job.CropParams) -or `
                ($null -eq $Job.CropParams.Left -and $null -eq $Job.CropParams.Right -and $null -eq $Job.CropParams.Top -and $null -eq $Job.CropParams.Bottom) ) {
                $Job.CropParams = Get-VideoCropParameters -InputFile $Job.VideoPath
                Write-Log "Параметры обрезки: $($Job.CropParams | Out-String)" -Severity Verbose -Category 'Video'
            }
            else {
                Write-Log "Параметры обрезки уже заданы: $($Job.CropParams | Out-String)" -Severity Verbose -Category 'Video'
            }
            
            # Формируем скрипт обрезки по времени
            $trimScript = ""
            if ($Job.TrimStartSeconds -gt 0) {
                $startFrame = [math]::Round($Job.TrimStartSeconds * $Job.FrameRate)
                $endFrame = if ($Job.TrimDurationSeconds -gt 0) {
                    [math]::Round(($Job.TrimStartSeconds + $Job.TrimDurationSeconds) * $Job.FrameRate)
                }
                else { 0 }
                
                if ($endFrame -gt 0) {
                    $trimScript = "clip = core.std.Trim(clip, first=$startFrame, last=$endFrame)`n"
                }
                else {
                    $trimScript = "clip = core.std.Trim(clip, first=$startFrame)`n"
                }
            }
            
            # Подготавливаем параметры для шаблона
            $templateParams = @{
                VideoPath  = $Job.VideoPath
                CacheFile  = $Job.CacheFile
                trimScript = $trimScript
                CropLeft   = $Job.CropParams.Left
                CropRight  = $Job.CropParams.Right
                CropTop    = $Job.CropParams.Top
                CropBottom = $Job.CropParams.Bottom
            }
            
            # Генерация скрипта из шаблона
            $scriptContent = Get-VapourSynthTemplate -TemplatePath $selectedTemplatePath -Parameters $templateParams
            
            Write-Log "Создание скрипта VapourSynth (Template: $([System.IO.Path]::GetFileName($selectedTemplatePath)))" -Severity Information -Category 'Video'
            Set-Content -LiteralPath $Job.ScriptFile -Value $scriptContent -Force
            $Job.TempFiles.Add($Job.ScriptFile)
            $Job.TempFiles.Add($Job.CacheFile)
            
            # Получение информации о видео
            $vpyInfo = Get-VideoScriptInfo -ScriptPath $Job.ScriptFile
            $Job.VPYInfo = $vpyInfo
            Write-Log "Информация о видео: $($vpyInfo | Sort-Object -Stable | Out-String)" -Severity Verbose -Category 'Video'
            
            # Для x265 проверяем поддержку VPY
            if ($isHEVCEncoder) {
                $supportsVpy = Test-X265VpySupport -X265Path $Job.EncoderPath
                
                if ($supportsVpy) {
                    Write-Log "Используется прямой запуск x265 с VPY файлом" -Severity Information -Category 'Encoding'
                    
                    # Формируем аргументы для x265
                    $x265Args = @(
                        '--input', $Job.ScriptFile,
                        '--output', $Job.VideoOutput
                    ) + $Job.EncoderParams
                    
                    Write-Log "Запуск x265: $($Job.EncoderPath) $($x265Args -join ' ')" -Severity Debug -Category 'Encoding'
                    
                    & $Job.EncoderPath @x265Args
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "Ошибка кодирования x265 (код $LASTEXITCODE)"
                    }
                }
                else {
                    # Используем vspipe как запасной вариант
                    Write-Log "Используется vspipe для передачи данных в x265" -Severity Information -Category 'Encoding'
                    
                    $vspipeArgs = @('-c', 'y4m', $Job.ScriptFile, '-')
                    $x265Args = @(
                        '--output', $Job.VideoOutput,
                        '--input', '-'
                    ) + $Job.EncoderParams
                    
                    Write-Log "Запуск vspipe + x265" -Severity Debug -Category 'Encoding'
                    
                    & $global:VideoTools.VSPipe @vspipeArgs | & $Job.EncoderPath @x265Args
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "Ошибка кодирования x265 через vspipe (код $LASTEXITCODE)"
                    }
                }
            } 
            # Для AV1 энкодеров используем vspipe/ffmpeg
            elseif ($isAV1Encoder) {
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
            }
            
            $Job.TempFiles.Add($Job.VideoOutput)
            Write-Log "Видео успешно закодировано энкодером $($Job.Encoder)" -Severity Success -Category 'Video'
            
            # Сравнение количества кадров VPY скрипта и закодированного видео
            $encodedVideoInfo = Get-VideoStats -VideoFilePath $Job.VideoOutput
            if ($vpyInfo.Frames -eq $encodedVideoInfo.FrameCount) {
                Write-Log "Проверка кадров: OK - VPY скрипт ( $($vpyInfo.Frames) кадров ) = закодированное видео ( $($encodedVideoInfo.FrameCount) кадров )" -Severity Success -Category 'Video'
            }
            else {
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

function Invoke-VideoOnlyRemux {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        Write-Log "Ремуксинг видео без перекодирования" -Severity Information -Category 'Video'
        
        # Создаем временный файл для извлеченного видео
        $Job.VideoOutput = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName)_video.mkv"
        
        # Параметры обрезки
        $trimParams = @()
        if ($Job.TrimStartSeconds -gt 0) {
            $trimParams += '-ss', $Job.TrimStartSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($Job.TrimDurationSeconds -gt 0) {
            $trimParams += '-t', $Job.TrimDurationSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        
        # Параметры обрезки кадров (crop)
        $cropParams = if ($Job.CropParams) {
            if ($Job.CropParams.Left -or $Job.CropParams.Right -or $Job.CropParams.Top -or $Job.CropParams.Bottom) {
                @(
                    '-vf',
                    "crop=w=iw-$($Job.CropParams.Left)-$($Job.CropParams.Right):h=ih-$($Job.CropParams.Top)-$($Job.CropParams.Bottom):x=$($Job.CropParams.Left):y=$($Job.CropParams.Top)"
                )
            }
        }
        
        # Извлекаем видео дорожку без перекодирования
        $ffmpegArgs = @(
            '-y',
            '-hide_banner',
            '-loglevel', 'error',
            '-i', $Job.VideoPath
        )
        
        # Добавляем параметры обрезки по времени
        if ($trimParams.Count -gt 0) {
            $ffmpegArgs += $trimParams
        }
        
        # Добавляем параметры обрезки кадров
        if ($cropParams) {
            $ffmpegArgs += $cropParams
        }
        
        # Копируем только видео дорожку
        $ffmpegArgs += @(
            '-map', '0:v:0',
            '-c:v', 'copy',
            '-an',                    # без аудио
            '-sn',                    # без субтитров
            '-dn',                    # без данных
            $Job.VideoOutput
        )
        
        Write-Log "Извлечение видео: ffmpeg $($ffmpegArgs -join ' ')" -Severity Debug -Category 'Video'
        & $global:VideoTools.FFmpeg @ffmpegArgs
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка извлечения видео (код $LASTEXITCODE)"
        }
        
        $Job.TempFiles.Add($Job.VideoOutput)
        Write-Log "Видео успешно извлечено" -Severity Success -Category 'Video'
        
        return $Job
    }
    catch {
        Write-Log "Ошибка при ремуксинге видео: $_" -Severity Error -Category 'Video'
        throw
    }
}

Export-ModuleMember -Function `
    ConvertTo-Av1Video, `
    Invoke-VSPipeWithVSPipe, `
    Invoke-VSPipeWithFFmpeg, `
    Remux-VideoOnly, `
    Get-VapourSynthTemplate