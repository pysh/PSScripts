#region SCRIPT PARAMETERS
<#
.SYNOPSIS
    Скрипт для создания тестовых AV1-видео с подробной статистикой кодирования и автоматическим отчетом.

.DESCRIPTION
    Этот PowerShell-скрипт предназначен для автоматизации создания тестовых видеофайлов в формате AV1 с различными параметрами кодирования. Для каждого сочетания параметров (CRF, пресет, дополнительные параметры) скрипт:
    - Генерирует отдельный видеофайл с помощью выбранного фрейм-сервера (AviSynth или VapourSynth)
    - Сохраняет полную статистику кодирования: исходный/закодированный размер, время, скорость (FPS), VMAF, процент и коэффициент сжатия
    - Формирует подробный CSV-отчет по всем тестам
    - Поддерживает автоматическую генерацию скриптов для AviSynth/VapourSynth
    - Использует внешние инструменты: ffmpeg, ffprobe, vspipe, SvtAv1EncApp, mkvmerge
    - Позволяет гибко настраивать диапазоны параметров кодирования
    - Все промежуточные и итоговые файлы хранятся в отдельной временной папке рядом с исходным видео
    - Весь процесс логируется с цветовой индикацией событий
    - Встроена обработка ошибок и информативный вывод в консоль

.PARAMETER SourceVideoPath
    Путь к исходному видеофайлу (по умолчанию примерный путь)
.PARAMETER SampleDurationSeconds
    Длительность тестового фрагмента в секундах (по умолчанию 120)
.PARAMETER FrameServer
    Тип фрейм-сервера: AviSynth или VapourSynth (по умолчанию AviSynth)

.OUTPUTS
    - Тестовые AV1-видео с разными параметрами
    - CSV-отчет с результатами кодирования
    - Лог событий в консоли

.NOTES
    Требуются внешние утилиты: ffmpeg, ffprobe, vspipe, SvtAv1EncApp, mkvmerge, а также tools.ps1 с функциями Get-VideoStats2 и Get-VMAFValue.
    Скрипт поддерживает расширение диапазонов параметров для массового тестирования.
    Все пути к инструментам и плагинам задаются в начале скрипта.
    Для корректной работы необходимы соответствующие плагины для AviSynth/VapourSynth.

.EXAMPLE
    .\Create-TestVideoFiles5.ps1 -SourceVideoPath "C:\video.mkv" -SampleDurationSeconds 60 -FrameServer VapourSynth
#>

param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SourceVideoPath = 'y:\.temp\YT_y\Стендап комики 4k\Илья Соболев - Третий (Концерт, 2023) [4k].mkv',
    
    [Parameter()]
    [ValidateRange(1, 10000)]
    [int]$SampleDurationSeconds = 120,

    [Parameter(Mandatory = $false)]
    [ValidateSet('AviSynth', 'VapourSynth')] 
    [string]$FrameServer = 'AviSynth'
)
#endregion

#region CONFIGURATION
# Конфигурация инструментов кодирования
$EncodingTools = @{
    FFmpeg     = 'ffmpeg.exe'
    FFprobe    = 'ffprobe.exe'
    VSPipe     = 'vspipe.exe'
    AV1Encoder = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe'
}

# Настройки параметров кодирования для тестирования
$EncodingConfig = @{
    QualityLevels   = 32..33        # Диапазон значений CRF
    EncodingPresets = 4..4          # Диапазон пресетов кодирования
    ExtraParams     = @("--spy-rd 0", "--spy-rd 1")  # Дополнительные параметры
}

# Класс для хранения результатов кодирования
class EncodingResult {
    [string]$FileName
    [string]$Parameters
    [double]$OriginalSizeMB
    [double]$EncodedSizeMB
    [string]$EncodingTime
    [double]$EncodingFPS
    [double]$BitrateReduction
    [double]$VMAFScore
    [double]$CompressionRatio
}
#endregion

