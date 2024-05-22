
Function Invoke-Process ([string]$commandTitle, [string]$commandPath, [string]$commandArguments) {
    Try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $commandArguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        [pscustomobject]@{
            commandTitle = $commandTitle
            Command      = $commandPath
            Arguments    = $commandArguments
            stdout       = $p.StandardOutput.ReadToEnd()
            stderr       = $p.StandardError.ReadToEnd()
            ExitCode     = $p.ExitCode
        }
        $p.WaitForExit()
    }
    Catch {
        Write-Host "Error" -BackgroundColor Red
        Write-Host $PSItem.Exception -BackgroundColor Red
        Write-Host "Error" -BackgroundColor Red
        exit
    }
}