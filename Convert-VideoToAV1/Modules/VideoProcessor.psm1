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
            
<#             $scriptContent = @"
import vapoursynth as vs
core = vs.core
clip = core.lsmas.LWLibavSource(source=r"$($Job.VideoPath)", cachefile=r"$($Job.CacheFile)")
$trimScript
clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.Crop(clip, $($Job.CropParams.Left), $($Job.CropParams.Right), $($Job.CropParams.Top), $($Job.CropParams.Bottom))
clip.set_output()
"@ #>

            $scriptContent = ($Global:Config.Templates.VapourSynth.MainScript)
            $scriptContent = $scriptContent.Replace('{%VideoPath%}', $Job.VideoPath)
            $scriptContent = $scriptContent.Replace('{%CacheFile%}', $Job.CacheFile)
            $scriptContent = $scriptContent.Replace('{%trimScript%}', $trimScript)
            $scriptContent = $scriptContent.Replace('{%CropParams.Left%}', $Job.CropParams.Left)
            $scriptContent = $scriptContent.Replace('{%CropParams.Right%}', $Job.CropParams.Right)
            $scriptContent = $scriptContent.Replace('{%CropParams.Top%}', $Job.CropParams.Top)
            $scriptContent = $scriptContent.Replace('{%CropParams.Bottom%}', $Job.CropParams.Bottom)

            Write-Log "Создание скрипта:`r`n{$scriptContent}" -Severity Verbose -Category 'Video'

            Set-Content -LiteralPath $Job.ScriptFile -Value $scriptContent -Force
            $Job.TempFiles.Add($Job.ScriptFile)
            $Job.TempFiles.Add($Job.CacheFile)
            
            # Получение информации о видео
            $vpyInfo = Get-VideoScriptInfo -ScriptPath $Job.ScriptFile
            $Job.VPYInfo = $vpyInfo
            Write-Log "Информация о видео: $($vpyInfo | Out-String)" -Severity Verbose -Category 'Video'

            # Кодирование с выбранным энкодером
            $vspipeArgs = @('-c', 'y4m', $Job.ScriptFile, '-')
            $encArgs = @(
                '--output', $Job.VideoOutput,
                '--input', '-'
            )
            
            # Добавляем параметр --frames с количеством кадров из VPY скрипта
            if ($vpyInfo.Frames -gt 0) {
                $encArgs = @('--frames', $vpyInfo.Frames) + $encArgs
                Write-Log "Добавлен параметр --frames со значением $($vpyInfo.Frames)" -Severity Verbose -Category 'Encoding'
            }
            
            # Добавляем специфичные параметры энкодера
            $encArgs = $Job.EncoderParams + $encArgs
            
            Write-Log "Запуск энкодера: $($Job.EncoderPath) $($encArgs -join ' ')" -Severity Debug -Category 'Encoding'
            
            & $global:VideoTools.VSPipe $vspipeArgs | & $Job.EncoderPath $encArgs
            
            if ($LASTEXITCODE -ne 0) {
                throw "Ошибка кодирования AV1 энкодером $($Job.Encoder) (код $LASTEXITCODE)"
            }

            $Job.TempFiles.Add($Job.VideoOutput)
            Write-Log "Видео успешно закодировано энкодером $($Job.Encoder)" -Severity Success -Category 'Video'
            
            # Сравнение количества кадров VPY скрипта и закодированного видео
            $encodedVideoInfo = Get-VideoStats -VideoFilePath $Job.VideoOutput
            if ($vpyInfo.Frames -eq $encodedVideoInfo.FrameCount) {
                Write-Log "Проверка кадров: OK - VPY скрипт ( $($vpyInfo.Frames) кадров ) = закодированное видео ( $($encodedVideoInfo.FrameCount) кадров )" -Severity Success -Category 'Video'
            } else {
                Write-Log "ПРЕДУПРЕЖДЕНИЕ: Несоответствие количества кадров! VPY скрипт: $($vpyInfo.Frames), закодированное видео: $($encodedVideoInfo.FrameCount)" -Severity Warning -Category 'Video'
            }
        }
        else {
            Write-Log "Пропуск кодирования видео" -Severity Verbose -Category 'Video'
        }

        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке видео энкодером $($Job.Encoder): $_" -Severity Error -Category 'Video'
        throw
    }
}

Export-ModuleMember -Function ConvertTo-Av1Video