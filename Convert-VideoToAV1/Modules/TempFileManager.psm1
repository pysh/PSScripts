<#
.SYNOPSIS
    Modern temp file manager for PowerShell 7+
#>

using namespace System.IO
using namespace System.Collections.Generic

class TempFileManager : System.IDisposable {
    # Список временных файлов и директорий
    hidden [List[string]]$tempItems = [List[string]]::new()

    # Основная рабочая директория
    [string]$WorkingDirectory

    # Конструктор
    TempFileManager([string]$baseWorkingDir) {
        $this.WorkingDirectory = Join-Path $baseWorkingDir "temp_$(New-Guid)"
        $this.CreateDirectory($this.WorkingDirectory)
        Write-Debug "TempFileManager initialized: $($this.WorkingDirectory)"
    }

    # Создает и отслеживает новую директорию
    [string] CreateDirectory([string]$name) {
        $path = Join-Path $this.WorkingDirectory $name
        if (-not (Test-Path -LiteralPath $path)) {
            $null = New-Item -Path $path -ItemType Directory -Force
            $this.tempItems.Add($path)
            Write-Debug "Created temp directory: $path"
        }
        return $path
    }

    # Создает временный файл
    [string] CreateTempFile([string]$extension = 'tmp', [string]$subDir) {
        $parentDir = $this.WorkingDirectory
        if ($subDir) {
            $parentDir = $this.CreateDirectory($subDir)
        }

        $tempFile = Join-Path $parentDir "$(New-Guid).$extension"
        $null = New-Item -Path $tempFile -ItemType File -Force
        $this.tempItems.Add($tempFile)
        Write-Debug "Created temp file: $tempFile"
        return $tempFile
    }

    # Регистрирует существующий файл/директорию
    [void] RegisterItem([string]$path) {
        if (Test-Path -LiteralPath $path) {
            $this.tempItems.Add($path)
            Write-Debug "Tracking existing item: $path"
        }
    }

    # Очистка всех временных файлов
    [void] Cleanup() {
        $removedCount = 0
        $errors = 0

        # Удаление в обратном порядке
        for ($i = $this.tempItems.Count - 1; $i -ge 0; $i--) {
            $item = $this.tempItems[$i]
            try {
                if (Test-Path -LiteralPath $item -PathType Leaf) {
                    Remove-Item -LiteralPath $item -Force -ErrorAction Stop
                    $removedCount++
                }
                elseif (Test-Path -LiteralPath $item -PathType Container -and $item -ne $this.WorkingDirectory) {
                    Remove-Item -LiteralPath $item -Recurse -Force -ErrorAction Stop
                    $removedCount++
                }
            }
            catch {
                $errors++
                Write-Warning "Failed to remove temp item ${item}: $_"
            }
        }

        # Удаление основной рабочей директории
        try {
            if (Test-Path -LiteralPath $this.WorkingDirectory) {
                Remove-Item -LiteralPath $this.WorkingDirectory -Recurse -Force -ErrorAction Stop
                $removedCount++
            }
        }
        catch {
            $errors++
            Write-Warning "Failed to remove working directory $($this.WorkingDirectory): $_"
        }

        $this.tempItems.Clear()
        Write-Verbose "Cleanup completed. Removed: $removedCount, Errors: $errors"
    }

    # Реализация IDisposable
    [void] Dispose() {
        $this.Cleanup()
        [GC]::SuppressFinalize($this)
    }

    # Строковое представление
    [string] ToString() {
        return "TempFileManager: $($this.tempItems.Count) items in $($this.WorkingDirectory)"
    }
}

<#
.SYNOPSIS
    Создает новый экземпляр TempFileManager
#>
function New-TempFileManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseDirectory
    )

    return [TempFileManager]::new($BaseDirectory)
}

# Экспорт только функции, класс будет доступен автоматически
Export-ModuleMember -Function New-TempFileManager