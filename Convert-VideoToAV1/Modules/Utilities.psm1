<#
.SYNOPSIS
    Модуль вспомогательных функций
#>

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
<# 
function Get-VideoCropParameters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$InputFile,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$ThresholdBegin = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$ThresholdEnd = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$LuminanceThreshold = 1000,

        [ValidateSet(2, 4, 8, 16, 32)]
        [int]$Round = 2
    )
    
    function RoundToNearestMultiple {
        param([int]$Value, [int]$Multiple)
        if ($Multiple -eq 0) { return $Value }
        return [Math]::Round($Value / $Multiple) * $Multiple
    }

    try {
        Write-Log "Определение параметров обрезки для файла: $InputFile" -Severity Information -Category 'Video'
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
        
        Write-Log "Запуск AutoCrop для определения обрезки" -Severity Verbose -Category 'Video'
        $autocropOutput = & $AutoCropPath $tmpScriptFile $acFrameCount $acFrameInterval 144 144 $LuminanceThreshold 0
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка выполнения AutoCrop (код $LASTEXITCODE)"
        }
        
        $cropLine = $autocropOutput | Select-Object -Last 1
        $cropParams = $cropLine -split ',' | ForEach-Object { [int]$_ }

        $result = [PSCustomObject]@{
            Left           = RoundToNearestMultiple -Value $cropParams[0] -Multiple $Round
            Top            = RoundToNearestMultiple -Value $cropParams[1] -Multiple $Round
            Right          = RoundToNearestMultiple -Value $cropParams[2] -Multiple $Round
            Bottom         = RoundToNearestMultiple -Value $cropParams[3] -Multiple $Round
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
#>

function Get-VideoCropParameters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$InputFile,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$ThresholdBegin = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$ThresholdEnd = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$LuminanceThreshold = 1000,

        [ValidateSet(2, 4, 8, 16, 32)]
        [int]$Round = 2
    )
    
    function RoundToNearestMultiple {
        param([int]$Value, [int]$Multiple)
        if ($Multiple -eq 0) { return $Value }
        return [Math]::Round($Value / $Multiple) * $Multiple
    }

    try {
        Write-Log "Определение параметров обрезки для файла: $InputFile" -Severity Information -Category 'Video'
        $tmpScriptFile = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), 'vpy')
        
        # Получаем путь к директории модуля
        $moduleDir = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Module.Path)
        $templatePath = Join-Path -Path $moduleDir -ChildPath "AutoCropTemplate.vpy"
        
        if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
            throw "Файл шаблона VapourSynth не найден: $templatePath"
        }

        # Читаем шаблон и заменяем плейсхолдер
        $scriptContent = Get-Content -LiteralPath $templatePath -Raw
        $scriptContent = $scriptContent -replace '\{input_file\}', $InputFile

        Set-Content -LiteralPath $tmpScriptFile -Value $scriptContent -Force

        $AutoCropPath = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Support\AutoCrop\AutoCrop.exe'
        $acFrameCount = 2
        $acFrameInterval = 400
        
        Write-Log "Запуск AutoCrop для определения обрезки" -Severity Verbose -Category 'Video'
        $autocropOutput = & $AutoCropPath $tmpScriptFile $acFrameCount $acFrameInterval 144 144 $LuminanceThreshold 0
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка выполнения AutoCrop (код $LASTEXITCODE)"
        }
        
        $cropLine = $autocropOutput | Select-Object -Last 1
        $cropParams = $cropLine -split ',' | ForEach-Object { [int]$_ }

        $result = [PSCustomObject]@{
            Left           = RoundToNearestMultiple -Value $cropParams[0] -Multiple $Round
            Top            = RoundToNearestMultiple -Value $cropParams[1] -Multiple $Round
            Right          = RoundToNearestMultiple -Value $cropParams[2] -Multiple $Round
            Bottom         = RoundToNearestMultiple -Value $cropParams[3] -Multiple $Round
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

Export-ModuleMember -Function Get-AudioTrackInfo, Remove-TemporaryFiles, Get-VideoScriptInfo, Get-VideoCropParameters, Write-Log