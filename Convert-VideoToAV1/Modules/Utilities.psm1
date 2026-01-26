<#
.SYNOPSIS
    Вспомогательные функции для обработки видео
#>

$global:Config = $null
$global:VideoTools = $null

function Convert-FpsToDouble {
    param (
        [string]$FpsString
    )

    if ($FpsString -match '^\d+/\d+$') {
        $numerator, $denominator = $FpsString -split '/'
        return [double]$numerator / [double]$denominator
    } elseif ($FpsString -match '^\d+(\.\d+)?$') {
        return [double]$FpsString
    } else {
        throw "Некорректный формат FPS: $FpsString"
    }
}

function Initialize-Configuration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)
    
    try {
        if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
            throw "Файл конфигурации не найден"
        }
        $global:Config = Import-PowerShellDataFile -Path $ConfigPath
        $global:VideoTools = $global:Config.Tools
        Write-Log "Конфигурация успешно загружена" -Severity Success -Category 'Config'
    }
    catch {
        Write-Log "Ошибка загрузки конфигурации: $_" -Severity Error -Category 'Config'
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
                Index     = $id #$_.index
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

function Get-MP4AudioTrackInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VideoFilePath)
    
    try {
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams a `
            -show_entries stream=index,codec_name,channels:stream_tags=language,title,handler_name:disposition=default,forced `
            -of json $VideoFilePath | ConvertFrom-Json
        
        [Console]::OutputEncoding = $originalEncoding
        
        $result = $ffprobeOutput.streams | ForEach-Object {
            [PSCustomObject]@{
                Index     = $_.index
                CodecName = $_.codec_name
                Channels  = $_.channels
                Language  = $_.tags.language
                Title     = ([string]::IsNullOrWhiteSpace($_.tags.title) ? $_.tags.handler_name : $_.tags.title)
                Default   = $_.disposition.default -eq 1
                Forced    = $_.disposition.forced -eq 1
            }
        }
        
        Write-Log "Найдено $($result.Count) аудиодорожек в MP4" -Severity Information -Category 'Audio'
        return $result
    }
    catch {
        Write-Log "Ошибка при получении информации об аудиодорожках MP4: $_" -Severity Error -Category 'Audio'
        throw
    }
}

function Remove-TemporaryFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        Write-Log "Очистка временных файлов ($($Job.TempFiles.Count) элементов)" -Severity Information -Category 'Cleanup'
        $removedCount = 0
        
        foreach ($file in $Job.TempFiles) {
            try {
                if (Test-Path -LiteralPath $file) {
                    Remove-Item -LiteralPath $file -Force -Recurse -ErrorAction SilentlyContinue
                    $removedCount++
                }
            }
            catch {
                Write-Log "Не удалось удалить временный файл ${file}: $_" -Severity Warning -Category 'Cleanup'
            }
        }
        
        Write-Log "Удалено $removedCount временных файлов" -Severity Information -Category 'Cleanup'
    }
    catch {
        Write-Log "Ошибка при очистке временных файлов: $_" -Severity Error -Category 'Cleanup'
    }
}

function Get-VideoScriptInfo {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$ScriptPath)
    
    try {
        $vspInfo = (& vspipe --info $ScriptPath 2>&1)
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка выполнения vspipe: $vspInfo"
        }

        $infoHash = @{}
        $vspInfo | ForEach-Object {
            if ($_ -match '^(?<name>.*?):\s*(?<value>.*)$') {
                $infoHash[$Matches.name] = $Matches.value
            }
        }

        return [PSCustomObject]$infoHash
    }
    catch {
        Write-Log "Ошибка при получении информации о скрипте VapourSynth: $_" -Severity Error -Category 'Video'
        throw
    }
}

function Get-VideoCropParameters {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$InputFile)
    
    function RoundToNearestMultiple {
        param([int]$Value, [int]$Multiple)
        if ($Multiple -eq 0) { return $Value }
        return [Math]::Round($Value / $Multiple) * $Multiple
    }

    try {
        $tmpScriptFile = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), 'vpy')
        $templatePath = $global:Config.Templates.VapourSynth.AutoCrop
        
        # Получаем абсолютный путь к шаблону
        $scriptDir = Split-Path -Parent $PSScriptRoot
        $templateFullPath = Join-Path $scriptDir $templatePath
        
        if (-not (Test-Path -LiteralPath $templateFullPath -PathType Leaf)) {
            throw "Файл шаблона VapourSynth не найден: $templateFullPath"
        }

        $scriptContent = Get-Content -LiteralPath $templateFullPath -Raw
        $scriptContent = $scriptContent -replace '\{input_file\}', $InputFile
        Set-Content -LiteralPath $tmpScriptFile -Value $scriptContent -Force

        $AutoCropPath = $global:VideoTools.AutoCrop
        $autocropOutput = & $AutoCropPath $tmpScriptFile 2 400 144 144 $global:Config.Processing.AutoCropThreshold 0
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка выполнения AutoCrop (код $LASTEXITCODE)"
        }
        
        $cropLine = $autocropOutput | Select-Object -Last 1
        $cropParams = $cropLine -split ',' | ForEach-Object { [int]$_ }

        return [PSCustomObject]@{
            Left   = RoundToNearestMultiple -Value $cropParams[0] -Multiple $global:Config.Encoding.Video.CropRound
            Top    = RoundToNearestMultiple -Value $cropParams[1] -Multiple $global:Config.Encoding.Video.CropRound
            Right  = RoundToNearestMultiple -Value $cropParams[2] -Multiple $global:Config.Encoding.Video.CropRound
            Bottom = RoundToNearestMultiple -Value $cropParams[3] -Multiple $global:Config.Encoding.Video.CropRound
        }
    }
    catch {
        Write-Log "Ошибка при определении параметров обрезки: $_" -Severity Error -Category 'Video'
        throw
    }
    finally {
        if (Test-Path -LiteralPath $tmpScriptFile) {
            Remove-Item -LiteralPath $tmpScriptFile -ErrorAction SilentlyContinue
        }
    }
}

function Get-VideoFrameRate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VideoPath)
    
    try {
        $fps = $null
        
        # Проверяем расширение файла
        $extension = [System.IO.Path]::GetExtension($VideoPath).ToLower()
        if ($extension -eq '.vpy') {
            # Обработка VapourSynth скриптов
            $vspipeApp = if ($global:VideoTools.VSPipe) { $global:VideoTools.VSPipe } else { 'vspipe' }
            $vspipeArgs = @(
                '-i', $VideoPath,
                '--info'
            )
            $vspipeOutput = & $vspipeApp @vspipeArgs 2>&1
            # Ищем строку с FPS в выводе
            $fpsLine = $vspipeOutput | Where-Object { $_ -match 'FPS:\s*([\d\/]+(?:\.\d+)?)' }
            if ($fpsLine) {
                $fps = [regex]::Match($fpsLine, 'FPS:\s*([\d\/]+(?:\.\d+)?)').Groups[1].Value
            } else {
                throw "Не удалось найти информацию о FPS в выводе vspipe"
            }
        }
        else {
            # Обработка обычных видеофайлов через ffprobe
            $ffprobeApp = if ($global:VideoTools.FFprobe) { $global:VideoTools.FFprobe } else { 'ffprobe' }
            $ffprobeArgs = @(
                '-v', 'error',
                '-select_streams', 'v:0',
                '-show_entries', 'stream=r_frame_rate',
                '-of', 'json',
                $VideoPath
            )
            
            $ffprobeOutput = & $ffprobeApp @ffprobeArgs
            $fpsJson = $ffprobeOutput | ConvertFrom-Json
            $fps = $fpsJson.streams[0].r_frame_rate
        }
        
        # Общая логика обработки FPS
        if ($null -ne $fps) {
            return [double] [Math]::Round((Convert-FpsToDouble -Fps $fps), 2)
        } else {
            throw "Не удалось получить значение FPS"
        }
    }
    catch {
        Write-Log "Ошибка получения framerate: $_" -Severity Error -Category 'UtilModule'
        throw
    }
}

