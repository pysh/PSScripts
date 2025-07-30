<#
.SYNOPSIS
    Main conversion script with full path support and file discovery
#>

using namespace System.IO

# Parameters
param (
    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
    [string]$InputDirectory = 'r:\Temp\_to_encode\',

    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
    [string]$OutputDirectory = 'r:\Temp\_to_encode\'
)

# Import modules
$modulesPath = Join-Path $PSScriptRoot "Modules" -Resolve
Import-Module (Join-Path $modulesPath "VideoProcessor.psm1") -Force
Import-Module (Join-Path $modulesPath "AudioProcessor.psm1") -Force
Import-Module (Join-Path $modulesPath "MetadataProcessor.psm1") -Force
Import-Module (Join-Path $modulesPath "Utilities.psm1") -Force

# Global configuration
$global:VideoTools = @{
    VSPipe      = 'vspipe.exe'
    SvtAv1Enc   = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp_orig.exe'
    OpusEnc     = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\opus\opusenc.exe'
    FFmpeg      = 'X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.exe'
    ffprobe     = 'ffprobe.exe'
    MkvMerge    = 'mkvmerge.exe'
    MkvExtract  = 'mkvextract.exe'
    MkvPropedit = 'mkvpropedit.exe'
}

# Discover video files
$videoFiles = Get-ChildItem -LiteralPath $InputDirectory -Filter "*.mkv" -Exclude "*_out.*" -File -Recurse:$false

if (-not $videoFiles) {
    Write-Error "No MKV files found in $InputDirectory"
    exit 1
}

Clear-Host
$Error.Clear()

# Process each file
foreach ($videoFile in $videoFiles) {
    try {
        Write-Log "Starting processing of $($videoFile.Name)" -Severity Debug -Category 'MainModule'
        
        # Initialize job
        [System.Collections.Hashtable]$job = @{
            VideoPath = $videoFile.FullName
            BaseName = [IO.Path]::GetFileNameWithoutExtension($videoFile.Name)
            WorkingDir = $OutputDirectory
            TempFiles = @()
        }

        # Process video
        Write-Log "Processing video" -Severity Debug -Category 'MainModule'
        $job = Convert-VideoToAV1 -Job $job
        
        # Process audio
        Write-Log "Processing audio..."  -Severity Debug -Category 'MainModule'
        $job = Convert-AudioToOpus -Job $job
        
        # Process metadata
        Write-Log "Processing metadata..."  -Severity Debug -Category 'MainModule'
        $job = Process-Metadata -Job $job
        
        # Finalize
        Write-Log "Finalizing..."  -Severity Debug -Category 'MainModule'
        Complete-Conversion -Job $job
        
        Write-Log "Successfully processed: $($job.FinalOutput)" -Severity Success -Category 'MainModule'
    }
    catch {
        Write-Error "Failed to process $($videoFile.Name): $_"
        Cleanup-FailedJob -Job $job
    }
}