function Invoke-Process2 {
    param (
        [Parameter(Mandatory=$true)]
        [string]$commandPath,
        
        [Parameter(Mandatory=$false)]
        [string]$commandArguments = "",
        
        [Parameter(Mandatory=$false)]
        [string]$workingDirectory = $null,
        
        [Parameter(Mandatory=$false)]
        [int]$timeoutSeconds = 0
    )
    
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $commandArguments
        
        if ($workingDirectory) {
            $pinfo.WorkingDirectory = $workingDirectory
        }
        
        $stdoutBuilder = New-Object System.Text.StringBuilder
        $stderrBuilder = New-Object System.Text.StringBuilder
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo
        
        # Set up output handlers with renamed parameters
        $process.add_OutputDataReceived({
            param($sourceProcess, $eventArgs)
            if ($eventArgs.Data) {
                [void]$stdoutBuilder.AppendLine($eventArgs.Data)
                Write-Verbose $eventArgs.Data
            }
        })
        
        $process.add_ErrorDataReceived({
            param($sourceProcess, $eventArgs)
            if ($eventArgs.Data) {
                [void]$stderrBuilder.AppendLine($eventArgs.Data)
                Write-Warning $eventArgs.Data
            }
        })
        
        $process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        # Wait for exit with optional timeout
        $completed = if ($timeoutSeconds -gt 0) {
            $process.WaitForExit($timeoutSeconds * 1000)
        } else {
            $process.WaitForExit()
            $true
        }
        
        if (-not $completed) {
            Write-Warning "Process timed out after $timeoutSeconds seconds"
            try {
                $process.Kill()
            } catch {
                Write-Warning "Failed to kill process: $_"
            }
        }
        
        return @{
            exitCode = if ($completed) { $process.ExitCode } else { -1 }
            stdout = $stdoutBuilder.ToString()
            stderr = $stderrBuilder.ToString()
            timedOut = -not $completed
        }
    }
    catch {
        Write-Error "Failed to execute process: $_"
        throw
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
    }
}

# Example usage
$result = Invoke-Process2 -commandPath 'ffmpeg' -commandArguments '-version' -timeoutSeconds 30 -Verbose
Write-Host "Exit code: $($result.exitCode)"
Write-Host "Output: $($result.stdout)"
Write-Host "Error: $($result.stderr)"
# Example usage
# $result = Invoke-Process2 -commandPath 'ffmpeg' `
#     -commandArguments '-version' `
#     -timeoutSeconds 30 `
#     -Verbose

#$result = Invoke-Process2 -commandPath 'ffmpeg' -commandArguments '-hide_banner -nostats -y -i "y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\01\The.Walking.Dead.S01E01_[x265][crf=23][hqdn3d].mkv" -i "y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\The.Walking.Dead.S01E01.mkv" -frames:v 1500 -filter_complex xpsnr -an -sn -dn -f null -'
#$result









#region old function
<#
function Invoke-Process2 {
    param (
        [Parameter(Mandatory=$true)]
        [string]$commandPath,
        
        [Parameter(Mandatory=$false)]
        [string]$commandArguments = "",
        
        [Parameter(Mandatory=$false)]
        [string]$workingDirectory = $null
    )
    
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $commandArguments
        
        if ($workingDirectory) {
            $pinfo.WorkingDirectory = $workingDirectory
        }
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo
        $process.Start() #| Out-Null
        
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        return @{
            exitCode = $process.ExitCode
            stdout = $stdout
            stderr = $stderr
        }
    }
    catch {
        Write-Error "Failed to execute process: $_"
        throw
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
    }
}

# Example usage
# $result = Invoke-Process2 -commandPath 'ffmpeg' `
#     -commandArguments '-version' `
#     -timeoutSeconds 30 `
#     -Verbose

#$result = Invoke-Process2 -commandPath 'ffmpeg' -commandArguments '-hide_banner -nostats -y -i "y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\01\The.Walking.Dead.S01E01_[x265][crf=23][hqdn3d].mkv" -i "y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\The.Walking.Dead.S01E01.mkv" -frames:v 1500 -filter_complex xpsnr -an -sn -dn -f null -'
#$result
#>

#endregion