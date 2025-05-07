<# ===========================================================================================
.SYNOPSIS
    Набор утилит для работы с видеофайлами
.DESCRIPTION
    Содержит функции для анализа видео, сравнения качества, извлечения метаданных и работы с цветовыми параметрами
#>

# Загрузка внешних функций
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\function_Invoke-Executable.ps1'

enum libVmafPool {
    mean
    harmonic_mean
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

<# ===========================================================================================
.SYNOPSIS
    Получает значение XPSNR между двумя видеофайлами
.DESCRIPTION
    Вычисляет метрику XPSNR (расширенный PSNR) между искаженным и эталонным видео
.PARAMETER Distorted
    Путь к искаженному видеофайлу
.PARAMETER Reference
    Путь к эталонному видеофайлу
.PARAMETER TrimStartSeconds
    Начальная точка обрезки в секундах
.PARAMETER DurationSeconds
    Длительность сегмента для анализа
.PARAMETER Pool
    Метод агрегации результатов (mean или harmonic_mean)
.PARAMETER OutputLog
    Путь к файлу лога
#>
function Get-XPSNRValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distorted,
        [Parameter(Mandatory = $true)]
        [string]$Reference,
        [int]$TrimStartSeconds = 0,
        [int]$DurationSeconds = 0,
        [libVmafPool]$Pool = [libVmafPool]::harmonic_mean,
        [string]$OutputLog
    )

    $prmXPSNR = @(
        '-filter_complex "'
        if ($TrimStartSeconds -gt 0 -and $DurationSeconds -gt 0) {
            "[0:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds)[dist];"
            "[1:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds)[ref];"
        }
        else { "[0:v]null[dist];[1:v]null[ref];" }
        "[dist][ref]"
        "xpsnr=eof_action=endall"
        '"'
    )

    $cmdXPSNR = @(
        "-hide_banner -y -nostats"
        ('-i "{0}" -i "{1}"' -f $Distorted, $Reference)
        ($prmXPSNR -join "")
        "-an -sn -dn -f null -"
    ) -join " "

    Write-Verbose "Запуск ffmpeg с параметрами: $cmdXPSNR"
    $outputPSNR = Invoke-Executable -sExeFile 'ffmpeg' -cArgs $cmdXPSNR -sWorkDir (Get-Location).Path 
    $regexp = '.*XPSNR  y: (?<xpsnr_y>\d+\.?\d+).*u: (?<xpsnr_u>\d+\.?\d+).*v: (?<xpsnr_v>\d+\.?\d+)'
    
    if ($outputPSNR.StdErr -match $regexp) {
        $xpsnr = @{
            Y   = [double]$Matches.xpsnr_y
            U   = [double]$Matches.xpsnr_u
            V   = [double]$Matches.xpsnr_v
            AVG = [double]($Matches.xpsnr_y, $Matches.xpsnr_u, $Matches.xpsnr_v | Measure-Object -Average).Average
        }
    }
    else {
        throw "Не удалось извлечь значение XPSNR из вывода"
    }
    
    if (-not $xpsnr.AVG) {
        throw "Не удалось извлечь значение XPSNR из вывода"
    }
    return [double]$xpsnr.AVG
}

<# ===========================================================================================
.SYNOPSIS
    Получает значение VMAF между двумя видеофайлами
.DESCRIPTION
    Вычисляет метрику VMAF (Video Multi-Method Assessment Fusion) между искаженным и эталонным видео
