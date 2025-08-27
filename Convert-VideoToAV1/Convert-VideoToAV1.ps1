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
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$InputDirectory = 'y:\.temp\YT_y\Стендап комики 4k\Борис Зелигер\',
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$OutputDirectory = 'y:\.temp\AV1temp\',

    [Parameter(Mandatory = $false)]
    [Switch]$CopyFiletoTempDir = $false
)

# Импорт модулей
$modulesPath = Join-Path $PSScriptRoot "Modules" -Resolve
@("VideoProcessor.psm1", "AudioProcessor.psm1", "MetadataProcessor.psm1", "Utilities.psm1", "TempFileManager.psm1") | ForEach-Object {
    $modPath = Join-Path $modulesPath $_
    Import-Module $modPath -Force -ErrorAction Stop -Scope Global
}
Initialize-Configuration -ConfigPath (Join-Path -Path $PSScriptRoot -ChildPath "config.psd1")

foreach ($tool in $global:VideoTools.GetEnumerator()) {
    if (-not (Get-Command -Name $tool.Value -ErrorAction SilentlyContinue)) {
        Write-Error "Инструмент не найден: $($tool.Value)"
        exit 1
    }
    else {
        Write-Log "$($tool.Name):`t$($tool.Value)" Information -Category "Tools"
    }
}

# Улучшенный поиск файлов с более гибким фильтром
try {
    $videoFiles = Get-ChildItem -LiteralPath $InputDirectory -File -Filter '*.mkv' | 
        Where-Object { 
            # $_.Name -match '.*S03\.E0[6-7].*\.mkv$' -and 
            $_.Name -notmatch '_out\.mkv$' 
        } | 
        Sort-Object LastWriteTime
    Write-Log "Найдено файлов: $($videoFiles.Count)" -Severity Information -Category "Tools"
    if (-not $videoFiles) {
        Write-Error "В директории $InputDirectory не найдены MKV файлы"
        exit 1
    }
}
catch {
    Write-Error "Ошибка при поиске видеофайлов: $_"
    exit 1
}

# Обработка каждого файла
foreach ($videoFile in $videoFiles) {
    $job = $null
    try {
        Write-Log "Начало обработки файла: $($videoFile.Name)" -Severity Information -Category 'MainScript'

        # Установка рабочей директории
        $BaseName = [IO.Path]::GetFileNameWithoutExtension($videoFile.Name)
        $WorkingDir = Join-Path -Path $OutputDirectory -ChildPath "${BaseName}.tmp"
        if (-not (Test-Path -Path $WorkingDir)) {
            New-Item -Path $WorkingDir -ItemType Directory | Out-Null
        }

        $videoFileNameTmp = Join-Path -Path $OutputDirectory -ChildPath $videoFile.Name
        if ($CopyFiletoTempDir -and -not (Test-Path -LiteralPath $videoFileNameTmp)) {
            Copy-Item -Path $videoFile.FullName -Destination $videoFileNameTmp -Force
            $nfoSrc = [IO.Path]::ChangeExtension($videoFile.FullName, 'nfo')
            $nfoDst = [IO.Path]::ChangeExtension($videoFileNameTmp, 'nfo')
            $job.TempFiles.Add($videoFileTmp.FullName)
            if (Test-Path $nfoSrc) {
                Copy-Item -Path $nfoSrc -Destination $nfoDst -Force
            }
        }
        elseif (-not $CopyFiletoTempDir) {
            $videoFileNameTmp = $videoFile.FullName
        }

        $videoFileTmp = Get-Item -LiteralPath $videoFileNameTmp
        $videoFileOut = Join-Path -Path $WorkingDir -ChildPath "${BaseName}_out.mkv"

        if (Test-Path -LiteralPath $videoFileOut) {
            Write-Log "Выходной файл $(Split-Path $videoFileOut -Leaf) уже существует, пропускаем" -Severity Information -Category 'MainScript'
            continue
        }

        $job = @{
            VideoPath   = $videoFileTmp.FullName
            FinalOutput = $videoFileOut
            BaseName    = $BaseName
            WorkingDir  = $WorkingDir
            TempFiles   = [System.Collections.Generic.List[string]]::new()
            StartTime   = [DateTime]::Now
        }

        # Обработка аудио
        Write-Log "Конвертация аудио в Opus..." -Severity Verbose -Category 'Audio'
        $job = ConvertTo-OpusAudio -Job $job

        # Обработка метаданных
        Write-Log "Извлечение метаданных..." -Severity Verbose -Category 'Metadata'
        $job = Invoke-ProcessMetaData -Job $job
        Write-Log "Сохранение настроек..." -Severity Verbose -Category 'Muxing'
        ($job | ConvertTo-Json -Depth 10) | Out-File -LiteralPath "$($job.FinalOutput).json" -Encoding UTF8

        # Обработка видео
        $videoFileOut = Join-Path -Path $WorkingDir -ChildPath ("{0} - s{1:d2}e{2:d2} - {3} [{4}]_out.mkv" -f `
            $job.NFOFields.SHOWTITLE, `
            [int]$job.NFOFields.SEASON_NUMBER, `
            [int]$job.NFOFields.PART_NUMBER, `
            $job.NFOFields.TITLE, `
            $job.NFOFields.AIR_DATE)
        $job.FinalOutput = $videoFileOut
        Write-Log "Конвертация видео в AV1..." -Severity Verbose -Category 'Video'
        $job = ConvertTo-Av1Video -Job $job
        Write-Log "Сохранение настроек..." -Severity Verbose -Category 'Muxing'
        ($job | ConvertTo-Json -Depth 10) | Out-File -LiteralPath "$($job.FinalOutput).json" -Encoding UTF8

        # Финализация
        Write-Log "Создание итогового файла..." -Severity Verbose -Category 'Muxing'
        Complete-MediaFile -Job $job

        Write-Log "Сохранение настроек..." -Severity Verbose -Category 'Muxing'
        ($job | ConvertTo-Json -Depth 10) | Out-File -LiteralPath "$($job.FinalOutput).json" -Encoding UTF8

        # Оценка качества видео
        # Write-Log "Оценка качества видео..." -Severity Verbose -Category 'Video'
        # Get-VideoQualityMetrics `
        #     -DistortedPath $Job.VideoOutput `
        #     -ReferencePath $Job.VideoPath `
        #     -ModelVersion 'vmaf_4k_v0.6.1' `
        #     -Metrics VMAF `
        #     -VMAFPoolMethod mean `
        #     -Subsample 3 `
        #     -Vebose

        $duration = [DateTime]::Now - $job.StartTime
        Write-Log "Файл успешно обработан: $($job.FinalOutput) (Время: $($duration.ToString('hh\:mm\:ss')))" -Severity Success -Category 'Main'
    }
    catch {
        Write-Log "Ошибка при обработке $($videoFileTmp.Name): $_" -Severity Error -Category 'Main'
        if ($job) {
            #Remove-TemporaryFiles -Job $job
        }
    }
    finally {
        if ($global:Config.Processing.DeleteTempFiles -and $job) {
            #Remove-TemporaryFiles -Job $job
        }
    }
}

