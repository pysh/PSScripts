<#
.SYNOPSIS
    Автоматизированный набор тестов кодирования видео с поддержкой нескольких кодеков.

.DESCRIPTION
    Этот скрипт выполняет сравнительное тестирование кодирования видео с использованием различных кодеков и настроек качества. 
    Генерирует отчёты с метриками качества.

    Поддерживаемые кодеры:
    - AV1: SVT-AV1 (включая психовизуальную настройку), aomenc
    - HEVC: x265
    - AVC: x264

    Основные возможности:
    - Настраиваемые профили качества для каждого кодера
    - Точный покадровый анализ источника
    - Расчёт метрик качества (VMAF)
    - Подробная статистика кодирования
    - Генерация отчётов в CSV
    - Автоматическая упаковка в контейнер MKV

.PARAMETER SourceVideoPath
    Путь к исходному видеофайлу для тестов.

.PARAMETER TempDir
    Временная директория для тестовых файлов.
    По умолчанию: директория исходного файла

.PARAMETER SampleDurationSeconds
    Длительность тестовых фрагментов в секундах (1-10000).
    По умолчанию: 120 (2 минуты)

.PARAMETER FrameServer
    Движок для обработки видео.
    Допустимые значения: 'AviSynth', 'VapourSynth'
    По умолчанию: 'AviSynth'

.PARAMETER CropParameters
    Параметры обрезки видео. Если не указаны, определяются автоматически.

.EXAMPLE
    PS> .\Create-TestVideoFiles_DeepSeek.ps1 -SourceVideoPath "C:\video\test.mkv" -SampleDurationSeconds 60
    
    Запускает тесты с 1-минутными фрагментами из указанного файла.

.EXAMPLE
    PS> .\Create-TestVideoFiles_DeepSeek.ps1 -FrameServer VapourSynth -TestedEncoders "x265","SvtAv1"
    
    Запускает тесты для x265 и SVT-AV1 с использованием VapourSynth.

.NOTES
    Требования к системе:
    - PowerShell 5.1 или новее
    - Кодеры: SVT-AV1, aomenc, x265, x264
    - Обработка видео: AviSynth+ или VapourSynth
    - Инструменты FFmpeg (ffmpeg, ffprobe)
    - MKVToolNix (mkvmerge)
    - Модуль video_tools_AI.ps1

.LINK
    Проект SVT-AV1: https://gitlab.com/AOMediaCodec/SVT-AV1
    Кодер aomenc: https://aomedia.googlesource.com/aom/
    Кодер x265: https://www.videolan.org/developers/x265.html
    Кодер x264: https://www.videolan.org/developers/x264.html

.VERSION
    2.3.0

.AUTHOR
    Paul Nosov
    Контакты: paul.nosov@gmail.com
    GitHub: https://github.com/pysh

.DATE
    2025-07-14
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$SourceVideoPath = 'y:\.temp\YT_y\.temp\Lihie.S01.E06.2024.WEB-DL.HEVC.2160p.SDR.ExKinoRay.mkv',
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$TempDir = [IO.Path]::GetDirectoryName($SourceVideoPath),

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int]$SampleDurationSeconds = 120,

    [Parameter(Mandatory = $false)]
    [ValidateSet('AviSynth', 'VapourSynth')] 
    [string]$FrameServer = 'AviSynth',

    [Parameter(Mandatory = $false)]
    [System.Object]$CropParameters = @{
        Left   = 0
        Right  = 0
        Top    = 0
        Bottom = 0
    },

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10000)]
    [int]$autoCropRound = 2,

    [Parameter(Mandatory = $false)]
    [ValidateSet('SvtAv1', 'SvtAv1PSY', 'SvtAv1Essential', 'AOMEnc', 'x265', 'x264')]
    [string[]]$TestedEncoders = @('SvtAv1','SvtAv1PSY','AOMEnc')
)

#region Конфигурация кодеков
class EncoderProfile {
    [string]$Name
    [string]$DisplayName
    [string]$ExecutablePath
    [string[]]$CommonParams
    [scriptblock]$GetQualityParams
    [int[]]$QualityLevels
    [int[]]$EncodingPresets
    [string[]]$ExtraParams
    [string]$OutputExtension