function ConvertTo-Seconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TimeString,
        [double]$FrameRate
    )
    
    try {
        if ($TimeString -match '^(\d+):(\d+):(\d+)(?:\.(\d+))?$') {
            $hours = [int]$Matches[1]
            $minutes = [int]$Matches[2]
            $seconds = [int]$Matches[3]
            $milliseconds = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
            return $hours * 3600 + $minutes * 60 + $seconds + ($milliseconds / 1000)
        }
        elseif ($TimeString -match '^(\d+)(?:\.(\d+))?s$') {
            $seconds = [int]$Matches[1]
            $milliseconds = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
            return $seconds + ($milliseconds / 1000)
        }
        
        throw "Неверный формат времени: $TimeString"
    }
    catch {
        Write-Log "Ошибка конвертации времени: $_" -Severity Error -Category 'Video'
        throw
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug', 'Information', 'Warning', 'Error', 'Success', 'Verbose')]
        [string]$Severity = 'Information',
        [string]$Category,
        [switch]$NoNewLine
    )

    $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss.fff")
    $logSeverity = switch ($Severity) {
        'Success' { 'OK!' }
        'Debug' { 'DBG' }
        'Information' { 'INF' }
        'Verbose' { 'VRB' }
        'Warning' { 'WRN' }
        'Error' { 'ERR' }
        default { '---' }
    }
    
    $color = switch ($Severity) {
        'Success' { 'Green' }
        'Debug' { 'DarkGray' }
        'Information' { 'Cyan' }
        'Verbose' { 'DarkYellow' }
        'Warning' { 'DarkMagenta' }
        'Error' { 'Red' }
        default { 'White' }
    }
    
    $logMessage = "[$timestamp] [$logSeverity]$(if($Category){ " [$Category]" })`t$Message"
    Write-Host $logMessage -ForegroundColor $color -NoNewline:$NoNewLine
}

function Get-VideoQualityMetrics {
    <#
.SYNOPSIS
    Вычисляет метрики качества видео VMAF и XPSNR между искаженным и эталонным видео.
.DESCRIPTION
    Объединяет функциональность VMAF и XPSNR в единый вызов с поддержкой:
    - AviSynth (.avs) и VapourSynth (.vpy) скриптов
    - Обрезки по времени и области (crop)
    - Многопоточной обработки
    - Разных моделей VMAF
    - Настройки порогов и округления
.PARAMETER DistortedPath
    Путь к тестируемому (искаженному) видеофайлу или скрипту (avs/vpy).
.PARAMETER ReferencePath
    Путь к эталонному видеофайлу или скрипту (avs/vpy).
.PARAMETER Metrics
    Какие метрики рассчитывать ('VMAF', 'XPSNR' или 'Both').
.PARAMETER Crop
    Параметры обрезки видео (Left, Right, Top, Bottom).
.PARAMETER TrimStartSeconds
    Начальная точка обрезки в секундах.
.PARAMETER DurationSeconds
    Длительность сегмента для анализа.
.PARAMETER ModelVersion
    Версия модели VMAF ('vmaf_4k_v0.6.1' или 'vmaf_v0.6.1').
.PARAMETER VMAFThreads
    Количество потоков для расчета VMAF.
.PARAMETER Subsample
    Частота субсэмплинга кадров (1 = все кадры).
.PARAMETER VMAFLogPath
    Путь для сохранения детального отчета VMAF.
.PARAMETER VMAFPoolMethod
    Метод агрегации VMAF ('mean' или 'harmonic_mean').
.PARAMETER AviSynthPath
    Путь к AviSynth+ (avs2yuvpipe.exe) для обработки AviSynth скриптов.
    По умолчанию ищет в стандартных путях.
.EXAMPLE
    Get-VideoQualityMetrics -ReferencePath "original.vpy" -DistortedPath "encoded.mp4" -Metrics Both
.EXAMPLE
    Get-VideoQualityMetrics -ReferencePath "original.avs" -DistortedPath "encoded.mkv" -Metrics VMAF
.EXAMPLE
    Get-VideoQualityMetrics -ReferencePath "reference.mkv" -DistortedPath "distorted.vpy" -Metrics XPSNR -VMAFThreads 8
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ $(($_ -match '\.(avs|vpy|mp4|mkv)$') -and (Test-Path -LiteralPath $_ -PathType Leaf)) })]
        [string]$DistortedPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ $(($_ -match '\.(avs|vpy|mp4|mkv)$') -and (Test-Path -LiteralPath $_ -PathType Leaf)) })]
        [string]$ReferencePath,

        [ValidateSet('VMAF', 'XPSNR', 'Both')]
        [string]$Metrics = 'VMAF',

        [PSCustomObject]$Crop = @{
            Left          = 0
            Right         = 0
            Top           = 0
            Bottom        = 0
            CropDistVideo = $false
        },

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TrimStartSeconds = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$DurationSeconds = 0,

        [string]$ModelVersion = 'vmaf_4k_v0.6.1',

        [ValidateRange(1, 64)]
        [int]$VMAFThreads = [Environment]::ProcessorCount,

        [ValidateRange(1, 100)]
        [int]$Subsample = 1,

        [string]$VMAFLogPath,

        [ValidateSet('mean', 'harmonic_mean')]
        [string]$VMAFPoolMethod = 'mean',

        [string]$AviSynthPath = $null
    )

    # Функция для определения типа файла
