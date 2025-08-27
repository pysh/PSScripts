<#
.SYNOPSIS
    Модуль вспомогательных функций
#>

$global:Config = $null
$global:VideoTools = $null

function Initialize-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    try {
        if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
            throw "Файл конфигурации не найден"
        }

        $global:Config = Import-PowerShellDataFile -Path $ConfigPath
        $global:VideoTools = $global:Config.Tools

        # # Создаем временную директорию, если не существует
        # if (-not (Test-Path -Path $global:Config.Processing.TempDir -PathType Container)) {
        #     New-Item -Path $global:Config.Processing.TempDir -ItemType Directory -Force | Out-Null
        # }

        Write-Log "Конфигурация успешно загружена" -Severity Success -Category 'Config'
    }
    catch {
        Write-Log "Ошибка загрузки конфигурации: $_" -Severity Error -Category 'Config'
        throw
    }
}

function Get-AudioTrackInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VideoFilePath
    )

    try {
        Write-Log "Получение информации об аудиодорожках" -Severity Verbose -Category 'Audio'
        
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams a `
            -show_entries stream=index,codec_name,channels:stream_tags=language,title:disposition=default,forced,comment `
            -of json $VideoFilePath | ConvertFrom-Json
        
        [Console]::OutputEncoding = $originalEncoding
        
        $result = $ffprobeOutput.streams | ForEach-Object {
            [PSCustomObject]@{
                Index     = $_.index
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

function Remove-TemporaryFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )

    try {
        Write-Log "Очистка временных файлов ($($Job.TempFiles.Count) элементов)" -Severity Information -Category 'Cleanup'
        $removedCount = 0
        
        foreach ($file in $Job.TempFiles) {
            try {
                if (Test-Path -LiteralPath $file -PathType Leaf) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                    $removedCount++
                }
                elseif (Test-Path -LiteralPath $file -PathType Container) {
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
    param (
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    try {
        Write-Log "Получение информации о VapourSynth скрипте" -Severity Verbose -Category 'Video'
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

        Write-Log "Информация о скрипте получена" -Severity Debug -Category 'Video'
        return [PSCustomObject]$infoHash
    }
    catch {
        Write-Log "Ошибка при получении информации о скрипте VapourSynth: $_" -Severity Error -Category 'Video'
        throw
    }
}

function Get-VideoCropParameters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$InputFile
    )
    
    function RoundToNearestMultiple {
        param([int]$Value, [int]$Multiple)
        if ($Multiple -eq 0) { return $Value }
        return [Math]::Round($Value / $Multiple) * $Multiple
    }

    try {
        Write-Log "Определение параметров обрезки для файла: $InputFile" -Severity Information -Category 'Video'
        $tmpScriptFile = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), 'vpy')
        
        # Получаем путь к шаблону из конфига
        $templatePath = $global:Config.Templates.VapourSynth.AutoCrop
        
        if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
            throw "Файл шаблона VapourSynth не найден: $templatePath"
        }

        # Читаем шаблон и заменяем плейсхолдер
        $scriptContent = Get-Content -LiteralPath $templatePath -Raw
        $scriptContent = $scriptContent -replace '\{input_file\}', $InputFile

        Set-Content -LiteralPath $tmpScriptFile -Value $scriptContent -Force

        $AutoCropPath = $global:VideoTools.AutoCrop
        $acFrameCount = 2
        $acFrameInterval = 400
        
        Write-Log "Запуск AutoCrop для определения обрезки" -Severity Verbose -Category 'Video'
        $autocropOutput = & $AutoCropPath $tmpScriptFile $acFrameCount $acFrameInterval 144 144 $global:Config.Processing.AutoCropThreshold 0
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка выполнения AutoCrop (код $LASTEXITCODE)"
        }
        
        $cropLine = $autocropOutput | Select-Object -Last 1
        $cropParams = $cropLine -split ',' | ForEach-Object { [int]$_ }

        $result = [PSCustomObject]@{
            Left           = RoundToNearestMultiple -Value $cropParams[0] -Multiple $global:Config.Encoding.Video.CropRound
            Top            = RoundToNearestMultiple -Value $cropParams[1] -Multiple $global:Config.Encoding.Video.CropRound
            Right          = RoundToNearestMultiple -Value $cropParams[2] -Multiple $global:Config.Encoding.Video.CropRound
            Bottom         = RoundToNearestMultiple -Value $cropParams[3] -Multiple $global:Config.Encoding.Video.CropRound
            OriginalLeft   = $cropParams[0]
            OriginalTop    = $cropParams[1]
            OriginalRight  = $cropParams[2]
            OriginalBottom = $cropParams[3]
        }
        
        Write-Log "Параметры обрезки определены: $result" -Severity Information -Category 'Video'
        return $result
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

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
            
        [ValidateSet('Debug', 'Information', 'Warning', 'Error', 'Success', 'Verbose')]
        [string]$Severity = 'Information',

        [string]$Category,
            
        [switch]$NoNewLine
    )

    $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss.fff")

    switch ($Severity) {
        'Success'     { $color = 'Green';       $logSeverity = 'OK!' }
        'Debug'       { $color = 'DarkGray';    $logSeverity = 'DBG' }
        'Information' { $color = 'Cyan';        $logSeverity = 'INF' }
        'Verbose'     { $color = 'DarkMagenta'; $logSeverity = 'VRB' }
        'Warning'     { $color = 'Yellow';      $logSeverity = 'WRN' }
        'Error'       { $color = 'Red';         $logSeverity = 'ERR' }
        default       { $color = 'White';       $logSeverity = '---' }
    }
    
    $logMessage = "[$timestamp] [$logSeverity]$(if($Category){ " [$Category]" })`t$Message"

    $params = @{
        ForegroundColor = $color
    }
    
    if ($NoNewLine) {
        $params['NoNewline'] = $true
    }

    Write-Host $logMessage @params
}



