    EncoderProfile(
        [string]$name,
        [string]$displayName,
        [string]$executablePath,
        [string[]]$commonParams,
        [scriptblock]$getQualityParams,
        [int[]]$qualityLevels,
        [int[]]$encodingPresets,
        [string[]]$extraParams,
        [string]$outputExtension
    ) {
        $this.Name = $name
        $this.DisplayName = $displayName
        $this.ExecutablePath = $executablePath
        $this.CommonParams = $commonParams
        $this.GetQualityParams = $getQualityParams
        $this.QualityLevels = $qualityLevels
        $this.EncodingPresets = $encodingPresets
        $this.ExtraParams = $extraParams
        $this.OutputExtension = $outputExtension
    }
}

function Get-EncoderProfiles {
    return @(
        [EncoderProfile]::new(
            "SvtAv1",
            "SVT-AV1",
            "X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe",
            @("--progress", "3", "--rc", "0"), #, "--input-depth", "10"),
            { param($crf, $preset) @("--crf", $crf, "--preset", $preset) },
            @(26,28,30,32,34,36,38),
            @(3),
            @(""),
            "ivf"
        ),
        [EncoderProfile]::new(
            "SvtAv1PSY",
            "SVT-AV1 (Psychovisual)",
            "X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-PSYEX\SvtAv1EncApp.exe",
            @("--progress", "3", "--rc", "0"<# , "--hbd-mds", "2" #>, "--input-depth", "10"),
            { param($crf, $preset) @("--crf", $crf, "--preset", $preset) },
            @(26,28,30,32,34,36,38),
            @(3),
            @(""),
            "ivf"
        ),

        [EncoderProfile]::new(
            "SvtAv1Essential",
            "SVT-AV1 Essential",
            "X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-Essential\SvtAv1EncApp.exe",
            @("--progress", "3", "--rc", "0"), #, "--input-depth", "10"),
            { param($speed, $quality) @("--speed", $speed, "--quality", $preset) },
            @(26,28,30,32,34,36,38),
            @(3),
            @(""),
            "ivf"
        ),

        [EncoderProfile]::new(
            "AOMEnc",
            "AOM AV1",
            'X:\Apps\_VideoEncoding\ffmpeg\aomenc.exe',
            @("--passes=1", "--end-usage=q", "--threads=0", "--tune=ssim", "--enable-qm=1", "--deltaq-mode=3", "--ivf", "--bit-depth=10"),
            { param($crf, $preset) @("--cq-level=$crf", "--cpu-used=$preset") },
            @(20,22,24),
            @(3,4),
            @(""),
            "ivf"
        ),
        [EncoderProfile]::new(
            "x265",
            "x265 (HEVC)",
            "X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\x265\x265.exe",
            @("--no-strong-intra-smoothing", "--constrained-intra"), # , "--tune", "ssim", "--preset", "slow", "--tune", "ssim"
            { param($crf, $preset) @("--crf", $crf, "--preset", ("medium", "slow", "slower", "veryslow")[$preset-1]) },
            @(0),
            @(3),
            @(""), #, "--psy-rd 2.0"),
            "h265"
        ),
        [EncoderProfile]::new(
            "x264",
            "x264 (AVC)",
            "X:\Apps\_VideoEncoding\av1an\x264.exe",
            @("--no-progress", "--demuxer", "y4m", "--output-csp", "i420", "--preset", "slow", "--tune", "ssim"),
            { param($crf, $preset) @("--crf", $crf, "--preset", ("medium", "slow", "slower", "veryslow")[$preset-1]) },
            @(18..26),
            @(2..4),
            @("--aq-mode 3", "--aq-mode 4", "--psy-rd 1.0:0.0"),
            "h264"
        )
    )
}

function Get-EncoderVersion {
    param(
        [EncoderProfile]$Encoder
    )
    
    try {
        switch ($Encoder.Name) {
            { $_ -match 'SvtAv1' } {
                $versionLine = & $Encoder.ExecutablePath --version | Select-Object -First 1
                if ($versionLine -match 'SVT-AV1(?:-PSY|-HDR)? (v[\d\.]+-[^-]+)') {
                    $version = $matches[1]
                    if ($Encoder.Name -eq 'SvtAv1PSY' -and $versionLine -match '\[Mod by Patman\]') {
                        $version += " [Patman]"
                    }
                    return $version
                }
                return "Unknown"
            }
            'AOMEnc' {
                $helpOutput = & $Encoder.ExecutablePath --help | Out-String
                if ($helpOutput -match 'AV1 Encoder ([\d\.]+-\d+-g[a-f0-9]+)') {
                    return $matches[1]
                }
                return "Unknown"
            }
            'x265' {
                $versionLine = & $Encoder.ExecutablePath --version | Where-Object { $_ -match 'HEVC encoder version' }
                if ($versionLine -match 'HEVC encoder version (?<ver>.+)$') {
                    return $matches['ver'].Trim()
                }
                return "Unknown"
            }
            'x264' {
                $versionLine = & $Encoder.ExecutablePath --version | Select-Object -First 1
                if ($versionLine -match 'x264 (\d+\.\d+\.\d+)') {
                    return $matches[1]
                }
                return "Unknown"
            }
            default {
                return "Unknown version"
            }
        }
    }
    catch {
        Write-Log -Message "Не удалось получить версию кодера $($Encoder.Name): $_" -Severity Warn
        return "Unknown"
    }
}
# Инициализация профилей кодеков
$script:EncoderProfiles = Get-EncoderProfiles

# Конфигурация тестирования
$script:EncodingConfig = @{
    TestedEncoders = $TestedEncoders
}

# Инструменты
$script:EncodingTools = @{
    FFmpeg   = 'ffmpeg.exe'
    FFprobe  = 'ffprobe.exe'
    VSPipe   = 'vspipe.exe'
    MkvMerge = 'mkvmerge.exe'
}

function Test-ToolExists {
    param([string]$tool)
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Не найден необходимый инструмент: $tool"
    }
}