function Get-FileType {
    param([string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    switch ($extension) {
        '.vpy' { return 'VapourSynth' }
        '.avs' { return 'AviSynth' }
        default { return 'Video' }
    }
}

    # Функция для получения FPS из скрипта или видео
    function Get-ScriptFrameRate {
        param([string]$ScriptPath, [string]$ScriptType)
        
        try {
            if ($ScriptType -eq 'VapourSynth') {
                $vspipeApp = if ($global:VideoTools.VSPipe) { $global:VideoTools.VSPipe } else { 'vspipe' }
                $vspipeArgs = @('-i', $ScriptPath, '--info')
                $vspipeOutput = & $vspipeApp @vspipeArgs 2>&1
                
                $fpsLine = $vspipeOutput | Where-Object { $_ -match 'FPS:\s*([\d\/]+(?:\.\d+)?)' }
                if ($fpsLine) {
                    $fps = [regex]::Match($fpsLine, 'FPS:\s*([\d\/]+(?:\.\d+)?)').Groups[1].Value
                    return [double] [Math]::Round((Convert-FpsToDouble -FpsString $fps), 2)
                }
            }
            elseif ($ScriptType -eq 'AviSynth') {
                # Для AviSynth используем FFmpeg для получения FPS
                $ffprobeApp = if ($global:VideoTools.FFprobe) { $global:VideoTools.FFprobe } else { 'ffprobe' }
                $ffprobeArgs = @(
                    '-v', 'error',
                    '-f', 'avisynth',
                    '-i', $ScriptPath,
                    '-show_entries', 'stream=r_frame_rate',
                    '-of', 'json'
                )
                
                $ffprobeOutput = & $ffprobeApp @ffprobeArgs
                $fpsJson = $ffprobeOutput | ConvertFrom-Json
                if ($fpsJson.streams -and $fpsJson.streams[0].r_frame_rate) {
                    $fps = $fpsJson.streams[0].r_frame_rate
                    return [double] [Math]::Round((Convert-FpsToDouble -FpsString $fps), 2)
                }
            }
        }
        catch {
            Write-Verbose "Не удалось получить FPS из скрипта ${ScriptPath}: $_"
        }
        
        # Возвращаем значение по умолчанию
        return 24.0
    }

    # Определяем типы файлов
    $distortedType = Get-FileType -Path $DistortedPath
    $referenceType = Get-FileType -Path $ReferencePath
    
    Write-Verbose "Distorted type: $distortedType, Reference type: $referenceType"

    # Получаем FPS для каждого файла
    $videoRefFrameRate = if ($referenceType -eq 'Video') {
        Get-VideoFrameRate -VideoPath $ReferencePath
    } else {
        Get-ScriptFrameRate -ScriptPath $ReferencePath -ScriptType $referenceType
    }

    $videoDistFrameRate = if ($distortedType -eq 'Video') {
        Get-VideoFrameRate -VideoPath $DistortedPath
    } else {
        Get-ScriptFrameRate -ScriptPath $DistortedPath -ScriptType $distortedType
    }

    # Базовые фильтры для временных меток
    $baseFilters = "settb=AVTB,setpts=PTS-STARTPTS"

    # Собираем фильтры обрезки
    $cropFilterReference = if ($Crop.Left -or $Crop.Right -or $Crop.Top -or $Crop.Bottom) {
        "crop=w=iw-$($Crop.Left)-$($Crop.Right):h=ih-$($Crop.Top)-$($Crop.Bottom):x=$($Crop.Left):y=$($Crop.Top)"
    }
    
    if ($Crop.CropDistVideo) { 
        $cropFilterDistortion = $cropFilterReference 
    }

    # Фильтры обрезки по времени
    $trimFilter = if ($TrimStartSeconds -gt 0 -or $DurationSeconds -gt 0) {
        "trim=start=${TrimStartSeconds}:duration=${DurationSeconds}"
    }

    # Комбинируем все фильтры
    $commonFilters = (@($trimFilter, $baseFilters) -join ',').Trim(',')

    # Результаты
    $results = @{
        VMAF  = $null
        XPSNR = $null
    }

    # Функция для формирования входных параметров в зависимости от типа файла
    function Get-InputArgs {
        param([string]$Path, [string]$FileType, [double]$FrameRate)
        
        $argsList = @()
        
        switch ($FileType) {
            'VapourSynth' {
                $argsList += '-f', 'vapoursynth'
                $argsList += '-r', ($FrameRate.ToString().Replace(',', '.'))
            }
            'AviSynth' {
                $argsList += '-f', 'avisynth'
            }
            default {
                # Для видеофайлов ничего не добавляем
            }
        }
        
        $argsList += '-i', $Path
        return $argsList
    }

    # Общий фильтр для обоих потоков
    $filterChain = @(
        "[0:v]$(if($cropFilterDistortion) { "${cropFilterDistortion}," })$commonFilters[dist];",
        "[1:v]$(if($cropFilterReference) { "${cropFilterReference}," })$commonFilters[ref];"
    ) -join ''

    # Расчет VMAF
    if ($Metrics -in ('Both', 'VMAF')) {
        $vmafParams = @(
            "eof_action=endall",
            "n_threads=$VMAFThreads",
            "n_subsample=$Subsample",
            "model=version=$ModelVersion",
            "pool=$VMAFPoolMethod"
        )
        
        if ($VMAFLogPath) {
            $vmafParams += "log_path='$($VMAFLogPath.Replace('\', '\\'))'"
            $vmafParams += "log_fmt=json"
        }

        $vmafFilter = "[dist][ref]libvmaf=$($vmafParams -join ':')"
        
        # Формируем аргументы FFmpeg
        $ffmpegArgs = @(
            "-hide_banner", "-y", "-nostats"
        )
        
        # Добавляем параметры для искаженного видео
        $ffmpegArgs += Get-InputArgs -Path $DistortedPath -FileType $distortedType -FrameRate $videoDistFrameRate
        
        # Добавляем параметры для эталонного видео
        $ffmpegArgs += Get-InputArgs -Path $ReferencePath -FileType $referenceType -FrameRate $videoRefFrameRate
        
        # Добавляем фильтры и выход
        $ffmpegArgs += @(
            "-filter_complex", "${filterChain}${vmafFilter}",
            "-f", "null", "-"
        )

        Write-Verbose "Calculating VMAF: ffmpeg $($ffmpegArgs -join ' ')"
        $timerVMAF = [System.Diagnostics.Stopwatch]::StartNew()
        $output = & ffmpeg $ffmpegArgs 2>&1
        $timerVMAF.Stop()

        if ($output -join '`n' -match [regex]'(?m).*VMAF score: (?<vmaf>\d+\.+\d+).*') {
            $results.VMAF = [double]$Matches.vmaf
            Write-Verbose "VMAF calculation successful: $($results.VMAF)"
        }
        else {
            Write-Warning "VMAF calculation failed. Output: $($output -join "`n")"
            # Попробуем найти VMAF в другом формате вывода
            if ($output -join '`n' -match [regex]'VMAF score:\s*(\d+\.\d+)') {
                $results.VMAF = [double]$Matches[1]
                Write-Verbose "VMAF found (alternative pattern): $($results.VMAF)"
            }
            else {
                $results.VMAF = $null
            }
        }
    }

    # Расчет XPSNR
    if ($Metrics -in ('Both', 'XPSNR')) {
        $xpsnrFilter = "[dist][ref]xpsnr=eof_action=endall"
        
        # Формируем аргументы FFmpeg
        $ffmpegArgs = @(
            "-hide_banner", "-y", "-nostats"
        )
        
        # Добавляем параметры для искаженного видео
        $ffmpegArgs += Get-InputArgs -Path $DistortedPath -FileType $distortedType -FrameRate $videoDistFrameRate
        
        # Добавляем параметры для эталонного видео
        $ffmpegArgs += Get-InputArgs -Path $ReferencePath -FileType $referenceType -FrameRate $videoRefFrameRate
        
        # Добавляем фильтры и выход
        $ffmpegArgs += @(
            "-filter_complex", "${filterChain}${xpsnrFilter}",
            "-f", "null", "-"
        )

        Write-Verbose "Calculating XPSNR: ffmpeg $($ffmpegArgs -join ' ')"
        $timerXPSNR = [System.Diagnostics.Stopwatch]::StartNew()
        $output = & ffmpeg $ffmpegArgs 2>&1
        $timerXPSNR.Stop()

        # Ищем XPSNR в разных форматах вывода
        $xpsnrFound = $false
        
        # Формат 1: "XPSNR... y: XX.XX u: XX.XX v: XX.XX"
        if ($output -join '`n' -match [regex]'(?m)XPSNR.*y:\s*(?<y>\d+\.\d+).*u:\s*(?<u>\d+\.\d+).*v:\s*(?<v>\d+\.\d+)') {
            $results.XPSNR = @{
                Y    = [double]$Matches['y']
                U    = [double]$Matches['u']
                V    = [double]$Matches['v']
                MIN  = (([double]$Matches['y'], [double]$Matches['u'], [double]$Matches['v']) | Measure-Object -Minimum).Minimum
                AVG  = ([double]$Matches['y'] + [double]$Matches['u'] + [double]$Matches['v']) / 3
                WSUM = (4 * [double]$Matches['y'] + [double]$Matches['u'] + [double]$Matches['v']) / 6
            }
            $xpsnrFound = $true
            Write-Verbose "XPSNR calculation successful (pattern 1)"
        }
        # Формат 2: "PSNR y:XX.XX u:XX.XX v:XX.XX *"
        elseif ($output -join '`n' -match [regex]'(?m)PSNR.*y:\s*(?<y>\d+\.\d+).*u:\s*(?<u>\d+\.\d+).*v:\s*(?<v>\d+\.\d+)') {
            $results.XPSNR = @{
                Y    = [double]$Matches['y']
                U    = [double]$Matches['u']
                V    = [double]$Matches['v']
                MIN  = (([double]$Matches['y'], [double]$Matches['u'], [double]$Matches['v']) | Measure-Object -Minimum).Minimum
                AVG  = ([double]$Matches['y'] + [double]$Matches['u'] + [double]$Matches['v']) / 3
                WSUM = (4 * [double]$Matches['y'] + [double]$Matches['u'] + [double]$Matches['v']) / 6
            }
            $xpsnrFound = $true
            Write-Verbose "XPSNR calculation successful (pattern 2)"
        }
        
        if (-not $xpsnrFound) {
            Write-Warning "XPSNR calculation failed. Output: $($output -join "`n")"
            $results.XPSNR = $null
        }
    }

    # Добавляем информацию о параметрах
    $results['Parameters'] = @{
        DistortedType  = $distortedType
        ReferenceType  = $referenceType
        DistortedFPS   = $videoDistFrameRate
        ReferenceFPS   = $videoRefFrameRate
        Crop           = $Crop
        TimeRange      = if ($DurationSeconds -gt 0) {
            "$TrimStartSeconds-$($TrimStartSeconds+$DurationSeconds)s"
        }
        else { "Full duration" }
        ModelVersion   = $ModelVersion
        VMAFTimer      = $timerVMAF
        XPSNRTimer     = $timerXPSNR
    }

    return [PSCustomObject]$results
}

function Get-SafeFileName {
    [CmdletBinding()]
    param([string]$FileName)
    
    if ([string]::IsNullOrWhiteSpace($FileName)) { return [string]::Empty }
    foreach ($char in [IO.Path]::GetInvalidFileNameChars()) {
        $FileName = $FileName.Replace($char, '_')
    }
    return $FileName
}

function Get-EncoderPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EncoderName)
    
    try {
        if (-not $global:Config.Encoding.AvailableEncoders.ContainsKey($EncoderName)) {
            throw "Энкодер '$EncoderName' не найден в конфигурации"
        }
        
        $encoderPathRef = $global:Config.Encoding.AvailableEncoders[$EncoderName]
        $pathParts = $encoderPathRef -split '\.'
        
        $current = $global:Config
        foreach ($part in $pathParts) {
            $current = $current[$part]
        }
        
        if (-not (Test-Path -LiteralPath $current -PathType Leaf)) {
            throw "Файл энкодера не найден: $current"
        }
        
        return $current
    }
    catch {
        Write-Log "Ошибка получения пути к энкодеру '$EncoderName': $_" -Severity Error -Category 'Config'
        throw
    }
}

function Get-EncoderParams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EncoderName,
        [hashtable]$EncoderConfig
    )
    
    $baseParams = @()
    
    if ($EncoderConfig.BaseArgs) {
        $baseParams += $EncoderConfig.BaseArgs
    }
    
    # Определяем базовое имя энкодера для свитча
    $baseEncoderName = if ($EncoderName -match '^(SvtAv1EncESS|SvtAv1Enc|SvtAv1EncHDR|SvtAv1EncPSYEX)') {
        $matches[1]
    } elseif ($EncoderName -match '^(x265|Rav1eEnc|AomAv1Enc)') {
        $matches[1]
    } else {
        $EncoderName
    }

    # Добавляем специфичные параметры для каждого энкодера
    switch ($baseEncoderName) {
        "x265" {
            $baseParams += @('--crf', $EncoderConfig.Quality)
            $baseParams += @('--preset', $EncoderConfig.Preset)
        }
        "SvtAv1Enc" {
            $baseParams += @('--crf', $EncoderConfig.Quality)
            $baseParams += @('--preset', $EncoderConfig.Preset)
        }
        "SvtAv1EncESS" {
            if ($EncoderConfig.Quality -and (-not ([string]::IsNullOrWhiteSpace($EncoderConfig.Quality)))) {
                $baseParams += @('--quality', $EncoderConfig.Quality)
            }
            if ($EncoderConfig.Speed -and (-not ([string]::IsNullOrWhiteSpace($EncoderConfig.Speed)))) {
                $baseParams += @('--speed', $EncoderConfig.Speed)
            }
        }
        "SvtAv1EncHDR" {
            $baseParams += @('--crf', $EncoderConfig.Quality)
            $baseParams += @('--preset', $EncoderConfig.Preset)
        }
        "SvtAv1EncPSYEX" {
            $baseParams += @('--crf', $EncoderConfig.Quality)
            $baseParams += @('--preset', $EncoderConfig.Preset)
        }
        "Rav1eEnc" {
            $baseParams += @('--quantizer', $EncoderConfig.Quality)
            $baseParams += @('--speed', $EncoderConfig.Speed)
        }
        "AomAv1Enc" {
            $baseParams += @('--cq-level', $EncoderConfig.Quality)
            $baseParams += @('--cpu-used', $EncoderConfig.CpuUsed)
        }
    }
    
    # Добавляем дополнительные параметры
    if ($global:Config.Encoding.Video.XtraParams) {
        $baseParams += $global:Config.Encoding.Video.XtraParams
    }
    return $baseParams
}

function Test-EncoderPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EncoderName,
        [switch]$VerboseInfo
    )
    
    try {
        $availableEncoders = $global:Config.Encoding.AvailableEncoders.Keys
        $presets = $global:Config.Encoding.Video.EncoderParams.Keys
        
        $result = @{
            EncoderName = $EncoderName
            IsAvailableEncoder = $EncoderName -in $availableEncoders
            IsPreset = $EncoderName -in $presets
            HasConfig = $global:Config.Encoding.Video.EncoderParams.ContainsKey($EncoderName)
            BaseEncoder = $null
            Config = $null
        }
        
        if ($result.HasConfig) {
            $result.Config = $global:Config.Encoding.Video.EncoderParams[$EncoderName]
            
            # Определяем базовый энкодер
            if ($EncoderName -match '^(SvtAv1EncESS|SvtAv1Enc|SvtAv1EncHDR|SvtAv1EncPSYEX)') {
                $result.BaseEncoder = $matches[1]
            }
        }
        
        if ($VerboseInfo) {
            Write-Log "Проверка пресета '$EncoderName':" -Severity Information
            Write-Log "  Доступный энкодер: $($result.IsAvailableEncoder)" -Severity Information
            Write-Log "  Пресет: $($result.IsPreset)" -Severity Information
            Write-Log "  Есть конфиг: $($result.HasConfig)" -Severity Information
            Write-Log "  Базовый энкодер: $($result.BaseEncoder)" -Severity Information
        }
        
        return [PSCustomObject]$result
    }
    catch {
        Write-Log "Ошибка проверки пресета: $_" -Severity Error
        throw
    }
}

function Get-EncoderConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EncoderName)
    
    try {
        # Проверяем наличие пресета в конфиге
        if (-not $global:Config.Encoding.Video.EncoderParams.ContainsKey($EncoderName)) {
            Write-Log "Конфигурация для энкодера '$EncoderName' не найдена. Поиск пресетов..." -Severity Warning -Category 'Config'
            
            # Ищем пресеты по шаблону (например, SvtAv1EncESS_*)
            $presetPattern = $EncoderName -replace '_.*$', '*'
            $matchingPresets = $global:Config.Encoding.Video.EncoderParams.Keys | Where-Object { $_ -like $presetPattern }
            
            if ($matchingPresets.Count -eq 0) {
                throw "Конфигурация для энкодера '$EncoderName' не найдена и подходящих пресетов не обнаружено"
            }
            
            # Используем первый найденный пресет
            $fallbackEncoder = $matchingPresets[0]
            Write-Log "Используется пресет '$fallbackEncoder' для '$EncoderName'" -Severity Information -Category 'Config'
            return $global:Config.Encoding.Video.EncoderParams[$fallbackEncoder]
        }
        
        return $global:Config.Encoding.Video.EncoderParams[$EncoderName]
    }
    catch {
        Write-Log "Ошибка получения конфигурации энкодера '$EncoderName': $_" -Severity Error -Category 'Config'
        throw
    }
}

<# function Get-VideoFrameRate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VideoPath)
    
    try {
        $fps = $null
        
        # Проверяем расширение файла
        $extension = [System.IO.Path]::GetExtension($VideoPath).ToLower()
        
        switch ($extension) {
            '.vpy' {
                # Обработка VapourSynth скриптов
                $vspipeApp = if ($global:VideoTools.VSPipe) { $global:VideoTools.VSPipe } else { 'vspipe' }
                $vspipeArgs = @('-i', $VideoPath, '--info')
                $vspipeOutput = & $vspipeApp @vspipeArgs 2>&1
                
                $fpsLine = $vspipeOutput | Where-Object { $_ -match 'FPS:\s*([\d\/]+(?:\.\d+)?)' }
                if ($fpsLine) {
                    $fps = [regex]::Match($fpsLine, 'FPS:\s*([\d\/]+(?:\.\d+)?)').Groups[1].Value
                } else {
                    throw "Не удалось найти информацию о FPS в выводе vspipe"
                }
            }
            '.avs' {
                # Обработка AviSynth скриптов через ffprobe
                $ffprobeApp = if ($global:VideoTools.FFprobe) { $global:VideoTools.FFprobe } else { 'ffprobe' }
                $ffprobeArgs = @(
                    '-v', 'error',
                    '-f', 'avisynth',
                    '-select_streams', 'v:0',
                    '-show_entries', 'stream=r_frame_rate',
                    '-of', 'json',
                    $VideoPath
                )
                
                $ffprobeOutput = & $ffprobeApp @ffprobeArgs
                $fpsJson = $ffprobeOutput | ConvertFrom-Json
                if ($fpsJson.streams -and $fpsJson.streams[0].r_frame_rate) {
                    $fps = $fpsJson.streams[0].r_frame_rate
                } else {
                    throw "Не удалось получить FPS из AviSynth скрипта"
                }
            }
            default {
                # Обработка обычных видеофайлов через ffprobe
                $ffprobeApp = if ($global:VideoTools.FFprobe) { $global:VideoTools.FFprobe } else { 'ffprobe' }
                $ffprobeArgs = @(
                    '-v', 'error',
                    '-select_streams', 'v:0',
                    '-show_entries', 'stream=r_frame_rate',
                    '-of', 'json',
                    $VideoPath
                )
                
                $ffprobeOutput = & $ffprobeApp @ffprobeArgs
                $fpsJson = $ffprobeOutput | ConvertFrom-Json
                $fps = $fpsJson.streams[0].r_frame_rate
            }
        }
        
        # Общая логика обработки FPS
        if ($null -ne $fps) {
            return [double] [Math]::Round((Convert-FpsToDouble -Fps $fps), 2)
        } else {
            throw "Не удалось получить значение FPS"
        }
    }
    catch {
        Write-Log "Ошибка получения framerate: $_" -Severity Error -Category 'UtilModule'
        throw
    }
}
#>

<# function Test-AviSynthSupport {
    [CmdletBinding()]
    param()
    
    try {
        # Проверяем, поддерживает ли FFmpeg AviSynth
        $ffmpegOutput = & ffmpeg -formats 2>&1
        if ($ffmpegOutput -match "avisynth") {
            Write-Verbose "FFmpeg поддерживает AviSynth"
            return $true
        }
        
        # Проверяем наличие avs2yuvpipe как альтернативы
        if (Get-Command avs2yuvpipe.exe -ErrorAction SilentlyContinue) {
            Write-Verbose "Найден avs2yuvpipe.exe для работы с AviSynth"
            return $true
        }
        
        Write-Warning "FFmpeg не поддерживает AviSynth и avs2yuvpipe не найден"
        return $false
    }
    catch {
        Write-Verbose "Ошибка проверки поддержки AviSynth: $_"
        return $false
    }
}
#>

<# function Get-AviSynthInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptPath)
    
    try {
        if (-not (Test-AviSynthSupport)) {
            throw "AviSynth не поддерживается в системе"
        }
        
        # Используем FFmpeg для получения информации о AviSynth скрипте
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -f avisynth `
            -show_entries stream=width,height,r_frame_rate,codec_name `
            -of json $ScriptPath | ConvertFrom-Json
        
        if ($ffprobeOutput.streams) {
            return [PSCustomObject]@{
                Width     = $ffprobeOutput.streams[0].width
                Height    = $ffprobeOutput.streams[0].height
                FrameRate = $ffprobeOutput.streams[0].r_frame_rate
                Codec     = $ffprobeOutput.streams[0].codec_name
            }
        }
    }
    catch {
        Write-Verbose "Ошибка получения информации о AviSynth скрипте: $_"
        return $null
    }
}
#>


function Test-VideoHDR {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VideoPath)
    
    try {
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams v:0 `
            -show_entries stream=color_primaries,color_transfer,color_space,side_data_list `
            -of json $VideoPath | ConvertFrom-Json
        
        $stream = $ffprobeOutput.streams[0]
        
        # Проверяем цветовые характеристики HDR
        $isHDR = $false
        
        # Проверяем transfer characteristics
        if ($stream.color_transfer -in ('smpte2084', 'arib-std-b67')) {
            $isHDR = $true
        }
        
        # Проверяем color primaries
        if ($stream.color_primaries -eq 'bt2020') {
            $isHDR = $true
        }
        
        # Проверяем Dolby Vision side data
        if ($stream.side_data_list) {
            foreach ($sideData in $stream.side_data_list) {
                if ($sideData.side_data_type -eq 'DOVI configuration record') {
                    $isHDR = $true
                    Write-Log "Обнаружен Dolby Vision" -Severity Information -Category 'Video'
                    break
                }
            }
        }
        
        return $isHDR
    }
    catch {
        Write-Log "Ошибка при определении HDR/DV: $_" -Severity Warning -Category 'Video'
        return $false
    }
}

# Хеш-таблицы для преобразования цветовых параметров
$script:ColorRangeMappings = @{
    'tv' = @{
        'aomenc' = @{ param = '--color-range='; value = '0' };
        'x264'   = @{ param = '--range='; value = '0' };
        'x265'   = @{ param = '--range'; value = 'limited' };
        'svt'    = @{ param = '--color-range'; value = '0' } 
    }
    'pc' = @{
        'aomenc' = @{ param = '--color-range='; value = '1' };
        'x264'   = @{ param = '--range='; value = '1' };
        'x265'   = @{ param = '--range'; value = 'full' };
        'svt'    = @{ param = '--color-range'; value = '1' } 
    }
}

$script:ColorPrimariesMappings = @{
    'bt709'     = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt709' };
        'x264'   = @{ param = '--colorprim='; value = '1' };
        'x265'   = @{ param = '--colorprim'; value = 'bt709' };
        'svt'    = @{ param = '--color-primaries'; value = '1' } 
    }
    'bt470bg'   = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt470bg' };
        'x264'   = @{ param = '--colorprim='; value = '5' };
        'x265'   = @{ param = '--colorprim'; value = 'bt470bg' };
        'svt'    = @{ param = '--color-primaries'; value = '5' } 
    }
    'bt470m'    = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt470m' };
        'x264'   = @{ param = '--colorprim='; value = '4' };
        'x265'   = @{ param = '--colorprim'; value = 'bt470m' };
        'svt'    = @{ param = '--color-primaries'; value = '4' } 
    }
    'bt2020'    = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt2020' };
        'x264'   = @{ param = '--colorprim='; value = '9' };
        'x265'   = @{ param = '--colorprim'; value = 'bt2020' };
        'svt'    = @{ param = '--color-primaries'; value = '9' } 
    }
    'smpte170m' = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'smpte170' };
        'x264'   = @{ param = '--colorprim='; value = '6' };
        'x265'   = @{ param = '--colorprim'; value = 'smpte170m' };
        'svt'    = @{ param = '--color-primaries'; value = '6' } 
    }
    'smpte240m' = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'smpte240' };
        'x264'   = @{ param = '--colorprim='; value = '7' };
        'x265'   = @{ param = '--colorprim'; value = 'smpte240m' };
        'svt'    = @{ param = '--color-primaries'; value = '7' } 
    }
    'film'      = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'film' };
        'x264'   = @{ param = '--colorprim='; value = '8' };
        'x265'   = @{ param = '--colorprim'; value = 'film' };
        'svt'    = @{ param = '--color-primaries'; value = '8' } 
    }
}

$script:TransferMappings = @{
    'bt709'     = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt709' };
        'x264'   = @{ param = '--transfer='; value = '1' };
        'x265'   = @{ param = '--transfer'; value = 'bt709' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '1' } 
    }
    'bt470bg'   = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt470bg' };
        'x264'   = @{ param = '--transfer='; value = '5' };
        'x265'   = @{ param = '--transfer'; value = 'bt470bg' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '5' } 
    }
    'bt470m'    = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt470m' };
        'x264'   = @{ param = '--transfer='; value = '4' };
        'x265'   = @{ param = '--transfer'; value = 'bt470m' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '4' } 
    }
    'bt2020-10' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt2020-10bit' };
        'x264'   = @{ param = '--transfer='; value = '14' };
        'x265'   = @{ param = '--transfer'; value = 'bt2020-10' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '14' } 
    }
    'bt2020-12' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt2020-12bit' };
        'x264'   = @{ param = '--transfer='; value = '15' };
        'x265'   = @{ param = '--transfer'; value = 'bt2020-12' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '15' } 
    }
    'smpte170m' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'unspecified' };
        'x264'   = @{ param = '--transfer='; value = '6' };
        'x265'   = @{ param = '--transfer'; value = 'smpte170m' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '6' } 
    }
    'smpte240m' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'unspecified' };
        'x264'   = @{ param = '--transfer='; value = '7' };
        'x265'   = @{ param = '--transfer'; value = 'smpte240m' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '7' } 
    }
    'smpte2084' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'smpte2084' };
        'x264'   = @{ param = '--transfer='; value = '16' };
        'x265'   = @{ param = '--transfer'; value = 'smpte2084' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '16' } 
    }
}

$script:MatrixMappings = @{
    'bt709'     = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '1' };
        'x264'   = @{ param = '--colormatrix='; value = '1' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt709' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '1' } 
    }
    'fcc'       = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '4' };
        'x264'   = @{ param = '--colormatrix='; value = '4' };
        'x265'   = @{ param = '--colormatrix'; value = 'fcc' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '4' } 
    }
    'bt470bg'   = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '5' };
        'x264'   = @{ param = '--colormatrix='; value = '5' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt470bg' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '5' } 
    }
    'smpte170m' = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '6' };
        'x264'   = @{ param = '--colormatrix='; value = '6' };
        'x265'   = @{ param = '--colormatrix'; value = 'smpte170m' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '6' } 
    }
    'smpte240m' = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '7' };
        'x264'   = @{ param = '--colormatrix='; value = '7' };
        'x265'   = @{ param = '--colormatrix'; value = 'smpte240m' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '7' } 
    }
    'bt2020nc'  = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '9' };
        'x264'   = @{ param = '--colormatrix='; value = '9' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt2020nc' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '9' } 
    }
    'bt2020c'   = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '10' };
        'x264'   = @{ param = '--colormatrix='; value = '10' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt2020c' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '10' } 
    }
}

function Get-VideoColorParams {
    <#
.SYNOPSIS
    Получает цветовые параметры видеофайла
#>
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoFilePath
    )

    $colorParams = & ffprobe -v error -select_streams v:0 `
        -show_entries "stream=color_range,color_space,color_transfer,color_primaries" `
        -of default=noprint_wrappers=1 "$VideoFilePath" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось получить цветовые параметры видео: $colorParams"
    }

    $result = @{}
    $colorParams | ForEach-Object {
        if ($_ -match '(.+)=(.+)') {
            $key = $matches[1]
            $value = $matches[2]
            if ($value -ne 'unknown') {
                $result[$key] = $value
            }
        }
    }

    return [PSCustomObject]@{
        ColorRange     = $result['color_range']
        ColorSpace     = $result['color_space']
        ColorTransfer  = $result['color_transfer']
        ColorPrimaries = $result['color_primaries']
    }
}

function Get-VideoColorMappings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoPath
    )

    $colorParams = Get-VideoColorParams -VideoFilePath $VideoPath
    $mappings = @{}

    # Map color range
    if ($colorParams.ColorRange -and $script:ColorRangeMappings[$colorParams.ColorRange]) {
        $mappings['Range'] = $script:ColorRangeMappings[$colorParams.ColorRange]
    }

    # Map color primaries
    if ($colorParams.ColorPrimaries -and $script:ColorPrimariesMappings[$colorParams.ColorPrimaries]) {
        $mappings['Primaries'] = $script:ColorPrimariesMappings[$colorParams.ColorPrimaries]
    }

    # Map transfer characteristics
    if ($colorParams.ColorTransfer -and $script:TransferMappings[$colorParams.ColorTransfer]) {
        $mappings['Transfer'] = $script:TransferMappings[$colorParams.ColorTransfer]
    }

    # Map matrix coefficients
    if ($colorParams.ColorSpace -and $script:MatrixMappings[$colorParams.ColorSpace]) {
        $mappings['Matrix'] = $script:MatrixMappings[$colorParams.ColorSpace]
    }

    return $mappings
}

function Copy-VideoFragments {
    <#
    .SYNOPSIS
    Extracts uniform fragments from MKV video file using mkvmerge.
    
    .DESCRIPTION
    Creates new MKV file containing specified number of uniform fragments from source MKV.
    Uses single mkvmerge call with precise time ranges for maximum reliability.
    
    .PARAMETER InputFile
    Path to input MKV video file
    
    .PARAMETER OutputFile
    Path for output video file
    
    .PARAMETER FragmentCount
    Number of fragments to extract (1-255)
    
    .PARAMETER FragmentDuration
    Duration of each fragment in seconds (1-600)
    
    .PARAMETER SkipStartSeconds
    Seconds to skip at the beginning of the video (default: 0)
    
    .PARAMETER SkipEndSeconds
    Seconds to skip at the end of the video (default: 0)
    
    .PARAMETER KeepAudio
    Include audio streams in output
    
    .PARAMETER KeepSubtitles
    Include subtitle streams in output
    
    .PARAMETER KeepAttachments
    Include attachments in output
    
    .PARAMETER KeepGlobalTags
    Keep global tags from source file (default: false)
    
    .PARAMETER KeepChapters
    Keep chapters from source file (default: false)
    
    .EXAMPLE
    Copy-VideoFragments -InputFile "input.mkv" -OutputFile "output.mkv" -FragmentCount 5 -FragmentDuration 10 -SkipStartSeconds 60 -SkipEndSeconds 120
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$InputFile,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFile,
        
        [ValidateRange(1, 255)]
        [int]$FragmentCount = 10,
        
        [ValidateRange(1, 600)]
        [int]$FragmentDuration = 12,
        
        [ValidateRange(0, [int]::MaxValue)]
        [double]$SkipStartSeconds = 60,
        
        [ValidateRange(0, [int]::MaxValue)]
        [double]$SkipEndSeconds = 60,
        
        [bool]$KeepAudio = $false,
        [bool]$KeepSubtitles = $false,
        [bool]$KeepAttachments = $false,
        
        [bool]$KeepGlobalTags = $false,
        [bool]$KeepChapters = $false
    )

    # Check for mkvmerge
    if (-not (Get-Command mkvmerge -ErrorAction SilentlyContinue)) {
        throw "mkvmerge is required (install MKVToolNix)"
    }

    # Normalize paths
    $InputFile = (Get-Item -LiteralPath $InputFile).FullName
    $OutputFile = [System.IO.Path]::GetFullPath($OutputFile)

    # Get duration
    try {
        $totalDuration = [double](& ffprobe -v error -show_entries format=duration -of csv=p=0 -i $InputFile 2>&1)
    }
    catch {
        throw "Failed to get duration: $_"
    }

    # Validate skip parameters
    if ($SkipStartSeconds + $SkipEndSeconds -ge $totalDuration) {
        throw "Sum of SkipStartSeconds and SkipEndSeconds ($($SkipStartSeconds + $SkipEndSeconds)) is greater than total duration ($totalDuration)"
    }

    # Calculate available duration
    $availableDuration = $totalDuration - $SkipStartSeconds - $SkipEndSeconds

    # Validate fragment duration
    if ($availableDuration -le $FragmentDuration) {
        throw "Available duration ($availableDuration sec) is less than fragment duration ($FragmentDuration sec)"
    }

    # Calculate uniform time ranges (HH:MM:SS.ss format)
    $step = ($availableDuration - $FragmentDuration) / ($FragmentCount - 1)
    $timeParts = foreach ($i in 0..($FragmentCount - 1)) {
        $start = $SkipStartSeconds + [math]::Min($i * $step, $availableDuration - $FragmentDuration)
        $startTime = [TimeSpan]::FromSeconds($start)
        $endTime = [TimeSpan]::FromSeconds($start + $FragmentDuration)
        "$($startTime.ToString('hh\:mm\:ss\.ff'))-$($endTime.ToString('hh\:mm\:ss\.ff'))"
    }
    
    # Join parts with ',+' separator
    $timeRanges = $timeParts -join ',+'

    # Prepare mkvmerge arguments
    $mkvMergeArgs = @(
        "--ui-language", "en",
        "--priority", "lower",
        "--output", $OutputFile,
        "--split", "parts:$timeRanges"
    )
    
    # Add optional parameters
    if (-not $KeepGlobalTags) { $mkvMergeArgs += "--no-global-tags" }
    if (-not $KeepChapters) { $mkvMergeArgs += "--no-chapters" }
    
    # Add stream selection parameters
    if (-not $KeepAudio) { $mkvMergeArgs += "--no-audio" }
    if (-not $KeepSubtitles) { $mkvMergeArgs += "--no-subtitles" }
    if (-not $KeepAttachments) { $mkvMergeArgs += "--no-attachments" }
    
    # Add input file
    $mkvMergeArgs += $InputFile

    # Execute single mkvmerge command
    try {
        Write-Progress -Activity "Processing" -Status "Extracting $FragmentCount fragments"
        
        Write-Verbose "Executing: mkvmerge $($mkvMergeArgs -join ' ')"
        
        & mkvmerge @mkvMergeArgs 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            throw "mkvmerge failed with exit code $LASTEXITCODE"
        }

        if (-not (Test-Path -LiteralPath $OutputFile)) {
            throw "Output file was not created"
        }

        [PSCustomObject]@{
            OutputFile = $OutputFile
            TimeRanges = $timeParts
            Command    = "mkvmerge $($mkvMergeArgs -join ' ')"
            Parameters = @{
                FragmentCount     = $FragmentCount
                FragmentDuration  = $FragmentDuration
                TotalDuration     = $totalDuration
                AvailableDuration = $availableDuration
                SkipStartSeconds  = $SkipStartSeconds
                SkipEndSeconds    = $SkipEndSeconds
            }
        }
    }
    catch {
        Write-Error "Error: $_"
        if (Test-Path -LiteralPath $OutputFile) {
            Remove-Item -LiteralPath $OutputFile -Force
        }
        throw
    }
    finally {
        Write-Progress -Completed -Activity "Done"
    }
}

function Get-VideoStats {
    <#
    .SYNOPSIS
    Calculates average video bitrate using packet-level statistics from ffprobe.

    .DESCRIPTION
    When stream doesn't contain bit_rate metadata, calculates it by analyzing individual packets
    using ffprobe's packet inspection capability.

    .PARAMETER VideoFilePath
        Путь к видеофайлу
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$VideoFilePath
    )
    
    try {
        $videoFile = Get-Item -LiteralPath $VideoFilePath -ErrorAction Stop
        
        # Get all video stream info in one ffprobe call
        $streamMetadata = & ffprobe -v error -select_streams v:0 `
            -show_entries stream `
            -show_entries format=size `
            -of json "$VideoFilePath" | ConvertFrom-Json -AsHashtable
        
        # Calculate FPS from ratio
        $framesPerSecond = if ($streamMetadata.streams[0].r_frame_rate -match '(\d+)/(\d+)') {
            [math]::Round([decimal]$matches[1] / [decimal]$matches[2], 3)
        }
        else {
            [decimal]$streamMetadata.streams[0].r_frame_rate
        }

        # Get detailed packet info in separate call
        $packetMetadata = & ffprobe -v error -select_streams v:0 `
            -count_packets -show_entries packet=dts_time,pts_time,size,flags `
            -of json "$VideoFilePath" | ConvertFrom-Json -AsHashtable
        
        # Calculate frame counts from different sources
        $frameCountFromPackets = $packetMetadata.packets.Count
        $frameCountFromStream = [int]$streamMetadata.streams[0].nb_read_packets
        $frameCountFromNbFrames = if ($streamMetadata.streams[0].nb_frames) {
            [int]$streamMetadata.streams[0].nb_frames
        }
        else {
            $frameCountFromPackets
        }

        # Calculate duration and bitrate from packets
        $durationFromPackets = $videoBitrate = $videoDataSize = 0
        if ($packetMetadata.packets -and $packetMetadata.packets.Count -gt 0) {
            $firstPacketTime = [double]$packetMetadata.packets[0].pts_time
            $lastPacketTime = [double]($packetMetadata.packets | Measure-Object -Property pts_time -Maximum).Maximum
            $durationFromPackets = $lastPacketTime - $firstPacketTime
            $videoDataSize = ($packetMetadata.packets | Measure-Object -Property size -Sum).Sum
            
            if ($durationFromPackets -gt 0) {
                $videoBitrate = [math]::Round(($videoDataSize * 8) / $durationFromPackets / 1Kb, 2)
            }
        }

        # Calculate duration from different sources
        $durationFromFrames = if ($frameCountFromNbFrames -gt 0) {
            [math]::Round($frameCountFromNbFrames / $framesPerSecond, 3)
        }
        else {
            [math]::Round($frameCountFromPackets / $framesPerSecond, 3)
        }

        $durationFromMetadata = if ($streamMetadata.streams[0].duration) {
            [math]::Round([double]$streamMetadata.streams[0].duration, 3)
        }
        else {
            $durationFromFrames
        }
        
        # Build result object
        return [PSCustomObject]@{
            FilePath            = $VideoFilePath
            FileName            = $videoFile.Name
            FileSizeBytes       = $videoFile.Length
            VideoDataSizeBytes  = $videoDataSize
            VideoCodecName      = $streamMetadata.streams[0].codec_name
            ResolutionWidth     = [int]$streamMetadata.streams[0].width
            ResolutionHeight    = [int]$streamMetadata.streams[0].height
            FrameRate           = $framesPerSecond
            FrameRateNum        = [int]($streamMetadata.streams[0].r_frame_rate -split '/')[0]
            FrameRateDen        = [int]($streamMetadata.streams[0].r_frame_rate -split '/')[1]
            FrameCount          = $frameCountFromNbFrames
            FrameCountPackets   = $frameCountFromPackets
            FrameCountStream    = $frameCountFromStream
            DurationSeconds     = $durationFromMetadata
            DurationFromFrames  = $durationFromFrames
            DurationFromPackets = [math]::Round($durationFromPackets, 3)
            FormattedDuration   = "{0:hh\:mm\:ss}" -f [timespan]::fromseconds($durationFromMetadata)
            BitrateKbps         = $videoBitrate
            PixelFormat         = $streamMetadata.streams[0].pix_fmt
            BitDepth            = $streamMetadata.streams[0].bits_per_raw_sample
            StreamMetadata      = $streamMetadata.streams[0]
            PacketMetadata      = $packetMetadata
        }
    }
    catch {
        Write-Error "Error processing video file '$VideoFilePath': $_"
        throw
    }
}

function Get-VideoAutoCropParams {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$InputFile,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$ThresholdBegin = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$ThresholdEnd = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$LuminanceThreshold = 1000,

        [Parameter(Mandatory = $false)]
        [ValidateSet(2, 4, 8, 16, 32)]
        [int]$Round = 2
    )
    
    # Функция для округления до ближайшего кратного значения
    function RoundToNearestMultiple {
        param([int]$Value, [int]$Multiple)
        if ($Multiple -eq 0) { return $Value }
        return [Math]::Round($Value / $Multiple) * $Multiple
    }

    $tmpScriptFile = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), 'vpy')
    
    @"
