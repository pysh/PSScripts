<#
.SYNOPSIS
    Utility functions module
#>

function Get-AudioMetadata {
    param(
        [Parameter(Mandatory)]
        [string]$VideoFilePath
    )

    $originalEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $ffprobeOutput = & $global:VideoTools.FFprobe -v error -select_streams a `
        -show_entries stream=index,codec_name,channels:stream_tags=language,title:disposition=default,forced,comment `
        -of json $VideoFilePath | ConvertFrom-Json
    [Console]::OutputEncoding = $originalEncoding
    
    return $ffprobeOutput.streams | ForEach-Object {
        [PSCustomObject]@{
            Index     = $_.index
            CodecName = $_.codec_name
            Channels  = $_.channels
            Language  = $_.tags.language
            Title     = $_.tags.title
            Default   = $_.disposition.default
            Forced    = $_.disposition.forced
            Comment   = $_.disposition.comment
        }
    }
}

function Cleanup-FailedJob {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )

    foreach ($file in $Job.TempFiles) {
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

function Get-VSVideoInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$VpyPath
    )

    # Получаем информацию через vspipe --info
    $vspInfo = (& vspipe --info $VpyPath 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Ошибка выполнения vspipe: $vspInfo"
        return $null
    }

    # Регулярное выражение для разбора строк "Key: Value"
    $regexpString = '^(?<name>.*?):\s*(?<value>.*)$'

    # Создаём хеш-таблицу и заполняем её
    $infoHash = @{}
    $vspInfo | ForEach-Object {
        if ($_ -match $regexpString) {
            $infoHash[$Matches.name] = $Matches.value
        }
    }

    # Преобразуем в объект и возвращаем
    return [PSCustomObject]$infoHash
}

function Get-VideoCropParametersAC2 {
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

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
            
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Success')]
        [string]$Severity = 'Info',

        [string]$Category,
            
        [switch]$NoNewLine
    )

    $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss.fff")
    $logMessage = "[$timestamp] [$Severity]$(if($Category){ " [$Category]" })`t$Message"

    $color = switch ($Severity) {
        'Success' { 'Green' }
        'Debug'   { 'DarkGray' }
        'Info'    { 'Cyan' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'White' }
    }

    if ($NoNewLine) {
        Write-Host $logMessage -ForegroundColor $color -NoNewline
    }
    else {
        Write-Host $logMessage -ForegroundColor $color
    }

    # Дополнительное логирование в файл или систему можно добавить здесь
}


Export-ModuleMember -Function Get-AudioMetadata, Get-VideoCropParametersAC2, Cleanup-FailedJob, Get-VSVideoInfo, Write-Log