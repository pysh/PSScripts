<#
.SYNOPSIS
    Конвертирует видеофайлы в формат AV1 с обрезкой по времени
.DESCRIPTION
    Обрабатывает видеофайлы, конвертируя видео в AV1, аудио в Opus,
    с поддержкой обрезки по времени и сохранением всех метаданных.
#>

using namespace System.IO

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$InputDirectory = 'v:\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\season 06\',
    
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = (Join-Path -Path $InputDirectory -ChildPath '.av1'),

    [Parameter(Mandatory = $false)]
    [string]$InputFilesFilter = '',
    
    [Parameter(Mandatory = $false)]
    [Switch]$CopyFiletoTempDir = $false,
    
    [Parameter(Mandatory = $false)]
    [int]$TrimStartFrame = 0,
    
    [Parameter(Mandatory = $false)]
    [double]$TrimStartSeconds = 0,
    
    [Parameter(Mandatory = $false)]
    [int]$TrimEndFrame = 0,
    
    [Parameter(Mandatory = $false)]
    [double]$TrimEndSeconds = 0,
    
    [Parameter(Mandatory = $false)]
    [string]$TrimTimecode = "",
    
    [Parameter(Mandatory = $false)]
    [System.Object]$CropParameters = @{
        Left   = 0
        Right  = 0
        Top    = 0
        Bottom = 0
    },

    # Параметр для выбора энкодера (значение по умолчанию установим позже)
    [Parameter(Mandatory = $false)]
    [ValidateSet('SvtAv1Enc', 'SvtAv1EncESS', 'SvtAv1EncHDR', 'SvtAv1EncPSYEX', 'Rav1eEnc', 'AomAv1Enc')]
    [string]$Encoder
)

