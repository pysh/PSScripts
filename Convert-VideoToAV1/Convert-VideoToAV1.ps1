<#
.SYNOPSIS
    Конвертирует видеофайлы в формат AV1/HEVC через универсальный конвейер
.DESCRIPTION
    Обрабатывает видеофайлы любого формата, ремукся их в MKV, затем конвертируя видео в AV1/HEVC,
    аудио в Opus, с поддержкой обрезки и сохранением всех метаданных.
#>

using namespace System.IO

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$InputDirectory = 'v:\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\BDREMUX\Season_10\',
    
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = (Join-Path -Path $InputDirectory -ChildPath '.enc'),
    
    [Parameter(Mandatory = $false)]
    [string]$InputFilesFilter = 'S10E10',
    
    [Parameter(Mandatory = $false)]
    [string]$TempDir = 'r:\.temp\',
    
    [Parameter(Mandatory = $false)]
    [Switch]$CopyFiletoTempDir = $true,
    
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
    [bool]$CopyAudio = $true,
    
    [Parameter(Mandatory = $false)]
    [bool]$CopyVideo = $false,
    
    [Parameter(Mandatory = $false)]
    [System.Object]$CropParameters,
    
    [Parameter(Mandatory = $false)]
    [string]$Encoder = "x265.film_grain",
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$TemplatePath = 'g:\Видео\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\HD_Script_TWD_s10.vpy',
    
    [Parameter(Mandatory = $false)]
    [switch]$ForceRemux = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepRemuxedFiles = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$ListEncoders = $false
)

