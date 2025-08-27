# Video Trimming Module
# Smart frame-accurate video trimming with minimal re-encoding
# Optimized for PowerShell 7.5+

# Main function
function Invoke-VideoTrimming {
    <#
    .SYNOPSIS
    Smart frame-accurate video trimming with minimal re-encoding.
    
    .DESCRIPTION
    Trims MKV video files with minimal re-encoding by using keyframe-based segmentation.
    Supports both time-based and frame-based trimming with priority for frame numbers.
    
    .PARAMETER InputFile
    Path to the input MKV video file.
    
    .PARAMETER StartTime
    Start time for trimming (format: HH:MM:SS.ms or seconds).
    
    .PARAMETER EndTime
    End time for trimming (format: HH:MM:SS.ms or seconds).
    
    .PARAMETER StartFrame
    Start frame number for trimming.
    
    .PARAMETER EndFrame
    End frame number for trimming.
    
    .PARAMETER OutputFile
    Path for the output file (default: {input_filename}_trimmed.mkv).
    
    .PARAMETER KeepTemp
    Keep temporary files after processing.
    
    .EXAMPLE
    Invoke-VideoTrimming -InputFile "video.mkv" -StartTime "00:10:00" -EndTime "00:20:30"
    
    .EXAMPLE
    Invoke-VideoTrimming -InputFile "video.mkv" -StartFrame 1602 -EndFrame 3000
    
    .EXAMPLE
    Invoke-VideoTrimming -InputFile "video.mkv" -StartFrame 1602 -KeepTemp
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$InputFile,
        
        [Parameter()] [string]$StartTime,
        [Parameter()] [string]$EndTime,
        [Parameter()] [int]$StartFrame,
        [Parameter()] [int]$EndFrame,
        [Parameter()] [string]$OutputFile,
        [Parameter()] [switch]$KeepTemp
    )
    
    # Set default output file if not specified
    if ([string]::IsNullOrEmpty($OutputFile)) {
        $inputFileInfo = Get-Item $InputFile
        $OutputFile = Join-Path $inputFileInfo.DirectoryName ($inputFileInfo.BaseName + "_trimmed.mkv")
    }
    
    # Get video information
    $videoInfo = ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -show_entries format=duration -of json $InputFile | ConvertFrom-Json
    $codec = $videoInfo.streams[0].codec_name
    $duration = [double]$videoInfo.format.duration
    
    # Get video FPS and offset
    $fps = Get-VideoFps $InputFile
    Write-Verbose "Video FPS: $fps"
    
    $videoOffset = [double](ffprobe -v error -select_streams v:0 -show_entries packet=pts_time -of csv=p=0 $InputFile | Select-Object -First 1)
    Write-Verbose "Video offset: $videoOffset seconds"
    
    # Process parameters
    $startSec = Process-StartParameter -StartTime $StartTime -StartFrame $StartFrame -Fps $fps -Duration $duration
    $endSec = Process-EndParameter -EndTime $EndTime -EndFrame $EndFrame -Fps $fps -Duration $duration
    
    # Validate parameters
    if ($startSec -ge $endSec) {
        throw "Start time must be less than end time."
    }
    if ($endSec -gt $duration) {
        throw "End time exceeds video duration ($([math]::Round($duration, 2)) seconds)."
    }
    
    Write-Host "Trimming from $startSec seconds (frame $(Convert-TimeToFrame $startSec $fps)) to $endSec seconds (frame $(Convert-TimeToFrame $endSec $fps))"
    
    # Get keyframes
    Write-Verbose "Finding keyframes..."
    $keyFrames = Get-KeyFrames $InputFile $videoOffset
    $keyFrames += $duration  # Add last frame as keyframe
    
    # Check if we can use perfect cutting
    if (Test-PerfectCutting $startSec $endSec $keyFrames $duration) {
        Write-Host "Using perfect cutting with mkvmerge (no re-encoding needed)"
        Perfect-CutWithMkvmerge $InputFile $OutputFile $startSec $endSec $duration
        return
    }
    
    # Find appropriate keyframes
    $startKeyFrame = Find-KeyFrameAfter $keyFrames $startSec
    $endKeyFrame = Find-KeyFrameBefore $keyFrames $endSec
    
    Write-Host "Using keyframes: $startKeyFrame to $endKeyFrame seconds"
    
    # Create temp directory
    $outputFileInfo = (Get-Item $OutputFile -ErrorAction SilentlyContinue) ?? (New-Object System.IO.FileInfo($OutputFile))
    $tempDir = Join-Path $outputFileInfo.DirectoryName ($outputFileInfo.BaseName + "_temp")
    
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
    }
    
    $tempFiles = @()
    
    try {
        $segments = @()
        
        # Process start segment (if needed)
        if ($startSec -lt $startKeyFrame) {
            Write-Host "Re-encoding start segment: $startSec to $startKeyFrame seconds"
            $tempFile = Join-Path $tempDir "start_segment.mkv"
            $tempFiles += $tempFile
            
            Execute-FFmpeg @(
                '-y', '-hide_banner',
                '-r', $fps
                "-i", $InputFile,
                "-ss", $startSec, "-to", $startKeyFrame,
                "-c:v", $codec, "-c:a", "copy", "-c:s", "copy",
                "-map_metadata", "0", "-avoid_negative_ts", "make_zero", $tempFile
            )
            $segments += $tempFile
        }
        
        # Process middle segment (copy without re-encoding)
        if ($startKeyFrame -lt $endKeyFrame) {
            Write-Host "Copying middle segment: $startKeyFrame to $endKeyFrame seconds"
            $tempFile = Join-Path $tempDir "middle_segment.mkv"
            $tempFiles += $tempFile
            
            $ffmpegArgs = @(
                '-y', '-hide_banner'
                '-r', $fps
                "-i", $InputFile
                "-ss", $startKeyFrame
                if ($endKeyFrame -lt $duration) { "-to", $endKeyFrame }
            )
            
            
            Execute-FFmpeg ($ffmpegArgs + @(
                    "-c", "copy", "-map_metadata", "0",
                    "-avoid_negative_ts", "make_zero", $tempFile
                ))
            $segments += $tempFile
        }
        
        # Process end segment (if needed)
        if ($endSec -gt $endKeyFrame) {
            Write-Host "Re-encoding end segment: $endKeyFrame to $endSec seconds"
            $tempFile = Join-Path $tempDir "end_segment.mkv"
            $tempFiles += $tempFile
            
            Execute-FFmpeg @(
                '-y', '-hide_banner',
                '-r', $fps,
                "-i", $InputFile,
                "-ss", $endKeyFrame, "-to", $endSec,
                "-c:v", $codec, "-c:a", "copy", "-c:s", "copy",
                "-map_metadata", "0", "-avoid_negative_ts", "make_zero", 
                $tempFile
            )
            $segments += $tempFile
        }
        
        # Merge segments
        if ($segments.Count -eq 1) {
            Move-Item $segments[0] $OutputFile -Force
        }
        else {
            Merge-Segments $segments $OutputFile
        }
        
        Write-Host "Successfully trimmed video saved to: $OutputFile" -ForegroundColor Green
    }
    finally {
        # Cleanup if not keeping temp files
        if (-not $KeepTemp) {
            Remove-TemporaryFiles $tempFiles
            if (Test-Path $tempDir) {
                Remove-Item $tempDir -Recurse -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Host "Temporary files kept in: $tempDir" -ForegroundColor Yellow
        }
    }
}



