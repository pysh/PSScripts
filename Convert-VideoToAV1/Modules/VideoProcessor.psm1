<#
.SYNOPSIS
    Модуль для обработки видео
#>

function ConvertTo-Av1Video {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )
    
    try {
        $Job.ScriptFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).vpy"
        $Job.CacheFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).lwi"
        $Job.VideoOutput = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).ivf"

        if (-not (Test-Path -LiteralPath $Job.VideoOutput -PathType Leaf)) {
            Write-Log "Определение параметров обрезки..." -Severity Verbose -Category 'Video'
            $Job.CropParams = Get-VideoCropParameters -InputFile $Job.VideoPath -Round 2
            Write-Log "Параметры обрезки: left=$($Job.CropParams.Left), right=$($Job.CropParams.Right), top=$($Job.CropParams.Top), bottom=$($Job.CropParams.Bottom)" -Severity Verbose -Category 'Video'
        
            # Генерация скрипта VapourSynth
            $scriptContent = @"
import vapoursynth as vs
core = vs.core
clip = core.lsmas.LWLibavSource(source=r"$($Job.VideoPath)", cachefile=r"$($Job.CacheFile)")
clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.Crop(clip, $($Job.CropParams.Left), $($Job.CropParams.Right), $($Job.CropParams.Top), $($Job.CropParams.Bottom))
clip.set_output()
"@
            Set-Content -LiteralPath $Job.ScriptFile -Value $scriptContent -Force
            $Job.TempFiles.Add($Job.ScriptFile)
            $Job.TempFiles.Add($Job.CacheFile)
            Write-Log "Создан VapourSynth скрипт: $($Job.ScriptFile)" -Severity Debug -Category 'Video'

            # Получение информации о видео
            $vpyInfo = Get-VideoScriptInfo -ScriptPath $Job.ScriptFile
            Write-Log "Информация о видео: $($vpyInfo | Out-String)" -Severity Verbose -Category 'Video'

            # Кодирование видео
            Write-Log "Начало кодирования видео..." -Severity Information -Category 'Video'
            $vspipeArgs = @('-c', 'y4m', $Job.ScriptFile, '-')
            $encArgs = @('--rc', '0', '--crf', '26', '--preset', '6', '--progress', '2', '--output', $Job.VideoOutput, '--input', '-')
            
            & $global:VideoTools.VSPipe $vspipeArgs | & $global:VideoTools.SvtAv1Enc $encArgs
            
            if ($LASTEXITCODE -ne 0) {
                throw "Ошибка кодирования AV1 (код $LASTEXITCODE)"
            }

            $Job.TempFiles.Add($Job.VideoOutput)
            Write-Log "Видео успешно закодировано: $($Job.VideoOutput)" -Severity Success -Category 'Video'
        }
        else {
            Write-Log "Пропуск кодирования видео, файл уже существует: $($Job.VideoOutput)" -Severity Verbose -Category 'Video'
        }

        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке видео: $_" -Severity Error -Category 'Video'
        throw
    }
}

Export-ModuleMember -Function ConvertTo-Av1Video