begin {
    # Splash
    Write-Host @'
  ____                          _     __     ___     _          _____       ___     ___ 
 / ___|___  _ ____   _____ _ __| |_   \ \   / (_) __| | ___  __|_   _|__   / \ \   / / |
| |   / _ \| '_ \ \ / / _ \ '__| __|___\ \ / /| |/ _` |/ _ \/ _ \| |/ _ \ / _ \ \ / /| |
| |__| (_) | | | \ V /  __/ |  | ||_____\ V / | | (_| |  __/ (_) | | (_) / ___ \ V / | |
 \____\___/|_| |_|\_/ \___|_|   \__|     \_/  |_|\__,_|\___|\___/|_|\___/_/   \_\_/  |_|
'@ -ForegroundColor DarkBlue
    
    # Вспомогательные функции
    function New-VideoJob {
        [CmdletBinding()]
        param(
            [string]$VideoPath,
            [string]$BaseName,
            [string]$WorkingDir,
            [string]$OriginalPath,
            [bool]$IsRemuxed,
            [object]$CropParams,
            [bool]$CopyAudioOverride
        )
        
        $job = @{
            VideoPath         = $VideoPath
            BaseName          = $BaseName
            WorkingDir        = $WorkingDir
            TempFiles         = [System.Collections.Generic.List[string]]::new()
            StartTime         = [DateTime]::Now
            IsRemuxed         = $IsRemuxed
            OriginalPath      = $OriginalPath
            CropParams        = $CropParams
            CopyAudioOverride = $CopyAudioOverride
        }
        
        return $job
    }
    
    function Get-OutputFilename {
        [CmdletBinding()]
        param([hashtable]$Job)
        
        try {
            # Получаем код энкодера
            $encoderCode = Get-EncoderCode -EncoderName $Job.Encoder
            
            if ($Job.NFOFields) {
                # Получаем информацию о разрешении видео
                $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams v:0 `
                    -show_entries stream=width,height,codec_name -of json $Job.VideoPath | ConvertFrom-Json
                
                $width = $ffprobeOutput.streams[0].width
                $height = $ffprobeOutput.streams[0].height
                
                # Определяем разрешение
                $resolution = switch ($width) {
                    { $_ -gt 3840 } { "8k"; break }
                    { $_ -gt 2560 } { "4k"; break }
                    { $_ -gt 1920 } { "2k"; break }
                    { $_ -gt 1280 } { "1080p"; break }
                    default { "${height}p" }
                }
                
                # Форматируем дату
                $airDate = if ($Job.NFOFields.AIR_DATE) { $Job.NFOFields.AIR_DATE } else { $Job.NFOFields.DATE_RELEASED }
                if ($airDate -and $airDate -match "^\d{4}-\d{2}-\d{2}") {
                    $airDateFormatted = $airDate
                } else {
                    $airDateFormatted = "0000-00-00"
                }
                
                # Формируем имя файла
                $finalOutputName = "{0} - s{1:00}e{2:00} - {3} [{4}][{5}][{6}]_out.mkv" -f `
                    $Job.NFOFields.SHOWTITLE,
                [int]$Job.NFOFields.SEASON_NUMBER,
                [int]$Job.NFOFields.PART_NUMBER,
                $Job.NFOFields.TITLE,
                $airDateFormatted,
                $resolution,
                $encoderCode
                
                # Заменяем недопустимые символы
                $invalidChars = [IO.Path]::GetInvalidFileNameChars()
                foreach ($char in $invalidChars) {
                    $finalOutputName = $finalOutputName.Replace($char, '_')
                }
                
                Write-Log "Сформировано имя выходного файла: $finalOutputName" -Severity Information -Category 'Main'
                return $finalOutputName
            }
        }
        catch {
            Write-Log "Ошибка при формировании имени файла: $_" -Severity Warning -Category 'Metadata'
        }
        
        # Значение по умолчанию
        return "$($Job.BaseName)_[$encoderCode]_out.mkv"
    }
    
    function Get-TrimParameters {
        [CmdletBinding()]
        param(
            [hashtable]$Job,
            [int]$TrimStartFrame,
            [double]$TrimStartSeconds,
            [int]$TrimEndFrame,
            [double]$TrimEndSeconds,
            [string]$TrimTimecode
        )
        
        $result = @{
            StartSeconds = 0
            DurationSeconds = 0
        }
        
        # Расчет стартового времени
        if ($TrimStartFrame -gt 0) {
            $result.StartSeconds = $TrimStartFrame / $Job.FrameRate
        }
        elseif ($TrimTimecode) {
            $result.StartSeconds = ConvertTo-Seconds -TimeString $TrimTimecode -FrameRate $Job.FrameRate
        }
        else {
            $result.StartSeconds = $TrimStartSeconds
        }
        
        # Расчет продолжительности
        if ($TrimEndFrame -gt 0 -and $TrimStartFrame -gt 0) {
            $result.DurationSeconds = ($TrimEndFrame - $TrimStartFrame) / $Job.FrameRate
        }
        elseif ($TrimEndSeconds -gt 0 -and $TrimStartSeconds -gt 0) {
            $result.DurationSeconds = $TrimEndSeconds - $TrimStartSeconds
        }
        
        return $result
    }
    
    function Measure-VideoQuality {
        [CmdletBinding()]
        param([hashtable]$Job)
        
        try {
            Write-Log "Расчёт VMAF..." -Severity Information -Category 'VMAF'
            
            $gqmParams = @{
                DistortedPath     = $Job.FinalOutput
                ReferencePath     = $Job.ScriptFile
                TrimStartSeconds  = $Job.TrimStartSeconds
                DurationSeconds   = $Job.TrimDurationSeconds
                Metrics           = 'VMAF'
                Subsample         = 5
            }
            
            $quality = Get-VideoQualityMetrics @gqmParams
            $Job.Quality = $quality.VMAF
            
            Write-Log "VMAF: $($quality.VMAF)" -Severity Information -Category 'VMAF'
            
            # Переименование файла с VMAF в имени
            if ($quality.VMAF -gt 0) {
                $NewFileName = [IO.Path]::ChangeExtension($Job.FinalOutput, ("_[{0:0.00}].mkv" -f $quality.VMAF))
                Rename-Item -LiteralPath $Job.FinalOutput -NewName $NewFileName
                $Job.FinalOutput = $NewFileName
            }
        }
        catch {
            $Job.Quality = 0
            Write-Log "Ошибка при расчёте VMAF: $_" -Severity Error -Category 'VMAF'
        }
    }
    
    function Save-EncodingSettings {
        [CmdletBinding()]
        param([hashtable]$Job)
        
        try {
            $settingsFile = [IO.Path]::ChangeExtension($Job.FinalOutput, "json")
            ($Job | ConvertTo-Json -Depth 10) | Out-File -LiteralPath $settingsFile -Encoding UTF8
            Write-Log "Настройки сохранены: $settingsFile" -Severity Information -Category 'Main'
        }
        catch {
            Write-Log "Ошибка сохранения настроек: $_" -Severity Warning -Category 'Main'
        }
    }
    
    function Remove-TemporaryFiles {
        [CmdletBinding()]
        param([hashtable]$Job)
        
        $removedCount = 0
        foreach ($file in $Job.TempFiles) {
            try {
                if (Test-Path -LiteralPath $file) {
                    Remove-Item -LiteralPath $file -Force -Recurse -ErrorAction SilentlyContinue
                    $removedCount++
                }
            }
            catch {
                Write-Log "Не удалось удалить временный файл ${file}: $_" -Severity Warning -Category 'Main'
            }
        }
        Write-Log "Удалено $removedCount временных файлов" -Severity Information -Category 'Main'
    }
    
    # Импорт модулей
    $modulesPath = Join-Path $PSScriptRoot "Modules"
    @("VideoProcessor.psm1", "AudioProcessor.psm1", "MetadataProcessor.psm1", 
        "Utilities.psm1", "TempFileManager.psm1", "RemuxProcessor.psm1",
        "ColorProcessor.psm1") | ForEach-Object {
            Import-Module (Join-Path $modulesPath $_) -Force -ErrorAction Stop
    }
    
    Initialize-Configuration -ConfigPath (Join-Path -Path $PSScriptRoot -ChildPath "config.psd1")
    
    # Если запрошен список энкодеров - показываем и выходим
    if ($ListEncoders) {
        Write-Host "`nДоступные энкодеры и пресеты:" -ForegroundColor Cyan
        Write-Host ("=" * 50)
        
        $availableEncoders = Get-AvailableEncoders -Format "Display"
        foreach ($enc in $availableEncoders) {
            Write-Host "$($enc.FullName)" -ForegroundColor Green -NoNewline
            Write-Host " - $($enc.DisplayName)"
        }
        
        Write-Host "`nПример использования:" -ForegroundColor Yellow
        Write-Host "  .\Convert-VideoToAV1.ps1 -Encoder 'x265.film_grain'" -ForegroundColor White
        Write-Host "  .\Convert-VideoToAV1.ps1 -Encoder 'SvtAv1EncESS.grain_optimized'" -ForegroundColor White
        
        exit 0
    }
    
    # Устанавливаем энкодер по умолчанию из конфига
    if (-not $PSBoundParameters.ContainsKey('Encoder')) {
        $Encoder = $global:Config.Encoding.DefaultEncoder
        Write-Log "Используется энкодер по умолчанию: $Encoder" -Severity Information -Category 'Config'
    }
    
    # Валидация выбранного энкодера
    $encoderCheck = Test-EncoderPreset -EncoderName $Encoder
    if (-not $encoderCheck.IsAvailable) {
        throw "Энкодер '$Encoder' не найден. Используйте -ListEncoders для просмотра доступных вариантов."
    }
    
    if (-not $encoderCheck.HasConfig) {
        # Если указан только базовый энкодер, используем пресет 'main'
        $Encoder = "$($encoderCheck.BaseEncoder).main"
        Write-Log "Используется пресет по умолчанию: $Encoder" -Severity Information -Category 'Config'
    }
    
    # ПЕРЕОПРЕДЕЛЕНИЕ ПАРАМЕТРОВ КОНФИГА
    if ($PSBoundParameters.ContainsKey('CopyAudio')) {
        $global:Config.Encoding.Audio.CopyAudio = $CopyAudio
        Write-Log "Переопределен CopyAudio: $CopyAudio" -Severity Information -Category 'Config'
    }
    
    if ($PSBoundParameters.ContainsKey('CopyVideo')) {
        $global:Config.Encoding.Video.CopyVideo = $CopyVideo
        Write-Log "Переопределен CopyVideo: $CopyVideo" -Severity Information -Category 'Config'
    }
    
    # Проверка инструментов
    foreach ($tool in $global:VideoTools.GetEnumerator()) {
        if (-not (Get-Command -Name $tool.Value -ErrorAction SilentlyContinue)) {
            throw "Инструмент не найден: $($tool.Value)"
        }
        Write-Log "$($tool.Name):`t$($tool.Value)" Information -Category "Tools"
    }
    
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    
    Write-Log "Выбран энкодер: $Encoder" -Severity Information -Category "Main"
}

