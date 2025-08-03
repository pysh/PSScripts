<#
.SYNOPSIS
    Конвертирует видеофайлы в формат AV1 с сохранением аудио, субтитров и метаданных

.DESCRIPTION
    Скрипт обрабатывает видеофайлы в указанной директории, конвертируя видео в AV1,
    аудио в Opus, сохраняя все метаданные, субтитры и вложения.

.PARAMETER InputDirectory
    Директория с исходными видеофайлами (по умолчанию 'r:\Temp\_to_encode\')

.PARAMETER OutputDirectory
    Директория для сохранения результатов (по умолчанию 'r:\Temp\_to_encode\')

.EXAMPLE
    .\Convert-VideoToAV1.ps1 -InputDirectory "C:\Videos\Source" -OutputDirectory "C:\Videos\Encoded"
#>

using namespace System.IO

param (
    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
    [string]$InputDirectory = 'r:\Temp\_to_encode\',

    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
    [string]$OutputDirectory = $InputDirectory
)

# Импорт модулей
$modulesPath = Join-Path $PSScriptRoot "Modules" -Resolve
Import-Module (Join-Path $modulesPath "VideoProcessor.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path $modulesPath "AudioProcessor.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path $modulesPath "MetadataProcessor.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path $modulesPath "Utilities.psm1") -Force -ErrorAction Stop

# Глобальная конфигурация инструментов
$global:VideoTools = @{
    VSPipe      = 'vspipe.exe'
    SvtAv1Enc   = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp_orig.exe'
    OpusEnc     = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\opus\opusenc.exe'
    FFmpeg      = 'X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.exe'
    FFprobe     = 'ffprobe.exe'
    MkvMerge    = 'mkvmerge.exe'
    MkvExtract  = 'mkvextract.exe'
    MkvPropedit = 'mkvpropedit.exe'
}

# Проверка доступности инструментов
foreach ($tool in $global:VideoTools.GetEnumerator()) {
    if (-not (Get-Command $tool.Value -ErrorAction SilentlyContinue)) {
        Write-Error "Инструмент не найден: $($tool.Value)"
        exit 1
    }
}

# Поиск видеофайлов
try {
    $videoFiles = Get-ChildItem -LiteralPath $InputDirectory -Filter "*.mkv" -Exclude "*_out.*" -File -Recurse:$false -ErrorAction Stop
    
    if (-not $videoFiles) {
        Write-Error "В директории $InputDirectory не найдены MKV файлы"
        exit 1
    }
}
catch {
    Write-Error "Ошибка при поиске видеофайлов: $_"
    exit 1
}


# Очистка консоли и обработка каждого файла
Clear-Host
foreach ($videoFile in $videoFiles) {
    try {
        Write-Log "Начало обработки файла: $($videoFile.Name)" -Severity Information -Category 'Main'
        
        # Установка рабочей директории
        # $WorkingDir = $OutputDirectory
        $BaseName   = [IO.Path]::GetFileNameWithoutExtension($videoFile.Name)
        $WorkingDir = Join-Path -Path ${OutputDirectory} -ChildPath "${BaseName}.tmp"
        if (-not (Test-Path $WorkingDir -PathType Container)) {
            New-Item -Path $WorkingDir -ItemType Directory | Out-Null
        }
        
        # Инициализация задачи
        $job = @{
            VideoPath   = $videoFile.FullName
            BaseName    = $BaseName
            WorkingDir  = $WorkingDir
            TempFiles   = [System.Collections.Generic.List[string]]::new()
            StartTime   = [DateTime]::Now
        }

        # Обработка видео
        Write-Log "Конвертация видео в AV1..." -Severity Verbose -Category 'Video'
        $job = ConvertTo-Av1Video -Job $job
        
        # Обработка аудио
        Write-Log "Конвертация аудио в Opus..." -Severity Verbose -Category 'Audio'
        $job = ConvertTo-OpusAudio -Job $job
        
        # Обработка метаданных
        Write-Log "Извлечение метаданных..." -Severity Verbose -Category 'Metadata'
        $job = Invoke-ProcessMetaData -Job $job
        
        # Финализация
        Write-Log "Создание итогового файла..." -Severity Verbose -Category 'Muxing'
        Complete-MediaFile -Job $job
        
        $duration = [DateTime]::Now - $job.StartTime
        Write-Log "Файл успешно обработан: $($job.FinalOutput) (Время: $($duration.ToString('hh\:mm\:ss')))" -Severity Success -Category 'Main'
    }
    catch {
        Write-Log "Ошибка при обработке $($videoFile.Name): $_" -Severity Error -Category 'Main'
        Remove-TemporaryFiles -Job $job
    }
}