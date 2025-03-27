param(
    [Parameter(Mandatory = $false)]
    [string]$ReferenceVideo = 'y:\.temp\YT_y\Стендап комики 4k\[20241205] Валентин Сидоров - Почему мы себя не ценим？ (Стендап, 2024) [4k].mkv',
    
    [Parameter(Mandatory = $false)]
    [string[]]$ComparisonVideos = @(
        'y:\.temp\YT_y\Стендап комики 4k\out_[SvtAv1EncApp]\[20241205] Валентин Сидоров - Почему мы себя не ценим？ (Стендап, 2024) [4k]_[SvtAv1_[preset4][crf33]].mkv'
        ),
    [bool]$calcPSNR = $true,
    [bool]$calcVMAF = $true,
    [string]$OutputCsv,
    [int]$TrimStartSeconds = 0,
    [int]$DurationSeconds = 0,
    [int]$MaxThreads = [System.Environment]::ProcessorCount,
    [switch]$WriteLog = $false
)

function Test-FFmpeg {
    try {
        & ffmpeg -version | Out-Null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# Load external functions
# . 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\function_Invoke-Executable.ps1'
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1'

# Validate ffmpeg presence
if (-not (Test-FFmpeg)) {
    throw "ffmpeg is not available in PATH"
}

# Validate input files
if (-not (Test-Path -LiteralPath $ReferenceVideo)) {
    throw "Reference video not found: $ReferenceVideo"
}

$results = @()
$totalFiles = $ComparisonVideos.Count
$processed = 0
$startTime = Get-Date
$PSStyle.Progress.View = 'Classic'

foreach ($video in $ComparisonVideos) {
    if (-not (Test-Path -LiteralPath $video)) {
        Write-Warning "Video not found: $video"
        continue
    }
    
    $processed++
    $elapsedTime = (Get-Date) - $startTime
    $averageTime = $elapsedTime.TotalSeconds / $processed
    $remainingFiles = $totalFiles - $processed
    $estimatedSeconds = $averageTime * $remainingFiles
    $estimatedTime = [TimeSpan]::FromSeconds($estimatedSeconds)
    
    $percentComplete = ($processed / $totalFiles) * 100
    
    Write-Progress -Activity "Analyzing Videos" `
        -Status "Processing $processed of $totalFiles - $([math]::Round($percentComplete,1))%" `
        -PercentComplete $percentComplete `
        -CurrentOperation "Current: $(Split-Path $video -Leaf)" `
        -SecondsRemaining $estimatedTime.TotalSeconds
    
    Write-Verbose "Analyzing: $video"
    Write-Verbose "Elapsed: $($elapsedTime.ToString('hh\:mm\:ss')) - Remaining: $($estimatedTime.ToString('hh\:mm\:ss'))"
    
    try {
        $quality = Get-VideoQuality -Distorted $video `
                                    -Reference $ReferenceVideo `
                                    -calcXPSNR:$calcPSNR -calcVMAF:$calcVMAF `
                                    -TrimStartSeconds $TrimStartSeconds `
                                    -DurationSeconds $DurationSeconds `
                                    -MaxThreads $MaxThreads `
                                    -WriteLog:$WriteLog
        $stats = Get-VideoStats -VideoPath $video
        $results += [PSCustomObject]@{
            "Name"       = $stats.Name
            "Size"       = $stats.Size
            "XPSNR"      = $quality.XPSNR
            "VMAF"       = $quality.VMAF
            "FPS"        = $stats.FPS
            "FrameCount" = $stats.Frames
        }
    }
    catch {
        Write-Warning "Failed to analyze $video : $_"
        Write-Warning $_.Exception.Message
    }
}

Write-Progress -Activity "Analyzing Videos" -Completed
$totalTime = (Get-Date) - $startTime
Write-Host "`nAnalysis completed in $($totalTime.ToString('hh\:mm\:ss'))" -ForegroundColor Green

# Display results
$results | Sort-Object VMAF -Descending | Format-Table Name, Size, VMAF, XPSNR -AutoSize

# Export to CSV if requested
if ($OutputCsv) {
    $results | Export-Csv -Path $OutputCsv -NoTypeInformation
    Write-Host "Results exported to: $OutputCsv" -ForegroundColor Green
}