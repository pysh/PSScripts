function Invoke-Executable {
    # from https://stackoverflow.com/a/24371479/52277
    # Runs the specified executable and captures its exit code, stdout
    # and stderr.
    # Returns: custom object.
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$sExeFile,

        [Parameter(Mandatory = $false)]
        [String[]]$cArgs,

        [Parameter(Mandatory = $false)]
        [String]$sVerb,

        [Parameter(Mandatory = $false)]
        [String]$sWorkDir,

        [Parameter(Mandatory = $false)]
        [bool]$outStatus = $false
    )

    # Setting process invocation parameters.
    $oPsi = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $oPsi.CreateNoWindow = $true
    $oPsi.UseShellExecute = $false
    $oPsi.RedirectStandardOutput = $true
    $oPsi.RedirectStandardError = $true
    $oPsi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $oPsi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $oPsi.FileName = $sExeFile
    if (! [String]::IsNullOrEmpty($cArgs)) {
        $oPsi.Arguments = $cArgs -join " "
    }
    if (! [String]::IsNullOrEmpty($sVerb)) {
        $oPsi.Verb = $sVerb
    }
    if (! [String]::IsNullOrEmpty($sWorkDir)) {
        $oPsi.WorkingDirectory = $sWorkDir
    }
    
    # Creating process object.
    $oProcess = New-Object -TypeName System.Diagnostics.Process
    $oProcess.StartInfo = $oPsi

    # Creating string builders to store stdout and stderr.
    $oStdOutBuilder = New-Object -TypeName System.Text.StringBuilder
    $oStdErrBuilder = New-Object -TypeName System.Text.StringBuilder

    # Adding event handers for stdout and stderr.
    $sScripBlock = {
        if (! [String]::IsNullOrEmpty($EventArgs.Data)) {
            $Event.MessageData.AppendLine($EventArgs.Data)
        }
    }
    $oStdOutEvent = Register-ObjectEvent -InputObject $oProcess `
        -Action $sScripBlock -EventName 'OutputDataReceived' `
        -MessageData $oStdOutBuilder
    $oStdErrEvent = Register-ObjectEvent -InputObject $oProcess `
        -Action $sScripBlock -EventName 'ErrorDataReceived' `
        -MessageData $oStdErrBuilder

    # Starting process.
    $dt1 = Get-Date
    $oProcess.Start() | Out-Null
    $oProcess.BeginOutputReadLine()
    $oProcess.BeginErrorReadLine()

    if ($outStatus) {
        while (-not $oProcess.HasExited) {
            Start-Sleep -Seconds 2
            Write-Host ("{0:hh\:mm\:ss}..." -f ($(Get-Date) - $dt1))
        }
    }
    else {
        $oProcess.WaitForExit()
    }

    # Unregistering events to retrieve process output.
    Unregister-Event -SourceIdentifier $oStdOutEvent.Name
    Unregister-Event -SourceIdentifier $oStdErrEvent.Name

    return @{
        ExitCode = $oProcess.ExitCode
        StdOut   = $oStdOutBuilder.ToString().Trim()
        StdErr   = $oStdErrBuilder.ToString().Trim()
        ExeFile  = $sExeFile
        Args     = $cArgs -join " "
    }
}