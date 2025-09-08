<#
.SYNOPSIS
    Модуль для обработки видео
#>

function ConvertTo-Av1Video {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        $Job.ScriptFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).vpy"
        $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).lwi"
        $Job.VideoOutput = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).ivf"

        if (-not (Test-Path -LiteralPath $Job.VideoOutput -PathType Leaf)) {
            Write-Log "Определение параметров обрезки..." -Severity Verbose -Category 'Video'
            $Job.CropParams = Get-VideoCropParameters -InputFile $Job.VideoPath
            
            # Генерация скрипта с обрезкой по времени
            $trimScript = ""
            if ($Job.TrimStartSeconds -gt 0) {
                $startFrame = [math]::Round($Job.TrimStartSeconds * $Job.FrameRate)
                $endFrame = if ($Job.TrimDurationSeconds -gt 0) {
                    [math]::Round(($Job.TrimStartSeconds + $Job.TrimDurationSeconds) * $Job.FrameRate)
                } else { 0 }
                
                if ($endFrame -gt 0) {
                    $trimScript = "clip = core.std.Trim(clip, first=$startFrame, last=$endFrame)`n"
                } else {
                    $trimScript = "clip = core.std.Trim(clip, first=$startFrame)`n"
                }
            }
            
            $scriptContent = @"
import vapoursynth as vs
core = vs.core
clip = core.lsmas.LWLibavSource(source=r"$($Job.VideoPath)", cachefile=r"$($Job.CacheFile)")
$trimScript
clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.Crop(clip, $($Job.CropParams.Left), $($Job.CropParams.Right), $($Job.CropParams.Top), $($Job.CropParams.Bottom))
clip.set_output()
"@
            Set-Content -LiteralPath $Job.ScriptFile -Value $scriptContent -Force
            $Job.TempFiles.Add($Job.ScriptFile)
            $Job.TempFiles.Add($Job.CacheFile)
            # Получение информации о видео
            $vpyInfo = Get-VideoScriptInfo -ScriptPath $Job.ScriptFile
            $Job.VPYInfo = $vpyInfo
            Write-Log "Информация о видео: $($vpyInfo | Out-String)" -Severity Verbose -Category 'Video'

            # Кодирование
            $vspipeArgs = @('-c', 'y4m', $Job.ScriptFile, '-')
            $encArgs = @(
                '--rc', '0', '--crf', $global:Config.Encoding.Video.CRF,
                '--preset', $global:Config.Encoding.Video.Preset, '--progress', '2',
                '--output', $Job.VideoOutput, '--input', '-'
            )
            $Job.vspipeArgs = $vspipeArgs
            $Job.encArgs = $encArgs
            # Write-Log -Message "& $($global:VideoTools.VSPipe) $($vspipeArgs -join ' ') | & $($global:VideoTools.SvtAv1Enc) $($encArgs -join ' ')" -Severity Debug -Category 'Encoding'
            
            & $global:VideoTools.VSPipe $vspipeArgs | & $global:VideoTools.SvtAv1Enc $encArgs
            
            if ($LASTEXITCODE -ne 0) {
                throw "Ошибка кодирования AV1 (код $LASTEXITCODE)"
            }

            $Job.TempFiles.Add($Job.VideoOutput)
            Write-Log "Видео успешно закодировано" -Severity Success -Category 'Video'
        }
        else {
            Write-Log "Пропуск кодирования видео" -Severity Verbose -Category 'Video'
        }

        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке видео: $_" -Severity Error -Category 'Video'
        throw
    }
}

Export-ModuleMember -Function ConvertTo-Av1Video