begin {
    # Импорт модулей
    $modulesPath = Join-Path $PSScriptRoot "Modules"
    @("VideoProcessor.psm1", "AudioProcessor.psm1", "MetadataProcessor.psm1", "Utilities.psm1", "TempFileManager.psm1") | ForEach-Object {
        Import-Module (Join-Path $modulesPath $_) -Force -ErrorAction Stop
    }
    
    Initialize-Configuration -ConfigPath (Join-Path -Path $PSScriptRoot -ChildPath "config.psd1")
    
    # Устанавливаем значение по умолчанию для Encoder после загрузки конфига
    if (-not $PSBoundParameters.ContainsKey('Encoder')) {
        $Encoder = $global:Config.Encoding.DefaultEncoder
    }
    
    # Проверка инструментов
    foreach ($tool in $global:VideoTools.GetEnumerator()) {
        if (-not (Get-Command -Name $tool.Value -ErrorAction SilentlyContinue)) {
            throw "Инструмент не найден: $($tool.Value)"
        }
        Write-Log "$($tool.Name):`t$($tool.Value)" Information -Category "Tools"
    }
    
    if(-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    Write-Log "Выбран энкодер: $Encoder" -Severity Information -Category "Main"
}

process {
    try {
        # Поиск видеофайлов
        $videoFiles = Get-ChildItem -LiteralPath $InputDirectory -File |
            Where-Object {
                $_.Extension -match 'mkv|mp4' -and
                $_.Name -notmatch '_out\.mkv$'
            }
        if (-not [string]::IsNullOrWhiteSpace($InputFilesFilter)) { $videoFiles = @($videoFiles | Where-Object { $_.Name -match $InputFilesFilter }) }

        if (-not $videoFiles) {
            Write-Error "В директории $InputDirectory не найдены MKV/MP4 файлы"
            return
        }
        
        Write-Log "Найдено файлов: $($videoFiles.Count)" -Severity Information -Category "Main"

        # Обработка каждого файла
        foreach ($videoFile in $videoFiles) {
            $job = $null
            try {
                Write-Log "Начало обработки файла: $($videoFile.Name)" -Severity Information -Category 'Main'
                
                # Определяем тип файла
                $fileExtension = [System.IO.Path]::GetExtension($videoFile.Name).ToLower()
                $isMP4 = $fileExtension -eq '.mp4'
                
                # Создание рабочей директории
                $BaseName = [IO.Path]::GetFileNameWithoutExtension($videoFile.Name)
                $WorkingDir = Join-Path -Path $OutputDirectory -ChildPath "${BaseName}.tmp"
                New-Item -Path $WorkingDir -ItemType Directory -Force | Out-Null
                
                # Копирование файла при необходимости
                $videoFileNameTmp = if ($CopyFiletoTempDir) {
                    $dest = Join-Path -Path $OutputDirectory -ChildPath $videoFile.Name
                    if (-not (Test-Path -LiteralPath $dest)) {
                        Copy-Item -Path $videoFile.FullName -Destination $dest -Force
                        # Копирование NFO файла
                        $nfoSrc = [IO.Path]::ChangeExtension($videoFile.FullName, 'nfo')
                        $nfoDst = [IO.Path]::ChangeExtension($dest, 'nfo')
                        if (Test-Path $nfoSrc) { Copy-Item -Path $nfoSrc -Destination $nfoDst -Force }
                    }
                    $dest
                } else {
                    $videoFile.FullName
                }
                
                $videoFileTmp = Get-Item -LiteralPath $videoFileNameTmp
                
                # Инициализация job
                $job = @{
                    VideoPath   = $videoFileTmp.FullName
                    BaseName    = $BaseName
                    WorkingDir  = $WorkingDir
                    TempFiles   = [System.Collections.Generic.List[string]]::new()
                    StartTime   = [DateTime]::Now
                    IsMP4       = $isMP4
                    CropParams  = $CropParameters
                }
                
                # Устанавливаем выбранный энкодер
                $job.Encoder = $Encoder
                $job.EncoderPath = Get-EncoderPath -EncoderName $Encoder
                $encoderConfig = Get-EncoderConfig -EncoderName $Encoder
                $job.EncoderParams = Get-EncoderParams -EncoderName $Encoder -EncoderConfig $encoderConfig

                
                
                Write-Log "Параметры энкодера: $($encoderConfig | ConvertTo-Json -Compress)" -Severity Verbose -Category 'Video'
                Write-Log "Путь к энкодеру: $($job.EncoderPath)" -Severity Verbose -Category 'Video'
                
                # 1. ОБРАБОТКА МЕТАДАННЫХ (первым делом)
                Write-Log "Этап 1/3: Обработка метаданных" -Severity Information -Category 'Main'
                
                if ($isMP4) {
                    $job = Invoke-ProcessMP4Metadata -Job $job
                } else {
                    $job = Invoke-ProcessMetaData -Job $job
                }
                
                # Формирование имени выходного файла на основе метаданных
                $finalOutputName = "${BaseName}_out.mkv"  # значение по умолчанию
                
                if ($job.NFOFields) {
                    try {
                        # Получаем информацию о разрешении видео
                        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams v:0 `
                            -show_entries stream=width,height,codec_name -of json $job.VideoPath | ConvertFrom-Json
                        
                        $width = $ffprobeOutput.streams[0].width
                        $height = $ffprobeOutput.streams[0].height
                        
                        # Определяем разрешение по ширине
                        $resolution = switch ($width) {
                            { $_ -gt 3840 } { "8k"; break }
                            { $_ -gt 2560 } { "4k"; break }
                            { $_ -gt 1920 } { "2k"; break }
                            { $_ -gt 1280 } { "1080p"; break }
                            default { "${_}p" }
                        }

                        # Форматируем дату
                        $airDate = if ($job.NFOFields.AIR_DATE) { $job.NFOFields.AIR_DATE } else { $job.NFOFields.DATE_RELEASED }
                        if ($airDate -and $airDate -match "^\d{4}-\d{2}-\d{2}") {
                            $airDateFormatted = $airDate
                        } else {
                            $airDateFormatted = "0000-00-00"
                        }
                        
                        # Формируем имя файла
                        $finalOutputName = "{0} - s{1:00}e{2:00} - {3} [{4}][{5}][av1]_out.mkv" -f `
                            $job.NFOFields.SHOWTITLE,
                            [int]$job.NFOFields.SEASON_NUMBER,
                            [int]$job.NFOFields.PART_NUMBER,
                            $job.NFOFields.TITLE,
                            $airDateFormatted,
                            $resolution
                        
                        # Заменяем недопустимые символы в имени файла
                        $invalidChars = [IO.Path]::GetInvalidFileNameChars()
                        foreach ($char in $invalidChars) {
                            $finalOutputName = $finalOutputName.Replace($char, '_')
                        }
                        
                        Write-Log "Сформировано имя выходного файла: $finalOutputName" -Severity Information -Category 'Main'
                    }
                    catch {
                        Write-Log "Ошибка при формировании имени файла: $_" -Severity Warning -Category 'Metadata'
                    }
                }
                
                $job.FinalOutput = Join-Path -Path $OutputDirectory -ChildPath $finalOutputName
                
                if (Test-Path -LiteralPath $job.FinalOutput) {
                    Write-Log "Выходной файл уже существует, пропускаем: $finalOutputName" -Severity Information -Category 'Main'
                    continue
                }
                
                # Получение framerate для расчетов обрезки
                $frameRate = Get-VideoFrameRate -VideoPath $job.VideoPath
                $job.FrameRate = $frameRate
                
                # Расчет параметров обрезки
                $job.TrimStartSeconds = if ($TrimStartFrame -gt 0) { 
                    $TrimStartFrame / $frameRate 
                } elseif ($TrimTimecode) { 
                    ConvertTo-Seconds -TimeString $TrimTimecode -FrameRate $frameRate
                } else { 
                    $TrimStartSeconds 
                }
                
                $job.TrimDurationSeconds = if ($TrimEndFrame -gt 0 -and $TrimStartFrame -gt 0) { 
                    ($TrimEndFrame - $TrimStartFrame) / $frameRate 
                } elseif ($TrimEndSeconds -gt 0 -and $TrimStartSeconds -gt 0) { 
                    $TrimEndSeconds - $TrimStartSeconds 
                } else { 
                    0 
                }
                
                Write-Log "Параметры обрезки: Start=$($job.TrimStartSeconds)s, Duration=$($job.TrimDurationSeconds)s" -Severity Information -Category 'Main'
                
                # 2. ОБРАБОТКА АУДИО (второй этап)
                $audioMode = if ($global:Config.Encoding.Audio.CopyAudio) { "копирование" } else { "перекодирование в Opus" }
                Write-Log "Этап 2/3: Обработка аудио ($audioMode)" -Severity Information -Category 'Main'
                $job = ConvertTo-OpusAudio -Job $job

                # 3. ОБРАБОТКА ВИДЕО (третий, самый долгий этап)
                Write-Log "Этап 3/3: Обработка видео" -Severity Information -Category 'Main'
                $job = ConvertTo-Av1Video -Job $job -Debug
                
                # ФИНАЛИЗАЦИЯ
                Write-Log "Создание итогового файла" -Severity Information -Category 'Main'
                Complete-MediaFile -Job $job
                
                $duration = [DateTime]::Now - $job.StartTime
                Write-Log "Файл успешно обработан: $($job.FinalOutput) (Время: $($duration.ToString('hh\:mm\:ss')))" -Severity Success -Category 'Main'

                <#
                # Расчет VMAF
                Write-Log "Расчёт VMAF..." -Severity Information -Category 'VMAF'
                $gqmParams = @{
                    DistortedPath = $job.FinalOutput
                    ReferencePath = $job.ScriptFile
                    TrimStartSeconds = $job.TrimStartSeconds
                    DurationSeconds = $job.TrimDurationSeconds
                    Metrics = 'VMAF'
                    Subsample = 5
                }
                try {
                    # $quality = Get-VideoQualityMetrics @gqmParams
                    $job.Quality = $quality.VMAF
                    Write-Log "VMAF: $($quality.VMAF)" -Severity Information -Category 'VMAF'
                }
                catch {
                    $job.Quality = 0
                    Write-Log "Ошибка при расчёте VMAF: $_" -Severity Error -Category 'VMAF'
                }
                #>

                $NewFileName = [IO.Path]::ChangeExtension($job.FinalOutput, ("_[{0:0.00}].mkv" -f $quality.VMAF))
                # Сохранение настроек
                ($job | ConvertTo-Json -Depth 10) | Out-File -LiteralPath "${NewFileName}.json" -Encoding UTF8

                Rename-Item -LiteralPath $job.FinalOutput -NewName $NewFileName
                $job.FinalOutput = $NewFileName
            }
            catch {
                Write-Log "Ошибка при обработке $($videoFile.Name): $_" -Severity Error -Category 'Main'
            }
            finally {
                if ($job -and $global:Config.Processing.DeleteTempFiles) {
                    Remove-TemporaryFiles -Job $job
                }
            }
        }
    }
    catch {
        Write-Log "Критическая ошибка: $_" -Severity Error -Category 'Main'
    }
}

end {
    Write-Log "Обработка завершена" -Severity Information -Category 'Main'
}