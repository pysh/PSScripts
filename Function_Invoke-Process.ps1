
Function Invoke-Process {
    #[CmdletBinding()]
    param (
        #[Parameter()]
        #[TypeName]
        #[PSDefaultValue(WorkDir = 'Get-Location')]
        [string]$commandPath,
        [string]$commandArguments,
        [string]$commandTitle, 
        [string]$workingDir
    )

    Try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.WorkingDirectory = $workingDir
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $commandArguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() #| Out-Null
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