

Function Execute-Command ($commandTitle, $commandPath, $commandArguments) {
    Try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        # $pinfo.WindowStyle = 'Hidden'
        # $pinfo.CreateNoWindow = $true
        $pinfo.Arguments = $commandArguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        # $dt1 = Get-Date

        # Write-Host $commandPath, $commandArguments -ForegroundColor Magenta

        $p.Start() | Out-Null

        while (-not $p.HasExited) {
            Start-Sleep -Milliseconds 500
            # Write-Host ("...{0}... {1}" -f ($(Get-Date) - $dt1), $p.StandardError.EndOfStream)
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
    }
}

function Get-ColorSpaceFromVideoFile {
    param (
        [string]$inFileName
    )
    
    $RegExp = '(?:(?:^color_range=(?<color_range>\w*))|(?:^color_space=(?<color_space>\w*))|(?:^color_transfer=(?<color_transfer>.*))|(?:^color_primaries=(?<color_primaries>.*))|(?:^color_matrix=(?<color_matrix>.*)))'
    # $RegExp = '(?:.*color_range=)(?<color_range>.*)(?:\n|\r)(?:.*color_space=)(?<color_space>.*)(?:\n|\r)(?:.*color_transfer=)(?<color_transfer>.*)(?:\n|\r)(?:.*color_primaries=)(?<color_primaries>.*)'
    # $inFileName = 'W:\Видео\Сериалы\Зарубежные\Одни из нас (The Last Of Us)\season 01\The.Last.of.Us.S01E.2160p.HMAX.WEB-DL.x265.HDR.Master5\The.Last.of.Us.S01E01.2160p.HDR.Master5.mkv'
    if (Test-Path -LiteralPath $inFileName) {
        $r = @()
        Clear-Variable color_*
        # $outFileName = [System.IO.Path]::ChangeExtension($inFileName, 'colors')
        $params = @(
            '-hide_banner', 
            '-v 0', 
            '-select_streams 0', 
            '-show_streams', 
            ('-i "{0}"' -f $inFileName)
        )
        $retVal = (Execute-Command -commandTitle 'Get color settings...' -commandPath 'X:\Apps\_VideoEncoding\av1an\ffprobe.exe' -commandArguments ($params -join ' ')).stdout
        $retVal
        $matchResult = [regex]::Matches($retVal, $RegExp, [Text.RegularExpressions.RegexOptions]::Multiline)
        # Write-Host 'found results: ' $matchResult.Count -ForegroundColor Cyan
        foreach ($m in ($matchResult)) { 
            if ($m.Groups.Item("color_range").Value -ne '') { [string]$color_range = $m.Groups.Item("color_range").Value }
            elseif ($m.Groups.Item("color_space").Value -ne '') { [string]$color_space = $m.Groups.Item("color_space").Value }
            elseif ($m.Groups.Item("color_transfer").Value -ne '') { [string]$color_transfer = $m.Groups.Item("color_transfer").Value }
            elseif ($m.Groups.Item("color_primaries").Value -ne '') { [string]$color_primaries = $m.Groups.Item("color_primaries").Value }
            elseif ($m.Groups.Item("color_matrix").Value -ne '') { [string]$color_matrix = $m.Groups.Item("color_matrix").Value }
        }

        #     () { [string]$color_range     = $m.Groups.Item("color_range").Value }
        #     # Default {}
        # }
            
            
        # [string]$color_range     = $m.Groups.Item("color_range").Value
        # [string]$color_space     = $m.Groups.Item("color_space").Value
        # [string]$color_transfer  = $m.Groups.Item("color_transfer").Value
        # [string]$color_primaries = $m.Groups.Item("color_primaries").Value
        
        #Write-Host $r -ForegroundColor Blue
    }
    $r = [PSCustomObject]@{
        color_range     = $color_range; 
        color_space     = $color_space; 
        color_transfer  = $color_transfer; 
        color_primaries = $color_primaries; 
        color_matrix    = $color_matrix 
    }
    return $r
}

# $colors = (Get-ColorSpaceFromVideoFile -inFileName ('
# W:\Видео\Сериалы\Зарубежные\Одни из нас (The Last Of Us)\season 01\The.Last.of.Us.S01E.2160p.HMAX.WEB-DL.x265.HDR.Master5\The.Last.of.Us.S01E09.2160p.HDR.Master5.mkv
# ').Trim())

# $colors | Format-List