process {
    try {
        # Поиск видеофайлов (поддерживаемые форматы)
        $supportedFormats = Get-SupportedVideoFormats
        $videoFiles = Get-ChildItem -LiteralPath $InputDirectory -File |
        Where-Object {
            $_.Extension.ToLower() -in $supportedFormats -and
            $_.Name -notmatch '_out\.mkv$'
        }
        
        if (-not [string]::IsNullOrWhiteSpace($InputFilesFilter)) { 
            $videoFiles = @($videoFiles | Where-Object { $_.Name -match $InputFilesFilter }) 
        }
        
        if (-not $videoFiles) {
            Write-Error "В директории $InputDirectory не найдены видеофайлы поддерживаемых форматов"
            return
        }
        
        Write-Log "Найдено файлов: $($videoFiles.Count)" -Severity Information -Category "Main"
        
        # Обработка каждого файла
        foreach ($videoFile in $videoFiles) {
            $job = $null
            try {
                Write-Log "Начало обработки файла: $($videoFile.Name)" -Severity Information -Category 'Main'
                
                # Создание рабочей директории
                $BaseName = [IO.Path]::GetFileNameWithoutExtension($videoFile.Name)
                $WorkingDir = Join-Path -Path $TempDir -ChildPath "${BaseName}.tmp"
                New-Item -Path $WorkingDir -ItemType Directory -Force | Out-Null
                
                # ============================================
                # УНИВЕРСАЛЬНАЯ ПОДГОТОВКА ФАЙЛА
                # ============================================
                
                $isMKV = [System.IO.Path]::GetExtension($videoFile.Name).ToLower() -eq '.mkv'
                $needsRemux = $ForceRemux -or (-not $isMKV) -or (Test-NeedRemux -FilePath $videoFile.FullName)
                
                if ($needsRemux) {
                    # Ремуксим файл в MKV
                    Write-Log "Ремукс файла в MKV..." -Severity Information -Category 'Remux'
                    
                    $remuxedFile = Join-Path -Path $WorkingDir -ChildPath "${BaseName}_remuxed.mkv"
                    
                    # Используем универсальный ремукс
                    $remuxResult = Convert-ToMKVUniversal `
                        -InputFile $videoFile.FullName `
                        -OutputFile $remuxedFile `
                        -KeepTempFiles:$KeepRemuxedFiles
                    
                    if ($remuxResult -and (Test-Path -LiteralPath $remuxedFile)) {
                        Write-Log "Ремукс завершен: $([System.IO.Path]::GetFileName($remuxedFile))" -Severity Success -Category 'Remux'
                        
                        # Создаем Job с ремукснутым файлом
                        $job = New-VideoJob -VideoPath $remuxedFile `
                            -BaseName $BaseName `
                            -WorkingDir $WorkingDir `
                            -OriginalPath $videoFile.FullName `
                            -IsRemuxed $true `
                            -CropParams $CropParameters `
                            -CopyAudioOverride $CopyAudio
                        
                        $job.TempFiles.Add($remuxedFile)
                    } else {
                        throw "Ремукс не удался"
                    }
                } else {
                    # Используем оригинальный MKV файл
                    Write-Log "Используется оригинальный MKV файл" -Severity Information -Category 'Main'
                    
                    $videoFileNameTmp = if ($CopyFiletoTempDir) {
                        $dest = Join-Path -Path $TempDir -ChildPath $videoFile.Name
                        if (-not (Test-Path -LiteralPath $dest)) {
                            Copy-Item -Path $videoFile.FullName -Destination $dest -Force
                        }
                        $dest
                    } else {
                        $videoFile.FullName
                    }
                    
                    $job = New-VideoJob -VideoPath $videoFileNameTmp `
                        -BaseName $BaseName `
                        -WorkingDir $WorkingDir `
                        -OriginalPath $videoFile.FullName `
                        -IsRemuxed $false `
                        -CropParams $CropParameters `
                        -CopyAudioOverride $CopyAudio
                    
                    if ($CopyFiletoTempDir -and ($videoFileNameTmp -ne $videoFile.FullName)) {
                        $job.TempFiles.Add($videoFileNameTmp)
                    }
                }
                
                # Устанавливаем выбранный энкодер
                $job.Encoder = $Encoder
                
                # Копируем NFO файл если есть
                $nfoSrc = [IO.Path]::ChangeExtension($job.OriginalPath, 'nfo')
                if (Test-Path -LiteralPath $nfoSrc) {
                    $nfoDst = Join-Path -Path $WorkingDir -ChildPath "$BaseName.nfo"
                    Copy-Item -LiteralPath $nfoSrc -Destination $nfoDst -Force
                    $job.TempFiles.Add($nfoDst)
                    Write-Log "NFO файл скопирован" -Severity Information -Category 'Metadata'
                }
                
                # 1. ОБРАБОТКА МЕТАДАННЫХ
                Write-Log "Этап 1/3: Обработка метаданных" -Severity Information -Category 'Main'
                $job = Invoke-ProcessMetaData -Job $job
                
                # Формирование имени выходного файла на основе метаданных
                $finalOutputName = Get-OutputFilename -Job $job
                $job.FinalOutput = Join-Path -Path $OutputDirectory -ChildPath $finalOutputName
                
                if (Test-Path -LiteralPath $job.FinalOutput) {
                    Write-Log "Выходной файл уже существует, пропускаем: $finalOutputName" -Severity Information -Category 'Main'
                    continue
                }
                
                # Получение framerate для расчетов обрезки
                $frameRate = Get-VideoFrameRate -VideoPath $job.VideoPath
                $job.FrameRate = $frameRate
                
                # Расчет параметров обрезки
                $trimParams = Get-TrimParameters -Job $job `
                    -TrimStartFrame $TrimStartFrame `
                    -TrimStartSeconds $TrimStartSeconds `
                    -TrimEndFrame $TrimEndFrame `
                    -TrimEndSeconds $TrimEndSeconds `
                    -TrimTimecode $TrimTimecode
                
                $job.TrimStartSeconds = $trimParams.StartSeconds
                $job.TrimDurationSeconds = $trimParams.DurationSeconds
                
                Write-Log "Параметры обрезки: Start=$($job.TrimStartSeconds)s, Duration=$($job.TrimDurationSeconds)s" `
                    -Severity Information -Category 'Main'
                
                # Получаем конфигурацию энкодера
                $encoderConfig = Get-EncoderConfig -EncoderName $Encoder
                $job.EncoderPath = Get-EncoderPath -EncoderName $encoderConfig.BaseEncoder
                $job.EncoderParams = Get-EncoderParams -EncoderName $Encoder -EncoderConfig $encoderConfig
                
                Write-Log "Параметры энкодера: $($encoderConfig.DisplayName ?? $Encoder)" -Severity Information -Category 'Video'
                
                # 2. ОБРАБОТКА АУДИО
                $audioMode = if ($global:Config.Encoding.Audio.CopyAudio) { "копирование" } else { "перекодирование в Opus" }
                Write-Log "Этап 2/3: Обработка аудио ($audioMode)" -Severity Information -Category 'Main'
                $job = ConvertTo-OpusAudio -Job $job
                
                # 3. ОБРАБОТКА ВИДЕО
                Write-Log "Этап 3/3: Обработка видео" -Severity Information -Category 'Main'
                $job = ConvertTo-Av1Video -Job $job -TemplatePath $TemplatePath
                
                # ФИНАЛИЗАЦИЯ
                Write-Log "Создание итогового файла" -Severity Information -Category 'Main'
                Complete-MediaFile -Job $job
                
                $duration = [DateTime]::Now - $job.StartTime
                Write-Log "Файл успешно обработан: $($job.FinalOutput) (Время: $($duration.ToString('hh\:mm\:ss')))" `
                    -Severity Success -Category 'Main'
                
                # Опционально: Расчет VMAF
                if ($global:Config.Processing.CalculateVMAF -eq $true) {
                    Measure-VideoQuality -Job $job
                }
                
                # Сохранение настроек
                Save-EncodingSettings -Job $job
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