#region UTILITY FUNCTIONS
# Оптимизированная функция логирования
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('Debug', 'Info', 'Error')]
        [string]$Severity = 'Info',
        
        [switch]$NoNewLine
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Severity]`t$Message"
    $colors = @{'Debug' = 'DarkYellow'; 'Info' = 'Cyan'; 'Error' = 'Red' }
    
    if ($NoNewLine) {
        Write-Host $logMessage -ForegroundColor $colors[$Severity] -NoNewline
    }
    else {
        Write-Host $logMessage -ForegroundColor $colors[$Severity]
    }
}

# Функция для создания скрипта фрейм-сервера (AviSynth/VapourSynth)
function New-FrameServerScript {
    param(
        [string]$Path,
        [string]$VideoPath,
        [int]$Duration,
        [float]$FPS,
        [string]$Type
    )
    
    Write-Log -Message "Генерация скрипта $Type для видео $VideoPath" -Severity Debug
    
    if ($Type -eq 'VapourSynth') {
        $scriptContent = @"
import os, sys
import vapoursynth as vs
core = vs.core
sample_seconds = $Duration
sys.path.append(r"X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\VS\Scripts")
clip = core.lsmas.LWLibavSource(r"$VideoPath")
clip = core.std.AssumeFPS(clip, fpsnum=$FPS, fpsden=1)
clip = core.neo_f3kdb.Deband(clip, y=64, cb=64, cr=64, output_depth=10, preset="nograin")
clip = core.std.SelectEvery(clip, cycle=clip.num_frames/10, offsets=range(round($FPS*sample_seconds/10)), modify_duration=0)
clip.set_output()
"@
    } else {
        $scriptContent = @"
AddAutoloadDir("X:\Apps\_VideoEncoding\StaxRip\Apps\FrameServer\AviSynth\plugins\")
LoadPlugin("X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\Dual\f3kdb Neo\neo-f3kdb.dll")
LoadPlugin("X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\Dual\L-SMASH-Works\LSMASHSource.dll")
LWLibavVideoSource("$VideoPath")
AssumeFPS($FPS)
neo_f3kdb(preset="nograin", output_depth=10)
SelectRangeEvery(every=FrameCount/10, length=int($FPS*$Duration/10), offset=0, audio=true)
"@
    }
    Set-Content -LiteralPath $Path -Value $scriptContent -Force
    Write-Log -Message "Скрипт $Type создан: $Path" -Severity Info
}

# Функция для запуска кодирования и сбора статистики
function Invoke-EncodingWithStats {
    param(
        [string]$InputScript,
        [string]$OutputFile,
        [string[]]$Params,
        [string]$ServerType,
        [double]$OriginalSize,
        [double]$FrameCount
    )
    
    Write-Log -Message "Подготовка к кодированию: $OutputFile" -Severity Info
    [string]$OutputIVFFile = [IO.Path]::ChangeExtension($OutputFile, 'ivf')
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    
    if (-not (Test-Path -LiteralPath $OutputFile)) {
        $ffmpegParams = @(
            "-y"
            "-hide_banner"
            "-v", "error"
            "-i", $InputScript
            "-pix_fmt", "yuv420p"
            "-f", "yuv4mpegpipe"
            "-strict", -1
            "-"
        )
    
        $encoderParams = $Params + @(
            "--output", $OutputIVFFile
            "--input", "stdin"
        )

        Write-Log -Message "Запуск кодировщика с параметрами: $($Params -join ' ')" -Severity Info
        Write-Log -Message (@(
                "& $($EncodingTools.FFmpeg) ${ffmpegParams} | & $($EncodingTools.AV1Encoder) ${encoderParams}"
            ) -join ' ') -Severity Debug

        if ($ServerType -eq 'VapourSynth') {
            Write-Log -Message "Использование VapourSynth в качестве фрейм-сервера" -Severity Debug
            & $EncodingTools.VSPipe -c y4m "$InputScript" - | & $EncodingTools.AV1Encoder @encoderParams
        }
        else {
            Write-Log -Message "Использование AviSynth в качестве фрейм-сервера" -Severity Debug
            & $EncodingTools.FFmpeg @ffmpegParams | & $EncodingTools.AV1Encoder @encoderParams
        }

        Write-Log -Message "Мультиплексирование в MKV контейнер" -Severity Info
        & mkvmerge.exe --ui-language en --priority lower --output-charset UTF8 --output $OutputFile $OutputIVFFile 2>&1
        if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $OutputFile)) {
            Write-Log -Message "Удаление временного IVF файла" -Severity Debug
            Remove-Item -LiteralPath $OutputIVFFile
        }
        else {
            Write-Log -Message "Ошибка мультиплексирования: LASTEXITCODE=$LASTEXITCODE" -Severity Error
            throw "mkvmerge failed with exit code: $LASTEXITCODE `r`n$result"
        }
    } else {
        Write-Log -Message "Файл $OutputFile уже существует, пропускаем кодирование" -Severity Info
    }
    
    $timer.Stop()
    $encodedSize = (Get-Item -LiteralPath $OutputFile).Length
    
    # Расчитываем VMAF
    . 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1'
    Write-Log -Message "Расчёт VMAF для $OutputFile..." -Severity Info
    $vmafScore = Get-VMAFValue -Distorted $OutputFile  -Reference $InputScript
    <# `                    -DurationSeconds $SampleDurationSeconds `
                            -MaxThreads ([Environment]::ProcessorCount) #>
    
    Write-Log -Message "Кодирование завершено: VMAF=$vmafScore, FPS=$([math]::Round($FrameCount / $timer.Elapsed.TotalSeconds, 2))" -Severity Info
    
    return @{
        Time = $timer.Elapsed
        Size = $encodedSize
        FPS  = [math]::Round($FrameCount / $timer.Elapsed.TotalSeconds, 2)
        VMAF = $vmafScore
    }
}
#endregion

#region MAIN EXECUTION BLOCK
# Основной процесс
Clear-Host
$error.Clear()
try {
    Write-Log -Message "Начало работы скрипта Create-TestVideoFiles" -Severity Info
    
    # Подготовка директории для работы
    $videoFile = Get-Item -LiteralPath $SourceVideoPath
    $workingDir = Join-Path -Path $videoFile.DirectoryName -ChildPath "$($videoFile.BaseName).tmp"
    Write-Log -Message "Создание рабочей директории: $workingDir" -Severity Info
    New-Item -Path $workingDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    
    # Получаем метаданные видео
    Write-Log -Message "Анализ исходного видео: $($videoFile.Name)" -Severity Info
    . 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1'
    $videoInfo = Get-VideoStats2 -VideoPath $videoFile.FullName
    $frameCount = $videoInfo.FPS * $SampleDurationSeconds
    $originalSize = $videoFile.Length
    Write-Log -Message "Метаданные видео: FPS=$($videoInfo.FPS), Длительность=$SampleDurationSeconds сек, Кадров=$frameCount" -Severity Info
    
    # Создание скрипта фрейм-сервера
    $scriptExtension = if ($FrameServer -eq 'VapourSynth') { 'vpy' } else { 'avs' }
    $scriptPath = Join-Path $workingDir "$($videoFile.BaseName).$scriptExtension"
    Write-Log -Message "Генерация скрипта ${FrameServer}: $scriptPath" -Severity Info
    New-FrameServerScript -Path $scriptPath -VideoPath $videoFile.FullName -Duration $SampleDurationSeconds -FPS $videoInfo.FPS -Type $FrameServer
    
    # Инициализация коллекции результатов
    $results = [System.Collections.Generic.List[EncodingResult]]::new()
    Write-Log -Message "Начало процесса кодирования с разными параметрами" -Severity Info
    
    # Перебираем все комбинации параметров
    foreach ($crf in $EncodingConfig.QualityLevels) {
        foreach ($preset in $EncodingConfig.EncodingPresets) {
            foreach ($param in $EncodingConfig.ExtraParams) {
                Write-Log -Message "Кодирование: CRF=$crf, Preset=$preset, Params=$param" -Severity Info
                
                $encoderParams = @(
                    "--rc", 0
                    "--crf", $crf
                    "--preset", $preset
                    "--progress", 3
                ) + ($param -split ' ')
                $outputFile = Join-Path $workingDir "test_crf=${crf}_preset=${preset}_$($param.Replace('--','').Replace(' ','=')).mkv"
                
                # Запуск кодирования и сбор статистики
                $stats = Invoke-EncodingWithStats -InputScript $scriptPath `
                    -OutputFile $outputFile `
                    -Params $encoderParams `
                    -ServerType $FrameServer `
                    -OriginalSize $originalSize `
                    -FrameCount $frameCount
                
                # Формирование объекта с результатами
                $result = [EncodingResult]@{
                    FileName         = (Split-Path $outputFile -Leaf)
                    Parameters       = $encoderParams -join " "
                    OriginalSizeMB   = [math]::Round($originalSize / 1MB, 2)
                    EncodedSizeMB    = [math]::Round($stats.Size / 1MB, 2)
                    VMAFScore        = [math]::Round($stats.VMAF, 2)
                    EncodingTime     = "{0:mm\:ss}" -f $stats.Time
                    EncodingFPS      = [math]::Round($stats.FPS, 2)
                    BitrateReduction = [math]::Round(($originalSize - $stats.Size) / $originalSize * 100, 2)
                    CompressionRatio = [math]::Round($originalSize / $stats.Size, 2)
                }
                $results.Add($result)
                Write-Log -Message "Результат: VMAF=$($result.VMAFScore), Сжатие=$($result.BitrateReduction)%, FPS=$($result.EncodingFPS)" -Severity Info
            }
        }
    }

    #region REPORT GENERATION
    # Формируем отчет
    Write-Log -Message "Формирование отчета о кодировании" -Severity Info
    $report = @"