# Requirement checks
foreach ($tool in @('ffmpeg', 'ffprobe', 'mkvmerge')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' not found. Please install and add to PATH."
    }
}

# Helper functions
function Get-VideoFps {
    param([string]$InputFile)
    
    $fpsInfo = ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 $InputFile
    $parts = $fpsInfo -split "/"
    
    return $parts.Count -eq 2 ? [double]$parts[0] / [double]$parts[1] : [double]$fpsInfo
}

function Parse-Time {
    param([string]$TimeString)
    
    if ([string]::IsNullOrEmpty($TimeString)) { return $null }
    
    if ($TimeString -match "^(?<h>\d+):(?<m>\d+):(?<s>[\d\.]+)$") {
        return [double]$Matches.h * 3600 + [double]$Matches.m * 60 + [double]$Matches.s
    }
    elseif ($TimeString -match "^(?<s>[\d\.]+)$") {
        return [double]$Matches.s
    }
    else {
        throw "Invalid time format: $TimeString. Use HH:MM:SS.ms or seconds."
    }
}

function Convert-FrameToTime {
    param([int]$FrameNumber, [double]$Fps)
    return [math]::Round($FrameNumber / $Fps, 6)
}

function Convert-TimeToFrame {
    param([double]$Time, [double]$Fps)
    return [math]::Round($Time * $Fps)
}

function Process-StartParameter {
    param($StartTime, $StartFrame, $Fps, $Duration)
    
    return $StartFrame -gt 0 ? (Convert-FrameToTime $StartFrame $Fps) :
    (-not [string]::IsNullOrEmpty($StartTime)) ? (Parse-Time $StartTime) : 0
}

function Process-EndParameter {
    param($EndTime, $EndFrame, $Fps, $Duration)
    
    return $EndFrame -gt 0 ? (Convert-FrameToTime $EndFrame $Fps) :
    (-not [string]::IsNullOrEmpty($EndTime)) ? (Parse-Time $EndTime) : $Duration
}