#>
function Get-VMAFValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distorted,
        [Parameter(Mandatory = $true)]
        [string]$Reference,
        [int]$MaxThreads = [Environment]::ProcessorCount,
        [int]$TrimStartSeconds = 0,
        [int]$DurationSeconds = 0,
        [string]$ModelVersion = 'vmaf_4k_v0.6.1',
        [ValidateSet('json', 'xml', 'csv')]
        [string]$LogFormat = 'json',
        [string]$OutputLog
    )

    $prmVMAF = @(
        '-filter_complex "'
        if ($TrimStartSeconds -gt 0 -and $DurationSeconds -gt 0) {
            "[0:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds),settb=AVTB,setpts=PTS-STARTPTS[dist];"
            "[1:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds),settb=AVTB,setpts=PTS-STARTPTS[ref];"
        }
        else { "[0:v]null[dist];[1:v]null[ref];" }
        ("[dist][ref]libvmaf=eof_action=endall",
        "log_fmt=$($LogFormat)",
        "log_path='$($OutputLog)'",
        "n_threads=$($MaxThreads)",
        "n_subsample=3",
        "pool=$($Pool)",
        "model=version=$($ModelVersion)" -join ':')
        '"'
    )

    $cmdVMAF = @(
        "-hide_banner -y -nostats",
        ('-i "{0}" -i "{1}"' -f $Distorted, $Reference)
        ($prmVMAF -join ""),
        "-an -sn -dn -f null -"
    ) -join " "

    Write-Verbose "Запуск ffmpeg с параметрами: $cmdVMAF"
    $outputVMAF = Invoke-Executable -sExeFile 'ffmpeg' -cArgs $cmdVMAF -sWorkDir (Get-Location).Path
    $vmaf = $outputVMAF.StdErr | Select-String "VMAF score: (\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    
    if (-not $vmaf) {
        throw "Не удалось извлечь значение VMAF из вывода"
    }
    return [double]$vmaf
}

<# ===========================================================================================
.SYNOPSIS
    Получает количество аудиоканалов в файле
.PARAMETER AudioFilePath
    Путь к аудиофайлу
#>
function Get-AudioTrackChannels {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AudioFilePath
    )
    
    $outAudioChannels = & ffprobe -v error -show_entries stream=channels `
        -of default=noprint_wrappers=1:nokey=1 "$AudioFilePath" 2>&1
    return [Int16]$outAudioChannels
}


<# ===========================================================================================
By Workik & Deepchat v.4
.SYNOPSIS
Calculates average video bitrate using packet-level statistics from ffprobe.

.DESCRIPTION
When stream doesn't contain bit_rate metadata, calculates it by analyzing individual packets
using ffprobe's packet inspection capability.

.PARAMETER VideoFilePath
    Путь к видеофайлу
#>
function Get-VideoStatsAI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$VideoFilePath
    )
    
    try {
        $videoFile = Get-Item -LiteralPath $VideoFilePath -ErrorAction Stop
        
        # Get all video stream info in one ffprobe call
        $streamMetadata = & ffprobe -v error -select_streams v:0 `
            -show_entries stream=width,height,r_frame_rate,nb_read_packets,nb_frames,duration `
            -show_entries format=size `
            -of json "$VideoFilePath" | ConvertFrom-Json -AsHashtable
        
        # Calculate FPS from ratio
        $framesPerSecond = if ($streamMetadata.streams[0].r_frame_rate -match '(\d+)/(\d+)') {
            [math]::Round([decimal]$matches[1] / [decimal]$matches[2], 3)
        } else {
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
        } else {
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
        } else {
            [math]::Round($frameCountFromPackets / $framesPerSecond, 3)
        }

        $durationFromMetadata = if ($streamMetadata.streams[0].duration) {
            [math]::Round([double]$streamMetadata.streams[0].duration, 3)
        } else {
            $durationFromFrames
        }
        
        # Build result object
        return [PSCustomObject]@{
            FilePath            = $VideoFilePath
            FileName            = $videoFile.Name
            FileSizeBytes       = $videoFile.Length
            VideoDataSizeBytes  = $videoDataSize
            ResolutionWidth     = [int]$streamMetadata.streams[0].width
            ResolutionHeight    = [int]$streamMetadata.streams[0].height
            FrameRate           = $framesPerSecond
            FrameCount          = $frameCountFromNbFrames
            FrameCountPackets   = $frameCountFromPackets
            FrameCountStream    = $frameCountFromStream
            DurationSeconds     = $durationFromMetadata
            DurationFromFrames  = $durationFromFrames
            DurationFromPackets = [math]::Round($durationFromPackets, 3)
            FormattedDuration   = "{0:hh\:mm\:ss}" -f [timespan]::fromseconds($durationFromMetadata)
            BitrateKbps         = $videoBitrate
            StreamMetadata      = $streamMetadata.streams[0]
            PacketMetadata      = $packetMetadata
        }
    }
    catch {
        Write-Error "Error processing video file '$VideoFilePath': $_"
        throw
    }
}


