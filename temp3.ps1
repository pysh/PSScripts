<#
.SYNOPSIS
    Video encoding script using VapourSynth and FFmpeg
.DESCRIPTION
    Encodes video files using VapourSynth pipeline and FFmpeg with x265 encoder
#>

# Configuration
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Paths and Executables
$tools = @{
    FFmpeg = 'ffmpeg.exe'
    VSPipe = 'vspipe.exe'
}

# Input and Output Configuration
$paths = @{
    InputScript = 'g:\Видео\Сериалы\Отечественные\Аутсорс\сезон 01\Autsors.S01.2025.WEB-DL.HEVC.2160p.SDR.ExKinoRay\test\test.vpy'
    OutputFile  = 'g:\Видео\Сериалы\Отечественные\Аутсорс\сезон 01\Autsors.S01.2025.WEB-DL.HEVC.2160p.SDR.ExKinoRay\test\test_x265_crf23-slower.mkv'
}

# Encoding Parameters
$encodingParams = @{
    Input        = '-'
    VideoEncoder = 'libx265'
    CRF          = 23
    Preset       = 'slower'
    AudioCodec   = 'copy'
    Format       = 'matroska'
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Info','Warning','Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $colors = @{
        'Info'    = 'Cyan'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }
    
    Write-Host $logMessage -ForegroundColor $colors[$Level]
}

function Test-RequiredTools {
    foreach ($tool in $tools.Values) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required tool not found: $tool"
        }
    }
}

function Start-EncodingProcess {
    try {
        Write-Log "Starting video encoding process" -Level Info
        
        # Validate paths
        if (-not (Test-Path -LiteralPath $paths.InputScript)) {
            throw "Input VPY script not found: $($paths.InputScript)"
        }

        # Create output directory if needed
        $outputDir = Split-Path -Path $paths.OutputFile -Parent
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # Build FFmpeg command
        $ffmpegArgs = @(
            '-hide_banner',
            '-y',
            '-i', $encodingParams.Input
            '-c:v', $encodingParams.VideoEncoder,
            '-crf', $encodingParams.CRF,
            '-preset', $encodingParams.Preset,
            '-an',#'-c:a', $encodingParams.AudioCodec,
            '-f', $encodingParams.Format,
            $paths.OutputFile
        )

        # Execute the pipeline
        Write-Log "Executing encoding pipeline..." -Level Info
        
        & $tools.VSPipe -c y4m $paths.InputScript - | 
            & $tools.FFmpeg $ffmpegArgs

        if ($LASTEXITCODE -ne 0) {
            throw "Encoding failed with exit code $LASTEXITCODE"
        }

        Write-Log "Encoding completed successfully" -Level Info
        return $true
    }
    catch {
        Write-Log "Encoding error: $_" -Level Error
        return $false
    }
}

# Main execution
try {
    Clear-Host
    Write-Log "Starting video encoding script" -Level Info
    
    # Load external functions
    . 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\function_Invoke-Executable.ps1' -ErrorAction Stop
    
    # Check required tools
    Test-RequiredTools
    
    # Start encoding
    if (-not (Start-EncodingProcess)) {
        exit 1
    }
}
catch {
    Write-Log "Fatal error: $_" -Level Error
    exit 1
}

exit 0

<# $ffmpeg    = 'ffmpeg.exe'
$vspipe    = 'vspipe.exe'
$vpyScript = 'g:\Видео\Сериалы\Отечественные\Аутсорс\сезон 01\Autsors.S01.2025.WEB-DL.HEVC.2160p.SDR.ExKinoRay\test\test.vpy'
$outFile   = 'g:\Видео\Сериалы\Отечественные\Аутсорс\сезон 01\Autsors.S01.2025.WEB-DL.HEVC.2160p.SDR.ExKinoRay\test\qq.mkv'
$crf = 20
$ffmpegPrms0 = @(
    '-hide_banner',
    '-y'
)
$ffmpegPrms1 = @(
    '-c:v libx265',
    "-crf ${crf}",
    '-preset slow',
    '-c:a copy',
    '-f matroska',
    "`"$outFile`""
) -join ' '

Clear-Host
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\function_Invoke-Executable.ps1'
& "${vspipe}" -c y4m "${vpyScript}" - | & "$ffmpeg" $ffmpegPrms0 -i - $ffmpegPrms1 #>