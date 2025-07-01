<#
.SYNOPSIS
    Automated AV1 video encoding test suite with multi-encoder support.

.DESCRIPTION
    This script performs comprehensive video encoding tests using various AV1 encoders with 
    different quality settings. It generates comparative reports with quality metrics.

    Key features:
    - Supports multiple AV1 encoders (SVT-AV1, rav1e, aomenc)
    - Customizable quality/preset combinations
    - Frame-accurate source sampling
    - VMAF quality metric calculation
    - Detailed encoding statistics
    - CSV report generation

.PARAMETER SourceVideoPath
    Path to the source video file for encoding tests.
    Default: 'y:\.temp\YT_y\Стыдно знать\Стыдно знать - 20250520 - Пушкин vs Сапрыкин [4k][noAdv].mkv'

.PARAMETER SampleDurationSeconds
    Duration of test samples in seconds (1-10000).
    Default: 120 (2 minutes)

.PARAMETER FrameServer
    Frame server engine for video processing.
    Valid values: 'AviSynth', 'VapourSynth'
    Default: 'AviSynth'

.EXAMPLE
    PS> .\Create-TestVideoFiles_DeepSeek.ps1 -SourceVideoPath "C:\videos\test.mkv" -SampleDurationSeconds 60
    
    Runs encoding tests with 1-minute samples from specified video file.

.EXAMPLE
    PS> .\Create-TestVideoFiles_DeepSeek.ps1 -FrameServer VapourSynth
    
    Runs tests using VapourSynth frame server with default settings.

.INPUTS
    None. You cannot pipe input to this script.

.OUTPUTS
    - Test video files in MKV container
    - CSV report with encoding statistics
    - Console log with progress information

.NOTES
    System Requirements:
    - PowerShell 5.1 or later
    - AV1 encoders (SVT-AV1, rav1e, aomenc)
    - Frame server (AviSynth+ or VapourSynth)
    - FFmpeg tools (ffmpeg, ffprobe)
    - video_tools_AI.ps1 helper module

.LINK
    SVT-AV1 Project: https://gitlab.com/AOMediaCodec/SVT-AV1
    rav1e Encoder:   https://github.com/xiph/rav1e
    aomenc Encoder:  https://aomedia.googlesource.com/aom/

.VERSION
    2.1.0

.AUTHOR
    Paul Nosov
    Contact: paul.nosov@gmail.com
    GitHub: https://github.com/pysh

.DATE
    2025-05-31
#>

<#
.SYNOPSIS
    Automated SVT-AV1 video encoding test suite.
#>

<#
.SYNOPSIS
    Automated SVT-AV1 video encoding test suite with MKV output.
#>

param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SourceVideoPath = 'Y:\.temp\Сериалы\Отечественные\Трасса\season 01\[NOOBDL]Трасса.S01E01.2160p.WEB-DL.x265.mkv',
    
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$TempDir = [IO.Path]::GetDirectoryName($SourceVideoPath),

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int]$SampleDurationSeconds = 120,

    [Parameter(Mandatory = $false)]
    [ValidateSet('AviSynth', 'VapourSynth')] 
    [string]$FrameServer = 'AviSynth'
)

#region Configuration
class VideoEncoder {
    [string]$Name
    [string]$ExecutablePath
    [string[]]$CommonParams
    [scriptblock]$GetQualityParams
    [int[]]$QualityLevels
    [int[]]$EncodingPresets
    [string[]]$ExtraParams

    VideoEncoder(
        [string]$name,
        [string]$executablePath,
        [string[]]$commonParams,
        [scriptblock]$getQualityParams,
        [int[]]$qualityLevels,
        [int[]]$encodingPresets,
        [string[]]$extraParams
    ) {
        $this.Name = $name
        $this.ExecutablePath = $executablePath
        $this.CommonParams = $commonParams
        $this.GetQualityParams = $getQualityParams
        $this.QualityLevels = $qualityLevels
        $this.EncodingPresets = $encodingPresets
        $this.ExtraParams = $extraParams
    }
}