# Проверка доступности инструментов
foreach ($tool in $script:EncodingTools.Values) {
    Test-ToolExists $tool
}

# Загрузка вспомогательных функций
Import-Module 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Convert-VideoToAV1\Modules\Utilities.psm1' -Force
# . 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\video_tools_AI.ps1'

#endregion

#region Классы
class EncodingJob {
    [EncoderProfile]$Encoder
    [string]$InputScript
    [string]$OutputFile
    [int]$Crf
    [int]$Preset
    [string[]]$ExtraParams
    [string]$ServerType
    [object]$SourceVideoInfo
    [int]$SampleDurationSeconds
}

class EncodingResult {
    [string]$FileName
    [string]$Encoder
    [string]$EncoderVersion
    [string]$Parameters
    [double]$EncodedVideoSizeMB
    [string]$EncodingTime
    [double]$EncodingFPS
    [double]$VMAFScore
    [string]$PixelFormat
    [Int16]$BitDepth
    [double]$OriginalVideoSizeMB
    [double]$CompressionRatio
}
#endregion

#region Функции
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('Debug', 'Info', 'Error', 'Warn', 'Success')]
        [string]$Severity = 'Info',

        [switch]$NoNewLine
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Severity]`t$Message"
    $colors = @{
        'Debug'   = 'DarkYellow'
        'Info'    = 'Cyan'
        'Error'   = 'Red'
        'Warn'    = 'Magenta'
        'Success' = 'Green'
    }
    
    if ($NoNewLine) {
        Write-Host $logMessage -ForegroundColor $colors[$Severity] -NoNewline
    }
    else {
        Write-Host $logMessage -ForegroundColor $colors[$Severity]
    }
}

function New-FrameServerScript {
    param(
        [string]$ScriptPath,
        [string]$VideoPath,
        [int]$Duration,
        [object]$SourceVideoInfo,
        [string]$ServerType,
        [object]$CropParams
    )
    
    $scriptContent = if ($ServerType -eq 'VapourSynth') {
        @"
import os, sys
import vapoursynth as vs
core = vs.core
sample_seconds = $Duration
sys.path.append(r"X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\VS\Scripts")
clip = core.lsmas.LWLibavSource(r"$VideoPath")
clip = core.std.Crop(clip, $($CropParams.Left), $($CropParams.Right), $($CropParams.Top), $($CropParams.Bottom))
clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.neo_f3kdb.Deband(clip, y=64, cb=64, cr=64, output_depth=10, preset="nograin")
clip.set_output()
"@
    }
    else {
        @" 
AddAutoloadDir("X:\Apps\_VideoEncoding\StaxRip\Apps\FrameServer\AviSynth\plugins\")
LoadPlugin("X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\Dual\f3kdb Neo\neo-f3kdb.dll")
LoadPlugin("X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\Dual\L-SMASH-Works\LSMASHSource.dll")
LWLibavVideoSource("$VideoPath")
crop($($CropParams.Left), $($CropParams.Top), $(0-$CropParams.Right), $(0-$CropParams.Bottom))
ConvertBits(10)
neo_f3kdb(preset="nograin", output_depth=10)
"@
    }
    
    Set-Content -LiteralPath $ScriptPath -Value $scriptContent -Force
}

function Invoke-EncodingWithStats {
    param(
        [EncodingJob]$Job
    )
    
    $tempOutputFile = [IO.Path]::ChangeExtension($Job.OutputFile, $Job.Encoder.OutputExtension)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $frameCount = [math]::Round($Job.SourceVideoInfo.FrameRate * $Job.SampleDurationSeconds)
    
    if (-not (Test-Path -LiteralPath $Job.OutputFile)) {
        try {
            Write-Log -Message "Запуск кодера $($Job.Encoder.DisplayName)..." -Severity Info
            
            $qualityParams = & $Job.Encoder.GetQualityParams $Job.Crf $Job.Preset
            $allParams = $Job.Encoder.CommonParams + $qualityParams + `
            $(if ($Job.ExtraParams -ne '') { $Job.ExtraParams })

            # Раздельная обработка для разных типов кодеков
            if ($Job.Encoder.Name -match 'x26[45]') {
                # Прямой вызов для x264/x265
                $allParams += @(
                    "--input", $Job.InputScript,
                    "--output", $tempOutputFile
                )
                Write-Verbose "Запуск кодера $($Job.Encoder.DisplayName) с параметрами: $($allParams -join ' ')"
                & $Job.Encoder.ExecutablePath @allParams
            }
            else {
                # Обработка AV1 кодеков через пайп
                $ffmpegParams = @(
                    "-y", "-hide_banner", "-v", "error", "-nostats"
                    "-i", $($Job.InputScript),
                    "-f", "yuv4mpegpipe",
                    "-strict", -1,
                    "-"
                )

                $allParams += @(
                    if ($Job.Encoder.Name -eq "AOMEnc") {
                        "-o", $tempOutputFile
                        "-"
                    }
                    else {
                        "--input", "-",
                        "--output", $tempOutputFile
                    }
                )

                if ($Job.ServerType -eq 'VapourSynth') {
                    Write-Verbose "Запуск кодера $($Job.Encoder.DisplayName) с параметрами: $($allParams -join ' ')"
                    & $script:EncodingTools.VSPipe -c y4m "$($Job.InputScript)" - | & $Job.Encoder.ExecutablePath @allParams
                }
                else {
                    Write-Verbose "Запуск кодера $($Job.Encoder.DisplayName) с параметрами: $($allParams -join ' ')"
                    & $($script:EncodingTools.FFmpeg) @ffmpegParams | & $($Job.Encoder.ExecutablePath) @allParams
                }
            }

            # Упаковка в MKV
            & $script:EncodingTools.MkvMerge --ui-language en --priority lower --output-charset UTF8 --output $Job.OutputFile $tempOutputFile 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Ошибка mkvmerge: $LASTEXITCODE" }
            
            if (Test-Path -LiteralPath $Job.OutputFile) {
                Remove-Item -LiteralPath $tempOutputFile -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log -Message "Ошибка кодирования $($Job.Encoder.DisplayName): $_" -Severity Error
            throw
        }
    }
    $timer.Stop()

    $outputFileInfo = Get-VideoStats -VideoFilePath $Job.OutputFile
    $VMAFModelVersion = if ([int]$Job.SourceVideoInfo.ResolutionHeight -le 1080) {
        'vmaf_v0.6.1'
    } else {
        'vmaf_4k_v0.6.1'
    }
    Write-Log -Message "Расчёт VMAF с моделью ${VMAFModelVersion}..." -Severity Info
    
    #$vmafScore = Get-VMAFValueAI -Distorted $Job.OutputFile -Reference $Job.InputScript -ModelVersion $VMAFModelVersion

    $vmafScore = Get-VideoQualityMetrics `
                    -DistortedPath $job.OutputFile `
                    -ReferencePath $job.InputScript `
                    -ModelVersion (([int]$Job.SourceVideoInfo.ResolutionHeight -le 1080) ? 'vmaf_v0.6.1' : 'vmaf_4k_v0.6.1') `
                    -Metrics VMAF `
                    -Subsample 1

    $vmafScore = [Math]::Round($vmafScore.VMAF, 2)
    $finalOutputName = Join-Path -Path (Get-Item -LiteralPath $Job.OutputFile).DirectoryName `
        -ChildPath ("$((Get-Item -LiteralPath $Job.OutputFile).BaseName)_[${vmafScore}]$((Get-Item -LiteralPath $Job.OutputFile).Extension)")
    Rename-Item -LiteralPath $Job.OutputFile -NewName $finalOutputName -Force

    $encoderVersion = Get-EncoderVersion -Encoder $Job.Encoder

    return [EncodingResult]@{
        FileName            = $finalOutputName
        Encoder             = $Job.Encoder.DisplayName
        EncoderVersion      = $encoderVersion
        Parameters          = ($Job.Encoder.CommonParams + $qualityParams + $Job.ExtraParams) -join " "
        EncodedVideoSizeMB  = [math]::Round($outputFileInfo.VideoDataSizeBytes / 1MB, 3)
        VMAFScore           = [math]::Round($vmafScore, 2)
        EncodingTime        = "{0:hh\:mm\:ss}" -f $timer.Elapsed
        EncodingFPS         = [math]::Round($frameCount / $timer.Elapsed.TotalSeconds, 2)
        PixelFormat         = $outputFileInfo.PixelFormat
        BitDepth            = $outputFileInfo.BitDepth
        OriginalVideoSizeMB = [math]::Round($Job.SourceVideoInfo.VideoDataSizeBytes / 1MB, 2)
        CompressionRatio    = [math]::Round($Job.SourceVideoInfo.VideoDataSizeBytes / $outputFileInfo.VideoDataSizeBytes, 2)
    }
}
#endregion