function Get-KeyFrames {
    param([string]$InputFile, [double]$Offset)
    
    $keyFramesJson = ffprobe -v error -skip_frame nokey -select_streams v:0 -show_entries frame=pts_time -of json $InputFile | ConvertFrom-Json
    $keyFrames = @()
    
    if ($keyFramesJson.frames) {
        foreach ($frame in $keyFramesJson.frames) {
            if ($frame.pts_time) {
                $adjustedTime = [double]$frame.pts_time - $Offset
                $keyFrames += $adjustedTime
            }
        }
    }
    
    return ($keyFrames | Sort-Object)
}

function Test-PerfectCutting {
    param($StartTime, $EndTime, $KeyFrames, $Duration)
    
    $tolerance = 0.001  # 1ms tolerance
    
    $startIsKeyFrame = $StartTime -eq 0 ? $true : 
    (($KeyFrames | Where-Object { [math]::Abs($_ - $StartTime) -lt $tolerance }).Count -gt 0)
    
    $endIsKeyFrame = $EndTime -eq $Duration ? $true :
    (($KeyFrames | Where-Object { [math]::Abs($_ - $EndTime) -lt $tolerance }).Count -gt 0)
    
    return $startIsKeyFrame -and $endIsKeyFrame
}

function Perfect-CutWithMkvmerge {
    param($InputFile, $OutputFile, $StartTime, $EndTime, $Duration)
    
    try {
        $splitParts = "parts:"
        $splitParts += $StartTime -gt 0 ? "${StartTime}s" : ""
        $splitParts += "-"
        $splitParts += $EndTime -lt $Duration ? "${EndTime}s" : ""
        
        $process = Start-Process -FilePath "mkvmerge" -ArgumentList @(
            "-o", "`"$OutputFile`"",
            "--split", $splitParts,
            "`"$InputFile`""
        ) -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -ne 0) {
            throw "Mkvmerge failed with exit code $($process.ExitCode)"
        }
        
        Write-Host "Perfect cutting completed with mkvmerge" -ForegroundColor Green
    }
    catch {
        Write-Warning "Perfect cutting failed: $($_.Exception.Message)"
        throw
    }
}

function Find-KeyFrameAfter {
    param($KeyFrames, $Time)
    
    foreach ($frame in $KeyFrames) {
        if ($frame -ge $Time) {
            return $frame
        }
    }
    return $KeyFrames[-1]
}

function Find-KeyFrameBefore {
    param($KeyFrames, $Time)
    
    $prevFrame = $KeyFrames[0]
    foreach ($frame in $KeyFrames) {
        if ($frame -gt $Time) {
            return $prevFrame
        }
        $prevFrame = $frame
    }
    return $prevFrame
}

function Invoke-FFmpegProcess {
    param([array]$Arguments)
    
    Write-Verbose "Executing: ffmpeg $($Arguments -join ' ')"
    $process = Start-Process -FilePath "ffmpeg" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    
    if ($process.ExitCode -ne 0) {
        throw "FFmpeg failed with exit code $($process.ExitCode)"
    }
}

function Execute-FFmpeg {
    param([array]$Arguments)
    
    Write-Verbose "Executing: ffmpeg $($Arguments -join ' ')"
    & ffmpeg @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg failed with exit code $LASTEXITCODE"
    }

    #$process = Start-Process -FilePath "ffmpeg" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    #if ($process.ExitCode -ne 0) {
    #     throw "FFmpeg failed with exit code $($process.ExitCode)"
    # }
}

function Merge-Segments {
    param([array]$Segments, [string]$OutputFile)
    
    $concatFile = Join-Path ([System.IO.Path]::GetTempPath()) "concat_list.txt"
    $content = $Segments | ForEach-Object { "file '$($_.Replace('\', '/'))'" }
    Set-Content -Path $concatFile -Value $content
    
    try {
        Execute-FFmpeg @(
            '-y', '-hide_banner',
            '-r', $fps,
            "-f", "concat",
            "-safe", "0",
            "-i", $concatFile,
            # '-r', $fps,
            "-c", "copy",
            "-map_metadata", "0",
            $OutputFile
        )
    }
    finally {
        if (Test-Path $concatFile) {
            Remove-Item $concatFile -ErrorAction SilentlyContinue
        }
    }
}

function Remove-TemporaryFiles {
    param([array]$Files)
    
    foreach ($file in $Files) {
        if (Test-Path $file) {
            Remove-Item $file -ErrorAction SilentlyContinue
        }
    }
}

# Export the main function
Export-ModuleMember -Function Invoke-VideoTrimming