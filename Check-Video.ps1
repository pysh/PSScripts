Param (
    [String]$InputFileDirName = ('
    f:\
    ').Trim(), 
    [array] $filterList = @(
        ".mkv", 
        ".mp4"
    ), 
    [Switch]$bRecurse = $false, 
    [Switch]$isDebug = $false
)


# Variables

# [Switch]$bRecurse = $true
[string]$execFFMPEG = "ffmpeg.exe"

# Functions

Function Execute-Command ($commandTitle, $commandPath, $commandArguments)
{
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
        stdout = $p.StandardOutput.ReadToEnd()
        stderr = $p.StandardError.ReadToEnd()
        ExitCode = $p.ExitCode
    }
    $p.WaitForExit()
}

<# 
Function Execute-Command_OLD ($commandTitle, $commandPath, $commandArguments) {
    Try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        # $pinfo.WindowStyle = 'Hidden'
        # $pinfo.CreateNoWindow = $true
        $pinfo.Arguments = $commandArguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $dt1 = Get-Date

        # Write-Host $commandPath, $commandArguments -ForegroundColor Magenta

        $p.Start()

        while (-not $p.HasExited) {
            Start-Sleep -Seconds 2
            Write-Host ("{0:hh\:mm\:ss}..." -f ($(Get-Date) - $dt1))
        }

        # Write-Host ("process exited in {0}, exit code: {1}" -f ($(Get-Date) - $dt1), $p.ExitCode) -ForegroundColor DarkGreen
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p | Add-Member "commandTitle" $commandTitle
        $p | Add-Member "stdout" $stdout
        $p | Add-Member "stderr" $stderr
        #$stderr | Out-File -LiteralPath $output -Force
        #$stdout | Out-File -LiteralPath $output -Force -Append
        #Set-Content -Value @($stderr, $stdout) -LiteralPath $output -Force
        Return $p
    }
    Catch {
        Write-Host "Error" -BackgroundColor Red
        Write-Host $PSItem.Exception -BackgroundColor Red
        Write-Host "Error" -BackgroundColor Red
        # if ($p) { $p.Kill() }
    }
}

#>





$InputFileList = Get-ChildItem ([Management.Automation.WildcardPattern]::Escape($InputFileDirName)) -File -Recurse:$bRecurse | Where-Object { (($_.Extension -iin $filterList) -and ($_.BaseName -inotlike '*`[av1an`]*')) }
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor DarkBlue

foreach ($InputFileName in $InputFileList) {
    if (Test-Path ([Management.Automation.WildcardPattern]::Escape($InputFileName)) ) {
        $prmFFMPEG = ''
        $prmFFMPEG = @(
            ("-i ""{0}""" -f $InputFileName),
            "-hide_banner",
            "-xerror", 
            "-f null",
            "out.null"
        )

    }
    Write-Host ("Processing: {0}" -f $InputFileName) -ForegroundColor Blue
    Write-Host ($prmFFMPEG -join ' ') -ForegroundColor Cyan
    $retVal = Execute-Command -commandPath $execFFMPEG -commandArguments ($prmFFMPEG -join ' ')
    switch ($retVal.ExitCode) {
        0 { Write-Host $retVal -ForegroundColor Green }
        Default { Write-Host $retVal.stderr -ForegroundColor Magenta }
    }

}










<# for ($i = 0; $i -lt $array.Count; $i++) {
    # Action that will repeat until the condition is met
}

[System.Management.Automation]$ps=Cla

$PSStyle.Progress.View = [System.Management.Automation] #>