import vapoursynth as vs
core = vs.core

# Constants for better readability
MATRIX = {
    'RGB': 0,
    'BT709': 1,
    'UNSPEC': 2,
    'BT470BG': 5,
    'BT2020_NCL': 9
}

TRANSFER = {
    'BT709': 1,
    'BT470BG': 5,
    'ST2084': 16
}

PRIMARIES = {
    'BT709': 1,
    'BT470BG': 5,
    'BT2020': 9
}

# Load source
clip = core.lsmas.LWLibavSource(r"$InputFile")

# Get frame properties
props = clip.get_frame(0).props

# Determine matrix, transfer and primaries
matrix = props.get('_Matrix', MATRIX['UNSPEC'])
if matrix == MATRIX['UNSPEC'] or matrix >= 15:
    matrix = MATRIX['RGB'] if clip.format.id == vs.RGB24 else (
        MATRIX['BT709'] if clip.height > 576 else MATRIX['BT470BG']
    )

transfer = props.get('_Transfer', TRANSFER['BT709'])
if transfer <= 0 or transfer >= 19:
    transfer = (
        TRANSFER['BT470BG'] if matrix == MATRIX['BT470BG'] else
        TRANSFER['ST2084'] if matrix == MATRIX['BT2020_NCL'] else
        TRANSFER['BT709']
    )

