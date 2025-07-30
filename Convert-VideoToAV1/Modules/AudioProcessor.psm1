<#
.SYNOPSIS
    Audio processing module
#>

function Convert-AudioToOpus {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job,
        [switch]$KeepTempFlac = $false
    )

    $audioTracks = Get-AudioMetadata -VideoFilePath $Job.VideoPath
    $Job.AudioOutputs = @()
    
    foreach ($track in $audioTracks) {
        $audioPath = Join-Path -Path $Job.WorkingDir -ChildPath "audio"
        # $opusOutput = Join-Path -Path $audioPath -ChildPath "$($Job.BaseName).track$(([int]$track.Index).ToString('d2')).opus"
        $opusOutput = Join-Path -Path $audioPath -ChildPath ("aID{0}_[{1}]_{{`{2`}}}{3}{4}.opus" -f $(([int]$track.Index).ToString('d2')), $track.Language, $track.Title,($track.Default ? '+' : '-'), ($track.Forced ? 'Forced' : ''))
        
        #"$($Job.BaseName).track$(([int]$track.Index).ToString('d2')).opus"
        $tempAudio = [IO.Path]::ChangeExtension($opusOutput, "flac") #Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).track$($track.Index).flac"
        if (-not (Test-Path -LiteralPath $audioPath -PathType Container)) {New-Item -Path $audioPath -ItemType Directory | Out-Null}
        if (-not (Test-Path -LiteralPath $opusOutput -PathType Leaf)) {
            #$outExtension = switch $track.CodecName {}
            # Extract audio track
            Write-Log -Message "Converting track #$($track.Index) from $($Job.VideoPath) to ${tempAudio}..." -Severity Info -Category "AudioProcessor"
            $ffmpegParams = @(
                "-y", "-hide_banner", "-nostats", "-loglevel", "error"
                "-i", $Job.VideoPath
                "-map", "0:a:$($track.Index-1)"
                "-c:a", "$(if ($track.CodecName -eq 'flac') {'copy'} else {'flac'})"
                $tempAudio
            )
            & $global:VideoTools.FFmpeg $ffmpegParams
        
            # Convert to Opus
            $bitRate = switch ($track.Channels) {
                { $_ -le 2 } { "160"; break }
                { $_ -le 6 } { "320"; break }
                default { "384" }
            }
            $opusParams = @(
                "--quiet", "--vbr", "--bitrate", $bitRate
                $(if ($track.Title) { "--title", "$($track.Title)" })
                $(if ($track.Language) { "--comment", "language=$($track.Language)" })
                # $(if ($track.Forced) { "--comment", "forced=1" })
                # $(if ($track.Default) { "--comment", "default=1" })
                $tempAudio, $opusOutput
            )
            Write-Log -Message "Converting ${tempAudio} to ${opusOutput}..." -Severity Info -Category "AudioProcessor"
            & $global:VideoTools.OpusEnc @opusParams | Out-Null
        }
        $Job.AudioOutputs += $opusOutput
        if ($KeepTempFlac) {
            $Job.TempFiles += $tempAudio
        } else {
            Remove-Item -LiteralPath $tempAudio -Force -ProgressAction SilentlyContinue | Out-Null
        }
        $Job.TempFiles += $opusOutput
    }
    
    return $Job
}

Export-ModuleMember -Function Convert-AudioToOpus