# Encoders configuration with individual encoding settings
$script:Encoders = @(
    [VideoEncoder]::new(
        "SvtAv1",
        "X:\Apps\_VideoEncoding\av1an\SvtAv1EncApp3.exe",
        @("--progress", "2", "--rc", "0"),  # [0 = VQ, 1 = PSNR, 2 = SSIM], default is 1
        { param($crf, $preset) @("--crf", $crf, "--preset", $preset) },
        @(20..24),  # QualityLevels (CRF values)
        @(4),    # EncodingPresets
        @("")       # ExtraParams
    ),
    [VideoEncoder]::new(
        "SvtAv1PSY",
        "X:\Apps\_VideoEncoding\av1an\SvtAv1EncApp3PSY.exe",
        @("--progress", "3", "--rc", "0", "--hbd-mds", "2"),  # [0 = VQ, 1 = PSNR, 2 = SSIM, 3 = Subjective SSIM, 4 = Still Picture], default is 2
        { param($crf, $preset) @("--crf", $crf, "--preset", $preset) },
        @(25..30),          # Different CRF range for PSY version
        @(4),               # Different preset range
        @("")    # No extra params needed
    )
)

# Test configuration (now simplified)
$script:EncodingConfig = @{
    TestedEncoders = @('SvtAv1') # Encoders to test
}

# External tools
$script:EncodingTools = @{
    FFmpeg   = 'ffmpeg.exe'
    FFprobe  = 'ffprobe.exe'
    VSPipe   = 'vspipe.exe'
    MkvMerge = 'mkvmerge.exe'
}

function Test-ToolExists {
    param([string]$tool)
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Critical tool missing: $tool"
    }
}

# Проверка всех необходимых инструментов
foreach ($tool in $script:EncodingTools.Values) {
    Test-ToolExists $tool
}


# Load helper functions
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\video_tools_AI.ps1'
#endregion

#region Classes
class EncodingJob {
    [VideoEncoder]$Encoder
    [string]$InputScript
    [string]$OutputFile
    [int]$Crf
    [int]$Preset
    [string[]]$ExtraParams
    [string]$ServerType
    [object]$SourceVideoInfo
    [int]$SampleDurationSeconds
}

class EncodingResult {
    [string]$FileName
    [string]$Encoder
    [string]$Parameters
    [double]$EncodedVideoSizeMB
    [string]$EncodingTime
    [double]$EncodingFPS
    [double]$VMAFScore
    [string]$PixelFormat
    [Int16]$BitDepth
    [double]$OriginalVideoSizeMB
    [double]$CompressionRatio
}
#endregion