primaries = props.get('_Primaries', PRIMARIES['BT709'])
if primaries <= 0 or primaries >= 23:
    primaries = (
        PRIMARIES['BT470BG'] if matrix == MATRIX['BT470BG'] else
        PRIMARIES['BT2020'] if matrix == MATRIX['BT2020_NCL'] else
        PRIMARIES['BT709']
    )

# Display color parameters
#clip = core.text.Text(
#    clip, 
#    text='matrix: %d; transfer: %d; primaries: %d' % (matrix, transfer, primaries),
#    scale=10
#)

# Process video
clip = clip.resize.Bicubic(
    matrix_in=matrix,
    transfer_in=transfer,
    primaries_in=primaries,
    format=vs.RGB24
)
clip = clip.libp2p.Pack()
clip.set_output()
"@ | Set-Content -Path $tmpScriptFile -Force

    $AutoCropPath = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Support\AutoCrop\AutoCrop.exe'
    $acFrameCount = 2
    $acFrameInterval = 400
    
    try {
        $autocropOutput = & $AutoCropPath $tmpScriptFile $acFrameCount $acFrameInterval 144 144 $LuminanceThreshold 0
        
        # Получаем последнюю строку вывода (с параметрами обрезки)
        $cropLine = $autocropOutput | Select-Object -Last 1
        
        # Разбиваем строку по запятым и преобразуем в числа
        $cropParams = $cropLine -split ',' | ForEach-Object { [int]$_ }

        # Округляем значения до кратных $Round
        $roundedLeft = RoundToNearestMultiple -Value $cropParams[0] -Multiple $Round
        $roundedTop = RoundToNearestMultiple -Value $cropParams[1] -Multiple $Round
        $roundedRight = RoundToNearestMultiple -Value $cropParams[2] -Multiple $Round
        $roundedBottom = RoundToNearestMultiple -Value $cropParams[3] -Multiple $Round

        # Создаем объект с параметрами обрезки
        return [PSCustomObject]@{
            Left           = $roundedLeft
            Top            = $roundedTop
            Right          = $roundedRight
            Bottom         = $roundedBottom
            OriginalLeft   = $cropParams[0]
            OriginalTop    = $cropParams[1]
            OriginalRight  = $cropParams[2]
            OriginalBottom = $cropParams[3]
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmpScriptFile) {
            Remove-Item -LiteralPath $tmpScriptFile -ErrorAction SilentlyContinue
        }
    }
}

