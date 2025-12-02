<#
.SYNOPSIS
    Централизованное управление состоянием задачи обработки видео
#>

class VideoJob {
    # Основные свойства
    [string]$VideoPath
    [string]$BaseName
    [string]$WorkingDir
    [string]$FinalOutput
    [System.Collections.Generic.List[string]]$TempFiles
    [datetime]$StartTime
    
    # Кодирование
    [string]$Encoder
    [string]$EncoderPath
    [array]$EncoderParams
    [hashtable]$EncoderConfig
    
    # Метаданные
    [hashtable]$Metadata
    [hashtable]$NFOFields
    [string]$NfoTags
    
    # Обработка видео
    [double]$FrameRate
    [double]$TrimStartSeconds
    [double]$TrimDurationSeconds
    [object]$CropParams
    [object]$VPYInfo
    [object]$ColorInfo
    
    # Аудио
    [array]$AudioOutputs
    
    # Результаты
    [double]$Quality
    [string]$ScriptFile
    [string]$CacheFile
    [string]$VideoOutput
    
    # Флаги
    [bool]$IsMP4
    [bool]$IsHDR
    
    VideoJob() {
        $this.TempFiles = [System.Collections.Generic.List[string]]::new()
        $this.Metadata = @{}
        $this.StartTime = [DateTime]::Now
    }
    
    # Методы
    [void] AddTempFile([string]$path) {
        if (Test-Path -LiteralPath $path) {
            $this.TempFiles.Add($path)
        }
    }
    
    [void] Cleanup() {
        $removedCount = 0
        foreach ($file in $this.TempFiles) {
            try {
                if (Test-Path -LiteralPath $file) {
                    Remove-Item -LiteralPath $file -Force -Recurse -ErrorAction SilentlyContinue
                    $removedCount++
                }
            }
            catch {
                Write-Log "Не удалось удалить временный файл ${file}: $_" -Severity Warning
            }
        }
        Write-Log "Удалено $removedCount временных файлов" -Severity Information
    }
    
    [string] GetDuration() {
        $duration = [DateTime]::Now - $this.StartTime
        return $duration.ToString('hh\:mm\:ss')
    }
    
    [string] ToString() {
        return "VideoJob: $($this.BaseName) [Encoder: $($this.Encoder)]"
    }
}