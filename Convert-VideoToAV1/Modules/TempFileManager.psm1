<#
.SYNOPSIS
    Temp file manager for PowerShell 7+
#>

using namespace System.IO
using namespace System.Collections.Generic

class TempFileManager : System.IDisposable {
    hidden [List[string]]$tempItems = [List[string]]::new()
    [string]$WorkingDirectory

    TempFileManager([string]$baseWorkingDir) {
        $this.WorkingDirectory = Join-Path $baseWorkingDir "temp_$(New-Guid)"
        $this.CreateDirectory($this.WorkingDirectory)
    }

    [string] CreateDirectory([string]$name) {
        $path = Join-Path $this.WorkingDirectory $name
        if (-not (Test-Path -LiteralPath $path)) {
            $null = New-Item -Path $path -ItemType Directory -Force
            $this.tempItems.Add($path)
        }
        return $path
    }

    [string] CreateTempFile([string]$extension = 'tmp', [string]$subDir) {
        $parentDir = $this.WorkingDirectory
        if ($subDir) { $parentDir = $this.CreateDirectory($subDir) }

        $tempFile = Join-Path $parentDir "$(New-Guid).$extension"
        $null = New-Item -Path $tempFile -ItemType File -Force
        $this.tempItems.Add($tempFile)
        return $tempFile
    }

    [void] RegisterItem([string]$path) {
        if (Test-Path -LiteralPath $path) {
            $this.tempItems.Add($path)
        }
    }

    [void] Cleanup() {
        $removedCount = 0
        $errors = 0

        for ($i = $this.tempItems.Count - 1; $i -ge 0; $i--) {
            $item = $this.tempItems[$i]
            try {
                if (Test-Path -LiteralPath $item) {
                    Remove-Item -LiteralPath $item -Force -Recurse -ErrorAction Stop
                    $removedCount++
                }
            }
            catch { $errors++ }
        }

        try {
            if (Test-Path -LiteralPath $this.WorkingDirectory) {
                Remove-Item -LiteralPath $this.WorkingDirectory -Recurse -Force -ErrorAction Stop
                $removedCount++
            }
        }
        catch { $errors++ }

        $this.tempItems.Clear()
    }

    [void] Dispose() {
        $this.Cleanup()
        [GC]::SuppressFinalize($this)
    }

    [string] ToString() {
        return "TempFileManager: $($this.tempItems.Count) items in $($this.WorkingDirectory)"
    }
}

function New-TempFileManager {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BaseDirectory)
    return [TempFileManager]::new($BaseDirectory)
}

Export-ModuleMember -Function New-TempFileManager