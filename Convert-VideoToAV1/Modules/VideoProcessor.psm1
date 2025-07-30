<#
.SYNOPSIS
    Video processing module
#>

function Convert-VideoToAV1 {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )
    
    $Job.ScriptFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).vpy"
    Write-Log -Message "$($Job.ScriptFile)" -Severity Info -Category 'VideoProcessor'
    $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).lwi"
    Write-Log -Message "$($Job.CacheFile)" -Severity Info -Category 'VideoProcessor'
    $Job.VideoOutput = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).ivf"
    Write-Log -Message "$($Job.VideoOutput)" -Severity Info -Category 'VideoProcessor'

    if (-not (Test-Path -LiteralPath $Job.VideoOutput)) {
        # Get crop parameters
        Write-Log "Getting crop parameters..." -Severity Debug -Category 'VideoProcessor'
        $Job.CropParams = Get-VideoCropParametersAC2 -InputFile $Job.VideoPath -Round 2
        Write-Log -Message "left=$($Job.CropParams.Left), right=$($Job.CropParams.Right), top=$($Job.CropParams.Top), bottom=$($Job.CropParams.Bottom)" -Severity info
    
        # Generate VapourSynth script
        Write-Log -Message "Generate VapourSynth script" -Severity Info -Category 'VideoProcessor'
        $scriptContent = @"
import vapoursynth as vs
core = vs.core
clip = core.lsmas.LWLibavSource(source=r"$($Job.VideoPath)", cachefile=r"$($Job.CacheFile)")
clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.Crop(clip, $($Job.CropParams.Left), $($Job.CropParams.Right), $($Job.CropParams.Top), $($Job.CropParams.Bottom))
clip.set_output()
"@
        Write-Verbose -Message $scriptContent
        Set-Content -LiteralPath $Job.ScriptFile -Value $scriptContent -Force
        $Job.TempFiles += $Job.ScriptFile, $Job.CacheFile
        # Get info from vpy script
        Write-Log -Message "Getting info from vpy script..." -Severity Debug -Category 'VideoProcessor'
        $vpyInfo = Get-VSVideoInfo $Job.ScriptFile
        Write-Log -Message $vpyInfo -Severity Info -Category 'VideoProcessor'

        # Encode video
        Write-Log "Start encoding video: $($Job.VideoPath)" -Severity Debug -Category 'VideoProcessor'
        & $global:VideoTools.VSPipe -c y4m $Job.ScriptFile - | & $global:VideoTools.SvtAv1Enc `
            --rc 0 --crf 26 --preset 3 --progress 2 `
            --output $Job.VideoOutput --input -
    
        $Job.TempFiles += $Job.VideoOutput
    }
    return $Job
}

Export-ModuleMember -Function Convert-VideoToAV1