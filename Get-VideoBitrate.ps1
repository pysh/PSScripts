function Get-VideoBitrate {
    <#
    .SYNOPSIS
    Calculates average video bitrate using packet-level statistics from ffprobe.

    .DESCRIPTION
    When stream doesn't contain bit_rate metadata, calculates it by analyzing individual packets
    using ffprobe's packet inspection capability.

    .PARAMETER Path
    Path to video file(s) for analysis.

    .EXAMPLE
    Get-VideoBitrate -Path "video.mp4"

    .EXAMPLE
    Get-ChildItem *.mp4 | Get-VideoBitrate | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias("FullName")]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string[]]$Path
    )

    begin {
        if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
            throw "FFprobe not found. Please install FFmpeg first."
        }
    }

    process {
        foreach ($file in $Path) {
            try {
                $fileInfo = Get-Item -LiteralPath $file
                
                # First try to get direct bitrate from stream metadata
                $streamInfo = ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate,duration,codec_name -of json "$file" | ConvertFrom-Json
                $videoStream = $streamInfo.streams[0]

                if (-not $videoStream) {
                    Write-Warning "No video stream found in: $file"
                    continue
                }

                # If we have direct bitrate, use it
                if ($videoStream.bit_rate -and $videoStream.bit_rate -gt 0) {
                    $bitrate = [math]::Round($videoStream.bit_rate / 1000, 2)
                }
                else {
                    # Get detailed packet information
                    $packetData = ffprobe -v error -select_streams v:0 -show_entries packet=size,pts_time -of json "$file" | ConvertFrom-Json

                    if (-not $packetData.packets -or $packetData.packets.Count -eq 0) {
                        Write-Warning "No packet data available for: $file"
                        continue
                    }

                    # Calculate total video data size in bytes
                    $totalSize = ($packetData.packets | Measure-Object -Property size -Sum).Sum

                    # Calculate duration using first and last packet timestamps
                    $firstPacket = [double]$packetData.packets[0].pts_time
                    $lastPacket = [double]($packetData.packets | Measure-Object -Property pts_time -Maximum).Maximum
                    $duration = $lastPacket - $firstPacket

                    if ($duration -le 0) {
                        # Fallback to stream duration if packet timing is invalid
                        $duration = [double]$videoStream.duration
                        if ($duration -le 0) {
                            Write-Warning "Cannot determine video duration for: $file"
                            continue
                        }
                    }

                    # Calculate bitrate in kbps (kilobits per second)
                    $bitrate = [math]::Round(($totalSize * 8) / $duration / 1000, 2)
                }

                [PSCustomObject]@{
                    FileName    = $fileInfo.Name
                    FilePath    = $fileInfo.FullName
                    Bitrate     = "$bitrate kbps"
                    Duration    = if ($videoStream.duration -gt 0) { 
                        [timespan]::FromSeconds($videoStream.duration).ToString("hh\:mm\:ss") 
                    } else { "N/A" }
                    Codec       = $videoStream.codec_name
                    PacketCount = if ($packetData) { $packetData.packets.Count } else { "N/A" }
                    Method      = if ($videoStream.bit_rate) { "Metadata" } else { "Packet Analysis" }
                }
            }
            catch {
                Write-Error "Error processing $file : $_"
                continue
            }
        }
    }
}