<# ===========================================================================================
.SYNOPSIS
    Сравнивает качество двух видеофайлов
.DESCRIPTION
    Вычисляет метрики VMAF и XPSNR между двумя видеофайлами
#>
function Get-VideoQuality {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distorted,
        [Parameter(Mandatory = $true)]
        [string]$Reference,
        [switch]$calcXPSNR,
        [switch]$calcVMAF,
        [int]$TrimStartSeconds = 0,
        [int]$DurationSeconds = 0,
        [int]$MaxThreads = [Environment]::ProcessorCount,
        [switch]$WriteLog = $false
    )

    # Проверка существования файлов
    if (-not (Test-Path -LiteralPath $Distorted)) {
        throw "Искаженный видеофайл не найден: $Distorted"
    }
    if (-not (Test-Path -LiteralPath $Reference)) {
        throw "Эталонный видеофайл не найден: $Reference"
    }

    # Создание временных файлов для логов
    if ($WriteLog) {
        $logXPSNR = [System.IO.Path]::ChangeExtension($Distorted, "xpsnr.log").Replace('\', '/').Replace(':', '\:')
        $logVMAF = [System.IO.Path]::ChangeExtension($Distorted, "vmaf.json").Replace('\', '/').Replace(':', '\:')
    }

    try {
        # Установка рабочей директории
        Set-Location -LiteralPath (Get-Item -LiteralPath $Distorted).Directory.FullName

        # Получение информации о видео с помощью Get-VideoStatsAI
        $distortedStats = Get-VideoStatsAI -VideoFilePath $Distorted
        $referenceStats = Get-VideoStatsAI -VideoFilePath $Reference

        # Проверка совместимости видео
        if ($distortedStats.ResolutionWidth -ne $referenceStats.ResolutionWidth -or 
            $distortedStats.ResolutionHeight -ne $referenceStats.ResolutionHeight) {
            Write-Warning "Разрешения видео не совпадают: $($distortedStats.ResolutionWidth)x$($distortedStats.ResolutionHeight) vs $($referenceStats.ResolutionWidth)x$($referenceStats.ResolutionHeight)"
        }

        # Расчет XPSNR
        $xpsnr = if ($calcXPSNR) {
            Get-XPSNRValue -Distorted $Distorted `
                -Reference $Reference `
                -TrimStartSeconds $TrimStartSeconds `
                -DurationSeconds $DurationSeconds `
                -OutputLog $logXPSNR
        }

        # Расчет VMAF
        $vmaf = if ($calcVMAF) {
            Get-VMAFValue -Distorted $Distorted `
                -Reference $Reference `
                -TrimStartSeconds $TrimStartSeconds `
                -DurationSeconds $DurationSeconds `
                -OutputLog $logVMAF `
                -MaxThreads $MaxThreads
        }

        return [PSCustomObject]@{
            VMAF  = $vmaf
            XPSNR = $xpsnr
            DistortedStats = $distortedStats
            ReferenceStats = $referenceStats
        }
    }
    catch {
        Write-Error "Ошибка при сравнении видео: $_"
        throw
    }
    finally {
        # Очистка временных файлов
        if (-not $WriteLog) {
            if ($logXPSNR -and (Test-Path -LiteralPath $logXPSNR)) {
                Remove-Item -LiteralPath $logXPSNR -Force
            }
            if ($logVMAF -and (Test-Path -LiteralPath $logVMAF)) {
                Remove-Item -LiteralPath $logVMAF -Force
            }
        }
    }
}


<#
.SYNOPSIS
    Получает цветовые параметры видеофайла
#>
function Get-VideoColorParams {
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


<# ===========================================================================================
.SYNOPSIS
    Получает параметры кодирования для аудио
.DESCRIPTION
    Генерирует параметры кодирования аудио для ffmpeg на основе исходного файла
#>
function Get-FFmpegAudioParameters {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFileName,
        [ValidateSet('libopus', 'libfdk_aac')]
        [string]$Codec = 'libopus',
        [int]$MaxChannels = 0
    )

    # Получение информации об аудиодорожках
    $consoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $audioTracks = (. ffprobe -v error -select_streams a -show_entries `
            "stream=index,codec_name,channels,channel_layout:stream_disposition:stream_tags=language,title" `
            -of json "$InputFileName") | ConvertFrom-Json
    [Console]::OutputEncoding = $consoleEncoding

    $audioParams = @()
    $trackIndex = 0
    
    foreach ($track in $audioTracks.streams) {
        $channels = $track.channels
        $channelLayout = $track.channel_layout

        # Ограничение количества каналов
        if ($MaxChannels -gt 0 -and $channels -gt $MaxChannels) {
            $channels = $MaxChannels
        }

        # Установка битрейта в зависимости от кодеков
        $bitrate = switch ($Codec) {
            'libopus' {
                switch ($channels) {
                    { $_ -le 2 } { '160k'; break }
                    { $_ -le 6 } { '384k'; break }
                    default { '512k' }
                }
            }
            'libfdk_aac' {
                switch ($channels) {
                    { $_ -le 2 } { '192k'; break }
                    { $_ -le 6 } { '512k'; break }
                    default { '768k' }
                }
            }
        }

        # Формирование параметров для дорожки
        $trackParams = @(
            "-map 0:a:$trackIndex"
            "-c:a:$trackIndex $Codec"
            if ($Codec -eq 'libfdk_aac') { "-vbr 5" }
            else { "-b:a:$trackIndex $bitrate" }
            "-ac:a:$trackIndex $channels"
        )

        # Добавление информации о каналах
        if ($channels -ne $track.channels -and $channelLayout -like "*(side)*") {
            $trackParams += "-af:a:$trackIndex aformat=channel_layouts='7.1|5.1|stereo'"
        }

        # Добавление метаданных
        if ($track.tags.language) {
            $trackParams += "-metadata:s:a:$trackIndex language=$($track.tags.language)"
        }
        if ($track.tags.title) {
            $trackParams += "-metadata:s:a:$trackIndex title='$($track.tags.title)'"
        }
        elseif ($track.disposition.original -eq 1) {
            $trackParams += "-metadata:s:a:$trackIndex title='Original Audio'"
        }

        $audioParams += ($trackParams -join ' ')
        $trackIndex++
    }

    return $audioParams
}



# ===========================================================================================
# ===========================================================================================
function Get-VideoColorMappings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoPath
    )

    $colorParams = Get-VideoColorParams -VideoPath $VideoPath
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

<# ===========================================================================================
.SYNOPSIS
    Сохраняет метаданные видеофайла в XML и JSON форматах.
.DESCRIPTION
    Извлекает теги из видеофайла с помощью ffprobe и сохраняет их в XML (для MKVToolNix) 
    и JSON (для удобного чтения) форматах.
.PARAMETER VideoFilePath
    Путь к видеофайлу для извлечения тегов.
#>
function Save-VideoTags {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$VideoFilePath
    )
    
    $excludedTags = @('Writing application', 'Writing library', 'ENCODER')
    
    try {
        # Получаем теги с помощью ffprobe
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $videoTags = (. ffprobe -v error -show_entries format_tags -of json "$VideoFilePath") | ConvertFrom-Json
        [Console]::OutputEncoding = $originalEncoding

        # Создаем XML в формате MKVToolNix
        $xmlDocument = New-Object System.Xml.XmlDocument
        $xmlDocument.AppendChild($xmlDocument.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
        $rootElement = $xmlDocument.CreateElement("Tags")
        $xmlDocument.AppendChild($rootElement) | Out-Null
        $tagElement = $xmlDocument.CreateElement("Tag")
        $rootElement.AppendChild($tagElement) | Out-Null

        foreach ($tag in $videoTags.format.tags.PSObject.Properties) {
            if ($tag.Name -notin $excludedTags) {
                $simpleElement = $xmlDocument.CreateElement("Simple")
                $nameElement = $xmlDocument.CreateElement("Name")
                $nameElement.InnerText = [System.Web.HttpUtility]::HtmlEncode($tag.Name)
                $simpleElement.AppendChild($nameElement) | Out-Null
                $valueElement = $xmlDocument.CreateElement("String")
                $valueElement.InnerText = [System.Web.HttpUtility]::HtmlEncode($tag.Value)
                $simpleElement.AppendChild($valueElement) | Out-Null
                $tagElement.AppendChild($simpleElement) | Out-Null
            }
        }

        # Сохраняем теги в XML
        $xmlFilePath = [System.IO.Path]::ChangeExtension($VideoFilePath, "tags.xml")
        $xmlDocument.Save($xmlFilePath)

        # Сохраняем теги в JSON
        $jsonFilePath = [System.IO.Path]::ChangeExtension($VideoFilePath, "tags.json")
        $videoTags.format | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonFilePath -Encoding utf8 -Force
        
        Write-Host "Теги сохранены в: $jsonFilePath"
        return $jsonFilePath
    }
    catch {
        Write-Error "Ошибка сохранения тегов видео: $_"
        Write-Host $_
    }
}


<#
.SYNOPSIS
    Устанавливает теги для видеофайла из JSON файла.
.DESCRIPTION
    Применяет теги к видеофайлу с помощью mkvpropedit, используя JSON файл с метаданными.
.PARAMETER VideoFilePath
    Путь к видеофайлу для применения тегов.
.PARAMETER TagsFilePath
    Путь к JSON файлу с тегами.
#>
function Set-VideoTags {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$VideoFilePath,
        
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$TagsFilePath
    )
    
    try {
        # Read tags from JSON
        # $tags = Get-Content -LiteralPath $TagsPath -Raw | ConvertFrom-Json
        
        # Build mkvpropedit commands
        $mkvpropeditArgs = @('"--tags global:{0}"' -f $TagsFilePath)
        # foreach ($tag in $tags.format.tags.PSObject.Properties) {

        #     $commands += "--set ""$($tag.Name)=$($tag.Value)"""
        # }
        
        # Применяем теги
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $result = & mkvpropedit "$VideoFilePath" $mkvpropeditArgs
        [Console]::OutputEncoding = $originalEncoding
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Теги успешно применены к: $VideoFilePath"
            return $true
        }
        else {
            throw "Ошибка mkvpropedit (код $LASTEXITCODE): `r`n$result"
        }
    }
    catch {
        Write-Error "Ошибка применения тегов: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Конвертирует видеофайл в формат MKV.
.DESCRIPTION
    Использует mkvmerge для конвертации видеофайла в контейнер MKV.
.PARAMETER InputVideoFilePath
    Путь к исходному видеофайлу.
.PARAMETER OutputVideoFilePath
    Путь для сохранения MKV файла (по умолчанию - то же имя с расширением .mkv).
#>
function ConvertTo-MKV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$InputVideoFilePath,

        [Parameter(Mandatory = $false)]
        [string]$OutputVideoFilePath = ([IO.Path]::ChangeExtension($InputVideoFilePath, 'mkv'))
    )

    begin {
        # Проверяем наличие mkvmerge
        if (-not (Get-Command mkvmerge.exe -ErrorAction SilentlyContinue)) {
            throw "mkvmerge.exe не найден в PATH. Установите MKVToolNix."
        }
    }

    process {
        try {
            $mkvmergeArgs = @(
                '--ui-language', 'en'
                '--priority', 'lower'
                '--output', $OutputVideoFilePath
                $InputVideoFilePath
            )

            $process = Start-Process -FilePath 'mkvmerge.exe' -ArgumentList $mkvmergeArgs -NoNewWindow -Wait -PassThru
            
            if ($process.ExitCode -ne 0) {
                throw "Ошибка mkvmerge (код $($process.ExitCode))"
            }
            
            [PSCustomObject]@{
                InputPath  = $InputVideoFilePath
                OutputPath = $OutputVideoFilePath
                Success    = $true
            }
        }
        catch {
            Write-Error "Ошибка создания MKV файла: $_"
            [PSCustomObject]@{
                InputPath  = $InputVideoFilePath
                OutputPath = $OutputVideoFilePath
                Success    = $false
                Error      = $_.Exception.Message
            }
        }
    }
}


<#
.SYNOPSIS
    Распаковывает ZIP архивы из указанной папки.
.DESCRIPTION
    Извлекает содержимое всех ZIP архивов в указанную папку назначения.
.PARAMETER SourceFolderPath
    Путь к папке с ZIP архивами.
.PARAMETER DestinationFolderPath
    Путь для извлечения содержимого архивов.
.PARAMETER Overwrite
    Перезаписывать существующие файлы (по умолчанию - нет).
.PARAMETER CreateSubfolderForEachArchive
    Создавать отдельную подпапку для каждого архива (по умолчанию - нет).
#>
function Expand-ZipArchives {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$SourceFolderPath,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolderPath,
        
        [switch]$Overwrite = $false,
        [switch]$CreateSubfolderForEachArchive = $false
    )

    # Проверяем существование исходной папки
    if (-not (Test-Path -LiteralPath $SourceFolderPath -PathType Container)) {
        Write-Error "Исходная папка не существует: $SourceFolderPath"
        return
    }

    # Создаем папку назначения если ее нет
    if (-not (Test-Path -LiteralPath $DestinationFolderPath)) {
        try {
            New-Item -ItemType Directory -Path $DestinationFolderPath -Force | Out-Null
        }
        catch {
            Write-Error "Ошибка создания папки назначения: $_"
            return
        }
    }

    # Загружаем .NET сборку для работы с ZIP
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Находим все ZIP файлы в исходной папке
    $zipArchives = Get-ChildItem -LiteralPath $SourceFolderPath -Filter *.zip -File

    if ($zipArchives.Count -eq 0) {
        Write-Warning "ZIP архивы не найдены в исходной папке: ${SourceFolderPath}"
        return
    }

    # Обрабатываем каждый архив с отображением прогресса
    $totalArchives = $zipArchives.Count
    $processedArchives = 0

    foreach ($archive in $zipArchives) {
        try {
            # Обновляем прогресс
            $processedArchives++
            $percentComplete = [math]::Floor(($processedArchives / $totalArchives) * 100)
            Write-Progress -Activity "Распаковка ZIP архивов" `
                -Status "Обработка $($archive.Name) ($processedArchives из $totalArchives)" `
                -PercentComplete $percentComplete

            if ($CreateSubfolderForEachArchive) {
                # Создаем подпапку с именем архива (без расширения)
                $extractionPath = Join-Path -Path $DestinationFolderPath -ChildPath $archive.BaseName
            }
            else {
                $extractionPath = $DestinationFolderPath
            }

            # Создаем папку для извлечения
            if (-not (Test-Path -LiteralPath $extractionPath)) {
                New-Item -ItemType Directory -Path $extractionPath | Out-Null
            }

            # Извлекаем архив
            if ($Overwrite) {
                # Перезаписываем существующие файлы
                [System.IO.Compression.ZipFile]::ExtractToDirectory($archive.FullName, $extractionPath, $true)
            }
            else {
                # Не перезаписываем существующие файлы
                [System.IO.Compression.ZipFile]::ExtractToDirectory($archive.FullName, $extractionPath)
            }

            # Удаляем архив после извлечения
            Remove-Item -LiteralPath $archive.FullName -Force
        }
        catch {
            Write-Error "Ошибка извлечения $($archive.Name): $_"
        }
    }

    # Очищаем индикатор прогресса
    Write-Progress -Activity "Распаковка ZIP архивов" -Completed
}