class VideoColorInfo {
    [bool]$IsHDR
    [bool]$IsDolbyVision
    [string]$ColorPrimaries
    [string]$ColorTransfer
    [string]$ColorSpace
    [string]$ColorRange
    [string]$HDRFormat
    [double]$MaxLuminance
    [double]$MinLuminance
    [string]$MatrixCoefficients
    
    VideoColorInfo() {
        $this.IsHDR = $false
        $this.IsDolbyVision = $false
        $this.HDRFormat = "SDR"
    }
    
    [string] ToString() {
        if ($this.IsHDR) {
            $format = if ($this.IsDolbyVision) { "Dolby Vision" } else { $this.HDRFormat }
            return "HDR ($format) - Primaries: $($this.ColorPrimaries), Transfer: $($this.ColorTransfer)"
        }
        return "SDR - Primaries: $($this.ColorPrimaries), Transfer: $($this.ColorTransfer)"
    }
}

function Get-DetailedVideoColorInfo {
    <#
    .SYNOPSIS
        Получает детальную информацию о цветовых характеристиках видео
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath
    )
    
    try {
        $colorInfo = [VideoColorInfo]::new()
        
        # Получаем базовую информацию через ffprobe
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams v:0 `
            -show_entries stream=color_primaries,color_transfer,color_space,color_range,side_data_list `
            -show_entries format_tags=MAXCLL,MAXFALL `
            -of json $VideoPath | ConvertFrom-Json
        
        $stream = $ffprobeOutput.streams[0]
        $formatTags = $ffprobeOutput.format.tags
        
        # Заполняем базовые цветовые характеристики
        $colorInfo.ColorPrimaries = $stream.color_primaries ?? 'unknown'
        $colorInfo.ColorTransfer = $stream.color_transfer ?? 'unknown'
        $colorInfo.ColorSpace = $stream.color_space ?? 'unknown'
        $colorInfo.ColorRange = $stream.color_range ?? 'unknown'
        
        # Определяем HDR характеристики
        $colorInfo.IsHDR = $false
        
        # Проверяем transfer characteristics для HDR
        if ($stream.color_transfer -in ('smpte2084', 'arib-std-b67', 'bt2020-10', 'bt2020-12')) {
            $colorInfo.IsHDR = $true
            $colorInfo.HDRFormat = switch ($stream.color_transfer) {
                'smpte2084' { 'HDR10' }
                'arib-std-b67' { 'HLG' }
                'bt2020-10' { 'HDR10' }
                'bt2020-12' { 'HDR10' }
                default { 'HDR' }
            }
        }
        
        # Проверяем Dolby Vision
        if ($stream.side_data_list) {
            foreach ($sideData in $stream.side_data_list) {
                if ($sideData.side_data_type -eq 'DOVI configuration record') {
                    $colorInfo.IsHDR = $true
                    $colorInfo.IsDolbyVision = $true
                    $colorInfo.HDRFormat = 'Dolby Vision'
                    break
                }
            }
        }
        
        # Получаем информацию о яркости из метаданных
        if ($formatTags) {
            if ($formatTags.MAXCLL) {
                $colorInfo.MaxLuminance = [double]$formatTags.MAXCLL
            }
            if ($formatTags.MAXFALL) {
                $colorInfo.MinLuminance = [double]$formatTags.MAXFALL
            }
        }
        
        # Определяем матричные коэффициенты
        if ($stream.color_space -and $script:MatrixMappings[$stream.color_space]) {
            $colorInfo.MatrixCoefficients = $stream.color_space
        }
        
        Write-Log "Цветовая информация: $colorInfo" -Severity Information -Category 'Video'
        return $colorInfo
    }
    catch {
        Write-Log "Ошибка при получении цветовой информации: $_" -Severity Warning -Category 'Video'
        # Возвращаем базовый объект с информацией об ошибке
        $colorInfo.IsHDR = Test-VideoHDR -VideoPath $VideoPath
        return $colorInfo
    }
}

function Get-RecommendedEncoderSettings {
    <#
    .SYNOPSIS
        Рекомендует настройки энкодера на основе характеристик видео
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [VideoColorInfo]$ColorInfo,
        
        [Parameter(Mandatory)]
        [string]$EncoderName,
        
        [object]$VideoStats
    )
    
    $recommendations = @{
        Encoder = $EncoderName
        QualityAdjustment = 0
        PresetAdjustment = 0
        AdditionalParams = @()
        Notes = @()
    }
    
    # Рекомендации для HDR контента
    if ($ColorInfo.IsHDR) {
        $recommendations.Notes += "HDR контент: $($ColorInfo.HDRFormat)"
        
        switch ($EncoderName) {
            { $_ -like 'SvtAv1Enc*' } {
                if ($ColorInfo.IsDolbyVision) {
                    $recommendations.AdditionalParams += '--enable-dolby-vision', '1'
                    $recommendations.Notes += "Включена поддержка Dolby Vision"
                }
                
                # Для HDR немного увеличиваем качество
                $recommendations.QualityAdjustment = -2
                $recommendations.Notes += "HDR требует более высокого битрейта"
            }
            
            'AomAv1Enc' {
                $recommendations.AdditionalParams += '--color-primaries=bt2020', '--transfer-characteristics=smpte2084'
                if ($ColorInfo.MaxLuminance -gt 0) {
                    $recommendations.AdditionalParams += "--mastering-display=$($ColorInfo.MaxLuminance)nits"
                }
            }
        }
    }
    
    # Рекомендации на основе разрешения
    if ($VideoStats -and $VideoStats.ResolutionWidth -gt 1920) {
        $recommendations.Notes += "Высокое разрешение: $($VideoStats.ResolutionWidth)x$($VideoStats.ResolutionHeight)"
        
        # Для 4K+ уменьшаем preset для лучшего качества
        if ($VideoStats.ResolutionWidth -gt 3840) {
            $recommendations.PresetAdjustment = -2
            $recommendations.Notes += "8K контент: используем более медленный preset"
        } elseif ($VideoStats.ResolutionWidth -gt 2560) {
            $recommendations.PresetAdjustment = -1
            $recommendations.Notes += "4K контент: умеренное снижение скорости"
        }
    }
    
    return $recommendations
}

# Онлайн-перевод
function Invoke-MyMemoryTranslate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [string]$SourceLang = "ru",
        [string]$TargetLang = "en"
    )

    $url = "https://api.mymemory.translated.net/get?q=$([System.Web.HttpUtility]::UrlEncode($Text))&langpair=$SourceLang|$TargetLang"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get
        return $response.responseData.translatedText
    }
    catch {
        Write-Error "Ошибка перевода: $_"
        return $null
    }
}

function Invoke-LibreTranslate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [string]$SourceLang = "ru",
        [string]$TargetLang = "en"
    )

    # Русские публичные серверы
    $servers = @(
        "https://translate.terraprint.co",
        "https://libretranslate.opensourcestack.com"
    )

    $body = @{
        q      = $Text
        source = $SourceLang
        target = $TargetLang
    } | ConvertTo-Json

    foreach ($server in $servers) {
        try {
            $url = "$server/translate"
            $response = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json"
            if ($response.translatedText) {
                return $response.translatedText
            }
        }
        catch {
            Write-Warning "Сервер $server недоступен"
            continue
        }
    }
    
    Write-Error "Все серверы недоступны"
    return $null
}

function Invoke-GoogleTranslate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [string]$SourceLang = "auto",
        [string]$TargetLang = "en"
    )

    # Используем альтернативный endpoint
    $url = "https://translate.googleapis.com/translate_a/single?client=dict-chrome-ex&sl=$SourceLang&tl=$TargetLang&dt=t&q=$([System.Web.HttpUtility]::UrlEncode($Text))"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        return ($response[0] | ForEach-Object { $_[0] }) -join ""
    }
    catch {
        Write-Error "Ошибка перевода Google: $_"
        return $null
    }
}

function Invoke-FreeTranslate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [string]$SourceLang = "ru",
        [string]$TargetLang = "en"
    )

    Write-Host "Пробуем MyMemory..." -ForegroundColor Yellow
    $result = Invoke-MyMemoryTranslate -Text $Text -SourceLang $SourceLang -TargetLang $TargetLang
    if ($result) { return $result }

    Write-Host "Пробуем LibreTranslate..." -ForegroundColor Yellow
    $result = Invoke-LibreTranslate -Text $Text -SourceLang $SourceLang -TargetLang $TargetLang
    if ($result) { return $result }

    Write-Host "Пробуем Google Translate..." -ForegroundColor Yellow
    $result = Invoke-GoogleTranslate -Text $Text -SourceLang $SourceLang -TargetLang $TargetLang
    if ($result) { return $result }

    Write-Error "Все переводчики недоступны"
    return $null
}


# 
Export-ModuleMember -Function Initialize-Configuration, Get-AudioTrackInfo, `
    Remove-TemporaryFiles, Get-VideoScriptInfo, Get-VideoCropParameters, `
    Write-Log, Get-VideoQualityMetrics, Get-VideoFrameRate, ConvertTo-Seconds, `
    Get-SafeFileName, Get-EncoderPath, Get-EncoderParams, Get-EncoderConfig, `
    Copy-VideoFragments, Get-VideoStats, Get-VideoAutoCropParams, Get-VideoColorMappings, `
    Convert-FpsToDouble, Get-MP4AudioTrackInfo, Test-VideoHDR, Invoke-FreeTranslate