<#
.SYNOPSIS
    Вычисляет метрики качества видео VMAF и XPSNR между искаженным и эталонным видео.
.DESCRIPTION
    Объединяет функциональность VMAF и XPSNR в единый вызов с поддержкой:
    - Обрезки по времени и области (crop)
    - Многопоточной обработки
    - Разных моделей VMAF
    - Настройки порогов и округления
.PARAMETER DistortedPath
    Путь к тестируемому (искаженному) видеофайлу.
.PARAMETER ReferencePath
    Путь к эталонному видеофайлу.
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
.PARAMETER XPSNRPoolMethod
    Метод агрегации XPSNR ('mean' или 'harmonic_mean').
.EXAMPLE
    Get-VideoQualityMetrics -ReferencePath "original.mkv" -DistortedPath "encoded.mp4" -Metrics Both
#>
function Get-VideoQualityMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$DistortedPath,

        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path -LiteralPath $_})]
        [string]$ReferencePath,

        [ValidateSet('VMAF', 'XPSNR', 'Both')]
        [string]$Metrics = 'Both',

        [PSCustomObject]$Crop = @{
            Left   = 0
            Right  = 0
            Top    = 0
            Bottom = 0
            CropDistVido = $false
        },

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TrimStartSeconds = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$DurationSeconds = 0,

        [string]$ModelVersion = 'vmaf_4k_v0.6.1',

        [ValidateRange(1, 64)]
        [int]$VMAFThreads = [Environment]::ProcessorCount,

        [ValidateRange(1, 100)]
        [int]$Subsample = 3,

        [string]$VMAFLogPath,

        [ValidateSet('mean', 'harmonic_mean')]
        [string]$VMAFPoolMethod = 'harmonic_mean'

        # [ValidateRange(0, 255)]
        # [int]$BlackThreshold = 24,

        # [ValidateSet(2, 4, 8, 16, 32)]
        # [int]$Round = 4
    )

    # Базовые фильтры для временных меток
    $baseFilters = "settb=AVTB,setpts=PTS-STARTPTS"

    # Собираем фильтры обрезки
    $cropFilterReference = if ($Crop.Left -or $Crop.Right -or $Crop.Top -or $Crop.Bottom) {
        "crop=w=iw-$($Crop.Left)-$($Crop.Right):h=ih-$($Crop.Top)-$($Crop.Bottom):x=$($Crop.Left):y=$($Crop.Top)"
    }
    if ($Crop.CropDistVideo) { $cropFilterDistortion=$cropFilterReference }

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
            "model=version=$ModelVersion"
            "pool=$VMAFPoolMethod"
        )
        
        if ($VMAFLogPath) {
            $vmafParams += "log_path='$($VMAFLogPath.Replace('\', '\\'))'"
            $vmafParams += "log_fmt=json"
        }

        $vmafFilter = "[dist][ref]libvmaf=$($vmafParams -join ':')"
        
        $ffmpegArgs = @(
            "-hide_banner", "-y", "-nostats",
            "-i", $DistortedPath,
            "-i", $ReferencePath,
            "-filter_complex", "${filterChain}${vmafFilter}",
            "-f", "null", "-"
        )

        Write-Verbose "Calculating VMAF: ffmpeg $ffmpegArgs"
        $output = & ffmpeg $ffmpegArgs 2>&1

        if ($output -join '`n' -match [regex]'(?m).*VMAF score: (?<vmaf>\d+\.+\d+).*') {
            $results.VMAF = [double]$Matches.vmaf
        } else {
            Write-Warning "VMAF calculation failed: $($output -join "`n")"
        }
    }

    # Расчет XPSNR
    if ($Metrics -in ('Both', 'XPSNR')) {
        $xpsnrFilter = "[dist][ref]xpsnr=eof_action=endall"
        
        $ffmpegArgs = @(
            "-hide_banner", "-y", "-nostats",
            "-i", $DistortedPath,
            "-i", $ReferencePath,
            "-filter_complex", "${filterChain}${xpsnrFilter}",
            "-f", "null", "-"
        )

        Write-Verbose "Calculating XPSNR: ffmpeg $ffmpegArgs"
        $output = & ffmpeg $ffmpegArgs 2>&1

        if ($output -join '`n' -match [regex]'(?m)XPSNR.*y: (?<y>\d+\.\d+).*u: (?<u>\d+\.\d+).*v: (?<v>\d+\.\d+)') {
            $results.XPSNR = @{
                Y   = [double]$Matches['y']
                U   = [double]$Matches['u']
                V   = [double]$Matches['v']
                AVG = ([double]$Matches['y'] + [double]$Matches['u'] + [double]$Matches['v']) / 3
            }
        } else {
            Write-Warning "XPSNR calculation failed: $($output -join "`n")"
        }
    }

    # Добавляем информацию о параметрах
    $results['Parameters'] = @{
        Crop         = $Crop
        TimeRange    = if ($DurationSeconds -gt 0) {
            "$TrimStartSeconds-$($TrimStartSeconds+$DurationSeconds)s"
        } else { "Full duration" }
        ModelVersion = $ModelVersion
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



Export-ModuleMember -Function Initialize-Configuration, Get-AudioTrackInfo, `
                                Remove-TemporaryFiles, Get-VideoScriptInfo, `
                                Get-VideoCropParameters, Write-Log, `
                                Get-VideoQualityMetrics, Get-SafeFileName