#region Functions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('Debug', 'Info', 'Error', 'Warn', 'Success')]
        [string]$Severity = 'Info',

        [switch]$NoNewLine
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Severity]`t$Message"
    $colors = @{
        'Debug'   = 'DarkYellow'
        'Info'    = 'Cyan'
        'Error'   = 'Red'
        'Warn'    = 'Magenta'
        'Success' = 'Green'
    }
    
    if ($NoNewLine) {
        Write-Host $logMessage -ForegroundColor $colors[$Severity] -NoNewline
    }
    else {
        Write-Host $logMessage -ForegroundColor $colors[$Severity]
    }
}

function New-FrameServerScript {
    param(
        [string]$ScriptPath,
        [string]$VideoPath,
        [int]$Duration,
        [object]$SourceVideoInfo,
        #[float]$FPS,
        [string]$ServerType,
        [object]$CropParams
    )
    $FPS = $($SourceVideoInfo.FrameRate)
    $FPSNum = $($SourceVideoInfo.FrameRateNum)
    $FPSDen = $($SourceVideoInfo.FrameRateDen)

    $scriptContent = if ($ServerType -eq 'VapourSynth') {
        @"
import os, sys
import vapoursynth as vs
core = vs.core
sample_seconds = $Duration
sys.path.append(r"X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\VS\Scripts")
clip = core.lsmas.LWLibavSource(r"$VideoPath")
#clip = core.std.AssumeFPS(clip, None, ${FPSNum}, ${FPSDen})
clip = core.std.Crop(clip, $($CropParams.Left), $($CropParams.Right), $($CropParams.Top), $($CropParams.Bottom))
clip = core.neo_f3kdb.Deband(clip, y=64, cb=64, cr=64, output_depth=10, preset="nograin")
#clip = core.std.SelectEvery(clip, cycle=clip.num_frames/10, offsets=range(round($FPS*sample_seconds/10)), modify_duration=False)
clip.set_output()
"@
    }
    else {
        @" 
AddAutoloadDir("X:\Apps\_VideoEncoding\StaxRip\Apps\FrameServer\AviSynth\plugins\")
LoadPlugin("X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\Dual\f3kdb Neo\neo-f3kdb.dll")
LoadPlugin("X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\Dual\L-SMASH-Works\LSMASHSource.dll")
LWLibavVideoSource("$VideoPath")
# AssumeFPS(${FPSNum}, ${FPSDen})
crop($($CropParams.Left), $($CropParams.Top), $(0-$CropParams.Right), $(0-$CropParams.Bottom))
neo_f3kdb(preset="nograin", output_depth=10)
#SelectRangeEvery(every=FrameCount/10, length=int($FPS*$Duration/10), offset=0, audio=true)
"@
    }
    
    Set-Content -LiteralPath $ScriptPath -Value $scriptContent -Force
}

function Invoke-EncodingWithStats {
    param(
        [EncodingJob]$Job
    )
    
    $tempIvfFile = [IO.Path]::ChangeExtension($Job.OutputFile, 'ivf')
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $frameCount = [math]::Round($Job.SourceVideoInfo.FrameRate * $Job.SampleDurationSeconds)
    
    if (-not (Test-Path -LiteralPath $Job.OutputFile)) {
        $ffmpegParams = @(
            "-y", "-hide_banner", "-v", "error",
            "-i", $($Job.InputScript),
            "-f", "yuv4mpegpipe",
            "-strict", -1,
            "-"
        )
    
        try {
            Write-Log -Message "Starting $($Job.Encoder.Name) encoder..." -Severity Info
            
            $qualityParams = & $Job.Encoder.GetQualityParams $Job.Crf $Job.Preset
            $allParams = $Job.Encoder.CommonParams + `
                $qualityParams + `
            $(if ( $Job.ExtraParams -ne '' ) { $Job.ExtraParams } ) + `
            @(
                "--input", "stdin",
                "--output", $tempIvfFile
            )

            Write-Log -Message ($ffmpegParams -join ' ') -Severity Debug
            Write-Log -Message ($allParams -join ' ') -Severity Debug

            if ( $Job.ServerType -eq 'VapourSynth') {
                & $script:EncodingTools.VSPipe -c y4m "$($Job.InputScript)" - | & $Job.Encoder.ExecutablePath @allParams
            }
            else {
                & $($script:EncodingTools.FFmpeg) @ffmpegParams | & $($Job.Encoder.ExecutablePath) @allParams
            }

            # Mux IVF to MKV
            & $script:EncodingTools.MkvMerge --ui-language en --priority lower --output-charset UTF8 --output $Job.OutputFile $tempIvfFile 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "mkvmerge failed with exit code: $LASTEXITCODE" }
            
            if (Test-Path -LiteralPath $Job.OutputFile) {
                Remove-Item -LiteralPath $tempIvfFile -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log -Message "Encoding with $($Job.Encoder.Name) failed: $_" -Severity Error
            throw
        }
    }
    $timer.Stop()

    $outputFileInfo = Get-VideoStatsAI -VideoFilePath $Job.OutputFile
    Write-Log -Message "VMAF calculating..." -Severity Debug
    $vmafScore = Get-VMAFValueAI -Distorted $Job.OutputFile -Reference $Job.InputScript
    $vmafScore = [Math]::Round($vmafScore, 2)
    $finalOutputName = Join-Path -Path (Get-Item -LiteralPath $Job.OutputFile).DirectoryName `
        -ChildPath ("$((Get-Item -LiteralPath $Job.OutputFile).BaseName)_[${vmafScore}]$((Get-Item -LiteralPath $Job.OutputFile).Extension)")
    Rename-Item -LiteralPath $Job.OutputFile -NewName $finalOutputName -Force

    return [EncodingResult]@{
        FileName            = $finalOutputName #[IO.Path]::GetFileName($Job.OutputFile)
        Encoder             = $Job.Encoder.Name
        Parameters          = ($Job.Encoder.CommonParams + $qualityParams + $Job.ExtraParams) -join " "
        EncodedVideoSizeMB  = [math]::Round($outputFileInfo.VideoDataSizeBytes / 1MB, 3)
        VMAFScore           = [math]::Round($vmafScore, 2)
        EncodingTime        = "{0:hh\:mm\:ss}" -f $timer.Elapsed
        EncodingFPS         = [math]::Round($frameCount / $timer.Elapsed.TotalSeconds, 2)
        PixelFormat         = $outputFileInfo.PixelFormat
        BitDepth            = $outputFileInfo.BitDepth
        OriginalVideoSizeMB = [math]::Round($Job.SourceVideoInfo.VideoDataSizeBytes / 1MB, 2)
        CompressionRatio    = [math]::Round($Job.SourceVideoInfo.VideoDataSizeBytes / $outputFileInfo.VideoDataSizeBytes, 2)
    }
}
#endregion

#region Main Execution
Clear-Host
$error.Clear()

try {
    # Encoder availability check
    $availableEncoders = [System.Collections.Generic.List[VideoEncoder]]::new()
    foreach ($encoderName in $script:EncodingConfig.TestedEncoders) {
        $encoder = $script:Encoders | Where-Object { $_.Name -eq $encoderName }
        if (-not $encoder) {
            Write-Log -Message "Encoder $encoderName not found in configuration" -Severity Warn
            continue
        }
        $availableEncoders.Add($encoder)
    }

    if ($availableEncoders.Count -eq 0) {
        throw "No available encoders found. Check configuration."
    }

    # Calculate total number of tests to run
    $totalTests = 0
    foreach ($encoderName in $script:EncodingConfig.TestedEncoders) {
        $encoder = $script:Encoders | Where-Object { $_.Name -eq $encoderName }
        $combinations = $encoder.QualityLevels.Count * $encoder.EncodingPresets.Count * $encoder.ExtraParams.Count
        Write-Log -Message "Encoder $($encoder.Name) has $combinations test combinations" -Severity Info
        $totalTests += $combinations
    }
    Write-Log -Message "TOTAL TEST COMBINATIONS: $totalTests" -Severity Info

    # Initialize working directory
    $sourceVideoFile = Get-Item -LiteralPath $SourceVideoPath
    Write-Log -Message "Processing file: $($sourceVideoFile.Name)" -Severity Info
    
    $workingDirectory = if (Test-Path -LiteralPath $TempDir -PathType Container) {
        Join-Path -Path $TempDir -ChildPath "$($sourceVideoFile.BaseName)_AV1_Tests"
    } else {
        Join-Path -Path $sourceVideoFile.DirectoryName -ChildPath "$($sourceVideoFile.BaseName)_AV1_Tests"
    }
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    
    $sampleFileName = [IO.Path]::Combine($sourceVideoFile.DirectoryName, [IO.Path]::Combine($workingDirectory, "$($sourceVideoFile.BaseName)[sample]$($sourceVideoFile.Extension)"))
    $sourceVideoFile = if (Test-Path -LiteralPath $sampleFileName -PathType Leaf) {
        Get-Item -LiteralPath $sampleFileName
    } else {
        Get-Item -LiteralPath (Copy-VideoFragments -InputFile $sourceVideoFile -OutputFile $sampleFileName -FragmentCount 10 -FragmentDuration 12).OutputFile
    }

    # Get video metadata
    $sourceVideoInfo = Get-VideoStatsAI -VideoFilePath $sourceVideoFile.FullName
    
    # Get cropping parameters
    $cropParams = Get-VideoCropParametersAC $sourceVideoFile.FullName -Round 2
    Write-Log -Message "Cropping parameters: left: $($cropParams.Left); right: $($cropParams.Right); top: $($cropParams.Top); bottom: $($cropParams.Bottom)" -Severity Info

    # Generate frame server script
    $frameServerScriptPath = Join-Path $workingDirectory "$($sourceVideoFile.BaseName).$($FrameServer -eq 'VapourSynth' ? 'vpy' : 'avs')"
    New-FrameServerScript -ScriptPath $frameServerScriptPath `
        -VideoPath $sourceVideoFile.FullName `
        -Duration $SampleDurationSeconds `
        -SourceVideoInfo $sourceVideoInfo `
        -ServerType $FrameServer `
        -CropParams $cropParams

    
    $encodingResults = [System.Collections.Generic.List[EncodingResult]]::new()
    $testCurrent = 0
    $reportPath = Join-Path -Path $workingDirectory -ChildPath "$($sourceVideoFile.BaseName)_report.csv"

    foreach ($encoder in $availableEncoders) {
        $encoderVersion = & $encoder.ExecutablePath --version
        Write-Log "Testing encoder: ${encoderVersion}" -Severity Info
        foreach ($crf in $encoder.QualityLevels) {
            foreach ($preset in $encoder.EncodingPresets) {
                foreach ($param in $encoder.ExtraParams) {
                    $testCurrent++
                    $paramName = $param.Replace('--', '').Replace(' ', '=')
                    $outputFileName = "test_$($encoder.Name)_crf=${crf}_preset=${preset}$(if ($paramName -notin ('',$null)) {"+$paramName"}).mkv"
                    $outputFilePath = Join-Path $workingDirectory $outputFileName
                    
                    Write-Log -Message "Testing (${testCurrent}/${totalTests}): $outputFileName" -Severity Info
                    
                    $job = [EncodingJob]@{
                        Encoder               = $encoder
                        InputScript           = $frameServerScriptPath
                        OutputFile            = $outputFilePath
                        Crf                   = $crf
                        Preset                = $preset
                        ExtraParams           = $param -split ' '
                        ServerType            = $FrameServer
                        SourceVideoInfo       = $sourceVideoInfo
                        SampleDurationSeconds = $SampleDurationSeconds
                    }
                    
                    $result = Invoke-EncodingWithStats -Job $job
                    $result | Export-Csv -LiteralPath $reportPath -Append -Force -Delimiter "`t"
                    $encodingResults.Add($result)
                    Write-Log -Message "Completed: $([IO.Path]::GetFileName($result.FileName)) (VMAF: $($result.VMAFScore), Time: $($result.EncodingTime))" -Severity Success
                }
            }
        }
    }
    # Generate report
    $frameCount = [math]::Round($sourceVideoInfo.FrameRate * $SampleDurationSeconds)
    $reportHeader = @"
# ========================== ENCODING REPORT ==========================
# Source file: $($sourceVideoFile.Name)
# Duration: $SampleDurationSeconds sec ($frameCount frames)
# Original video size: {0:N2} MB
# Total encoded files: $($encodingResults.Count)
#
"@ -f ($sourceVideoInfo.VideoDataSizeBytes / 1MB)

    Write-Host $reportHeader
    $encodingResults | Format-Table FileName, Encoder, VMAFScore, EncodedVideoSizeMB, CompressionRatio, EncodingFPS -AutoSize
    Write-Host "`nReport saved to: $reportPath" -ForegroundColor Green
}
catch {
    Write-Log -Message "Execution error: $_" -Severity Error
    exit 1
}
#endregion