#region Основной скрипт
# Clear-Host
$error.Clear()

try {
    # Проверка доступности кодеров
    $availableEncoders = [System.Collections.Generic.List[EncoderProfile]]::new()
    foreach ($encoderName in $script:EncodingConfig.TestedEncoders) {
        $encoder = $script:EncoderProfiles | Where-Object { $_.Name -eq $encoderName }
        if (-not $encoder) {
            Write-Log -Message "Кодер $encoderName не найден в конфигурации" -Severity Warn
            continue
        }
        $availableEncoders.Add($encoder)
    }

    if ($availableEncoders.Count -eq 0) {
        throw "Не найдено доступных кодеров. Проверьте конфигурацию."
    }

    # Вывод информации о версиях кодеров
    Write-Log "Версии доступных кодеров:" -Severity Info
    foreach ($encoder in $availableEncoders) {
        $version = Get-EncoderVersion -Encoder $encoder
        Write-Log "- $($encoder.DisplayName): $version" -Severity Info
    }

    # Расчёт общего количества тестов
    $totalTests = 0
    foreach ($encoder in $availableEncoders) {
        $combinations = $encoder.QualityLevels.Count * $encoder.EncodingPresets.Count * $encoder.ExtraParams.Count
        Write-Log -Message "Кодер $($encoder.DisplayName): $combinations тестовых комбинаций" -Severity Info
        $totalTests += $combinations
    }
    Write-Log -Message "ОБЩЕЕ КОЛИЧЕСТВО ТЕСТОВ: $totalTests" -Severity Info

    # Инициализация рабочей директории
    $sourceVideoFile = Get-Item -LiteralPath $SourceVideoPath
    Write-Log -Message "Обработка файла: $($sourceVideoFile.Name)" -Severity Info
    
    $workingDirectory = if (Test-Path -LiteralPath $TempDir -PathType Container) {
        Join-Path -Path $TempDir -ChildPath "$($sourceVideoFile.BaseName)__Encoding_Tests_"
    }
    else {
        Join-Path -Path $sourceVideoFile.DirectoryName -ChildPath "$($sourceVideoFile.BaseName)__Encoding_Tests"
    }
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    
    $sampleFileName = [IO.Path]::Combine($sourceVideoFile.DirectoryName, [IO.Path]::Combine($workingDirectory, "$($sourceVideoFile.BaseName)[sample]$($sourceVideoFile.Extension)"))
    $sourceVideoFile = if (Test-Path -LiteralPath $sampleFileName -PathType Leaf) {
        Get-Item -LiteralPath $sampleFileName
    }
    else {
        Get-Item -LiteralPath (Copy-VideoFragments -InputFile $sourceVideoFile -OutputFile $sampleFileName -FragmentCount 10 -FragmentDuration 12).OutputFile
    }

    # Получение метаданных видео
    $sourceVideoInfo = Get-VideoStats -VideoFilePath $sourceVideoFile.FullName
    
    # Получение параметров обрезки
    if ($CropParameters -and $CropParameters.Left -ne 0 -and $CropParameters.Right -ne 0 -and $CropParameters.Top -ne 0 -and $CropParameters.Bottom -ne 0) {
        $cropParams = $CropParameters
        Write-Log -Message "Используются ручные параметры обрезки: слева: $($cropParams.Left); справа: $($cropParams.Right); сверху: $($cropParams.Top); снизу: $($cropParams.Bottom)" -Severity Info
    } else {
        $cropParams = Get-VideoAutoCropParams -InputFile $sourceVideoFile.FullName -Round $autoCropRound
        Write-Log -Message "Автоматически определены параметры обрезки: слева: $($cropParams.Left); справа: $($cropParams.Right); сверху: $($cropParams.Top); снизу: $($cropParams.Bottom)" -Severity Info
    }

    # Генерация скрипта для фреймсервера
    $frameServerScriptPath = Join-Path $workingDirectory "$($sourceVideoFile.BaseName).$($FrameServer -eq 'VapourSynth' ? 'vpy' : 'avs')"
    New-FrameServerScript -ScriptPath $frameServerScriptPath `
        -VideoPath $sourceVideoFile.FullName `
        -Duration $SampleDurationSeconds `
        -SourceVideoInfo $sourceVideoInfo `
        -ServerType $FrameServer `
        -CropParams $cropParams

    $encodingResults = [System.Collections.Generic.List[EncodingResult]]::new()
    $testCurrent = 0
    $reportPath = Join-Path -Path $workingDirectory -ChildPath "$($sourceVideoFile.BaseName)_report.csv"

    foreach ($encoder in $availableEncoders) {
        foreach ($crf in $encoder.QualityLevels) {
            foreach ($preset in $encoder.EncodingPresets) {
                foreach ($param in $encoder.ExtraParams) {
                    $testCurrent++
                    $paramName = $param.Replace('--', '').Replace(' ', '=')
                    $outputFileName = "test_$($encoder.Name)_crf=${crf}_preset=${preset}$(if ($paramName -notin ('',$null)) {"+$paramName"}).mkv"
                    $outputFilePath = Join-Path $workingDirectory $outputFileName
                    
                    Write-Log -Message "Тест (${testCurrent}/${totalTests}): $outputFileName" -Severity Info
                    
                    $job = [EncodingJob]@{
                        Encoder               = $encoder
                        InputScript           = $frameServerScriptPath
                        OutputFile            = $outputFilePath
                        Crf                   = $crf
                        Preset                = $preset
                        ExtraParams           = $param -split ' '
                        ServerType            = $FrameServer
                        SourceVideoInfo       = $sourceVideoInfo
                        SampleDurationSeconds = $SampleDurationSeconds
                    }
                    
                    $result = Invoke-EncodingWithStats -Job $job -Verbose
                    $result | Export-Csv -LiteralPath $reportPath -Append -Force -Delimiter "`t"
                    $encodingResults.Add($result)
                    Write-Log -Message "Завершено: $([IO.Path]::GetFileName($result.FileName)) (VMAF: $($result.VMAFScore), Время: $($result.EncodingTime))" -Severity Success
                }
            }
        }
    }

    # Генерация отчёта
    $frameCount = [math]::Round($sourceVideoInfo.FrameRate * $SampleDurationSeconds)
    $reportHeader = @"
# ======================= ОТЧЁТ О КОДИРОВАНИИ ========================
# Исходный файл: $($sourceVideoFile.Name)
# Длительность: $SampleDurationSeconds сек ($frameCount кадров)
# Размер исходного видео: {0:N2} MB
# Всего закодированных файлов: $($encodingResults.Count)
#
"@ -f ($sourceVideoInfo.VideoDataSizeBytes / 1MB)

    Write-Host $reportHeader
    $encodingResults | Format-Table FileName, Encoder, EncoderVersion, VMAFScore, EncodedVideoSizeMB, CompressionRatio, EncodingFPS -AutoSize
    Write-Host "`nОтчёт сохранён в: $reportPath" -ForegroundColor Green
}
catch {
    Write-Log -Message "Ошибка выполнения: $_" -Severity Error
    exit 1
}
#endregion