# ========================== ОТЧЕТ О КОДИРОВАНИИ ==========================
# Исходный файл: $($videoFile.Name)
# Длительность: $SampleDurationSeconds сек. ($frameCount кадров)
# Исходный размер: {0:N2} MB
#
"@ -f ($originalSize / 1MB)

    $report += $results | ConvertTo-Csv -Delimiter "`t" -UseQuotes AsNeeded 

    # Сохраняем и выводим отчет
    $reportPath = Join-Path -Path $workingDir -ChildPath "encoding_report.csv"
    #$report | Out-File -LiteralPath $reportPath -Encoding utf8
    Write-Log -Message "Сохранение отчета в CSV: $reportPath" -Severity Info
    $results | Sort-Object VMAFScore -Descending | Export-Csv -LiteralPath $reportPath -Force -Delimiter "`t" -UseQuotes AsNeeded
    Write-Host $report
    
    # Дополнительный вывод в консоль
    Write-Host "`nОтчет сохранен в: $reportPath" -ForegroundColor Green
    Write-Host "Всего закодировано файлов: $($results.Count)" -ForegroundColor Green
    Write-Log -Message "Скрипт успешно завершен. Закодировано файлов: $($results.Count)" -Severity Info
    #endregion
}
catch {
    Write-Log -Message "Критическая ошибка: $($_.Exception.Message)" -Severity Error
    Write-Error "Ошибка выполнения: $error[0]"
    exit 1
}
#endregion