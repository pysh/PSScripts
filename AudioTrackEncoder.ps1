<#
.SYNOPSIS
    Multi-format Audio Track Encoder for MKV files
.DESCRIPTION
    Extracts and encodes audio tracks from MKV files to FDK AAC and Opus formats
    with intelligent bitrate selection and metadata preservation.
.PARAMETER InputFile
    Path to the input MKV file
.PARAMETER OutputDir
    Directory to save encoded audio files
.PARAMETER LogFile
    Path to log file for encoding operations
#>

param (
    [Parameter(Mandatory=$true, HelpMessage="Path to input MKV file")]
    [ValidateScript({
        if (-not (Test-Path $_)) { throw "Input file does not exist" }
        if ($_ -notlike "*.mkv") { throw "Input must be an MKV file" }
        return $true
    })]
    [string]$InputFile,

    [Parameter(HelpMessage="Output directory for encoded files")]
    [string]$OutputDir = (Join-Path -Path (Get-Location) -ChildPath "AudioOutput"),

    [Parameter(HelpMessage="Log file path")]
    [string]$LogFile = (Join-Path -Path (Get-Location) -ChildPath "audio_encoding.log")
)

# Logging function
function Write-EncodingLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info","Warning","Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $LogFile -Value $logEntry
    
    switch ($Level) {
        "Warning" { Write-Warning $Message }
        "Error" { Write-Error $Message }
        default { Write-Host $Message }
    }
}

# Validate required external tools
function Test-EncoderTools {
    $requiredTools = @("ffmpeg", "ffprobe")
    foreach ($tool in $requiredTools) {
        try {
            $result = Get-Command $tool -ErrorAction Stop
        }
        catch {
            Write-EncodingLog -Message "Required tool $tool not found" -Level "Error"
            throw "Missing required encoding tool: $tool"
        }
    }
}

# Advanced audio track extraction
function Get-AudioTrackDetails {
    param ([string]$FilePath)
    
    try {
        $trackInfo = & ffprobe -v quiet -print_format json -show_streams -select_streams a "$FilePath"
        $audioStreams = $trackInfo | ConvertFrom-Json
        
        return $audioStreams.streams | ForEach-Object {
            [PSCustomObject]@{
                Index = $_.index
                Codec = $_.codec_name
                Channels = $_.channels
                Language = $_.tags.language ?? "und"
                BitRate = $_.bit_rate
                Title = $_.tags.title ?? "Unknown Track"
            }
        }
    }
    catch {
        Write-EncodingLog -Message "Failed to extract audio track details" -Level "Error"
        return $null
    }
}

# Bitrate selection logic
function Get-OptimalBitrate {
    param (
        [int]$Channels,
        [string]$Codec
    )
    
    $bitrateMap = @{
        1 = 64   # Mono
        2 = 128  # Stereo
        6 = 256  # 5.1 Surround
        8 = 320  # 7.1 Surround
    }
    
    return $bitrateMap[$Channels] ?? 128
}

# Audio encoding function with advanced options
function Invoke-AudioEncoding {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [string]$Codec,
        [int]$Bitrate,
        [string]$Language,
        [string]$TrackTitle
    )
    
    try {
        $ffmpegArgs = @(
            "-i", "`"$InputFile`"",
            "-c:a", $Codec,
            "-b:a", "${Bitrate}k",
            "-metadata", "language=$Language",
            "-metadata", "title=`"$TrackTitle`""
        )
        
        & ffmpeg @ffmpegArgs "`"$OutputFile`""
        
        Write-EncodingLog -Message "Encoded $OutputFile successfully"
    }
    catch {
        Write-EncodingLog -Message "Encoding failed for $OutputFile" -Level "Error"
    }
}

# Main encoding workflow
function Start-AudioTrackEncoding {
    param (
        [string]$InputFile,
        [string]$OutputDir
    )
    
    # Ensure output directory exists
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    
    # Get audio track details
    $audioTracks = Get-AudioTrackDetails -FilePath $InputFile
    
    foreach ($track in $audioTracks) {
        $bitrate = Get-OptimalBitrate -Channels $track.Channels
        
        # Encode to AAC
        $aacOutput = Join-Path $OutputDir "$($track.Title)_$($track.Language).aac"
        Invoke-AudioEncoding -InputFile $InputFile -OutputFile $aacOutput -Codec "aac" -Bitrate $bitrate -Language $track.Language -TrackTitle $track.Title
        
        # Encode to Opus
        $opusOutput = Join-Path $OutputDir "$($track.Title)_$($track.Language).opus"
        Invoke-AudioEncoding -InputFile $InputFile -OutputFile $opusOutput -Codec "libopus" -Bitrate $bitrate -Language $track.Language -TrackTitle $track.Title
    }
}

# Script execution
try {
    Test-EncoderTools
    Start-AudioTrackEncoding -InputFile $InputFile -OutputDir $OutputDir
    Write-EncodingLog -Message "Audio encoding completed successfully"
}
catch {
    Write-EncodingLog -Message "Encoding process failed: $_" -Level "Error"
}