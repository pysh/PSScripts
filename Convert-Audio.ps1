Param (
    [System.String]$filePath = 'W:\.temp\Youtube'
)
[datetime]$dtFrom     = Get-Date
[string]$ffmpeg     = 'X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.exe'
[string]$qaac       = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\qaac\qaac64.exe'

#$filterList= @(".mp2", ".mp3", ".mpa", ".ogg", ".opus", ".dts", ".dtshd", ".ac3", ".eac3", ".thd", ".wav")
$filterList = @(".dts", ".ac3")
[string]$qaacTVBRQuality = '--tvbr 91'
[string]$OpusBitrate = "-b:a 128k"
[string]$OutputCodec = "AAC" # (AAC, Opus)
[bool]$Normalize  = $true
#[bool]$isDebug    = $false

# QAAC quality
# Ch    q217        q118        q109        q91
# ---   --------    --------    --------    --------
# 7.1   999 Kbps    933 Kbps    865 Kbps    731 Kbps
# 6.1   875 Kbps    816 Kbps    757 Kbps    639 Kbps
# 5.1   750 Kbps    700 Kbps    649 Kbps    548 Kbps
# 2.0   250 Kbps    233 Kbps    216 Kbps    183 Kbps
# 1.0   125 Kbps    117 Kbps    108 Kbps     91 Kbps

# X:\Apps\_VideoEncoding\StaxRip\Apps\FrameServer\AviSynth\ffmpeg.exe -i "X:\temp\Kaleidoscope.S01E00.Black.2160p_temp\ID1 Russian {HDR}.ac3" -c:a libopus -b:a 128k -af volume=3.1dB -ac 2 -y -hide_banner "X:\temp\Kaleidoscope.S01E00.Black.2160p_temp\ID1 Russian {HDR}_3310543885.opus"


Function Execute-Command ($commandTitle, $commandPath, $commandArguments)
{
    Try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $commandPath
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.WindowStyle = 'Hidden'
        $pinfo.CreateNoWindow = $true
        $pinfo.Arguments = $commandArguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $dt1 = Get-Date
        $p.Start() | Out-Null

        while (-not $p.HasExited) {
            Start-Sleep -Milliseconds 500
            Write-Host ("...{0}... {1}" -f ($(Get-Date) - $dt1), $p.StandardError.EndOfStream)
        }

        #Write-Host ("process exited in {0}" -f ($(Get-Date) - $dt1)) -ForegroundColor DarkGreen
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


function Convert-File {
    param (
        [array]$InputFileList
    )
    
    if ($InputFileList -eq '') {
        Write-Host "Нечего конвертировать" -ForegroundColor DarkRed
        Return $null
    }
    $n = 0
    Write-Host ''
    Write-Host '=========================================================='
    foreach ($InputFile in [array]$InputFileList) {
        $n++
        $OutputAAC = ("{0}\{1}.{2}" -f $InputFile.DirectoryName, $InputFile.BaseName, "m4a")
        Write-Host ("{0}/{1}  {2}" -f $n, $InputFileList.Count, $InputFile.Name)

        if (Test-Path -LiteralPath $OutputAAC) {
            Write-Host ("Output file exists, skipping..." -f (Get-Item -LiteralPath $OutputAAC).Name) -ForegroundColor DarkMagenta
        }   else         {
            <#
            ----------------------------------------------------------
            Find gain
            ---------------------------------------------------------- 
            #>
            #$OutputGain = ("{0}\{1}.{2}" -f [WildcardPattern]::Escape($InputFile.DirectoryName), "~tmp", "vol.txt")
            if ($Normalize) {

                #$OutputGain = ("{0}\{1}_{2}" -f $InputFile.DirectoryName, $InputFile.BaseName, "gain.txt") #.Replace('{','`{').Replace('}','`}')
                $ArgList = @("-i ""$InputFile""",
                            "-sn", "-vn", "-hide_banner", "-af volumedetect", "-f null NUL")
                Write-Host 'Volume detecting...' -ForegroundColor Yellow -NoNewline
                
                
                ##$exec = Invoke-Process -FilePath $ffmpeg -ArgumentList ($ArgList -join " ") -DisplayLevel Full
                #Start-Process -FilePath $ffmpeg -ArgumentList $ArgList -Wait -NoNewWindow # -RedirectStandardError $OutputGain | Out-Null
                
                $exec = Execute-Command -commandTitle "Volumedetect" -commandPath $ffmpeg -commandArguments ($ArgList -join " ")

                #Write-Host $exec.stderr -ForegroundColor Gray
                $RegExp = '.*?max_volume: (?<sign>[-]?)(?<gain>.*?) dB.*'
                $matchResult = [regex]::Matches($exec.stderr, $RegExp)
                
                foreach ($m in ($matchResult | Select-Object -First 1)) { 
                    [string]$GainValue = $m.Groups.Item("gain").Value
                    [string]$SignValue = $m.Groups.Item("sign").Value
                    if ($SignValue -eq "-") { $Gain = ("-af volume={0}dB" -f $GainValue) } else { $Gain = ("-af volume=-{0}dB" -f $GainValue) }
                    }
                    [decimal]$GainValueNum = [decimal]$GainValue
                    If ($GainValueNum -ge 15) {
                        Write-Host ("Gain {0} is too high. Check regex: ""{1}"""-f $GainValue, $RegExp) -BackgroundColor Red
                        Write-Host $exec.stderr -BackgroundColor Red
                        Exit
                    }
                Write-Host ("`t{0}{1}dB" -f $SignValue, $GainValue) -ForegroundColor DarkYellow
            } else {
                $Gain = ''
                Write-Host 'Пропускаем нормализацию громкости' -ForegroundColor Yellow
            }

            if ($OutputCodec -eq 'AAC') {
                <#
                ---------------------------------------------------------- 
                Convert to Opus
                ---------------------------------------------------------- 
                #>
                # X:\Apps\_VideoEncoding\StaxRip\Apps\FrameServer\AviSynth\ffmpeg.exe -i "X:\temp\Kaleidoscope.S01E00.Black.2160p_temp\ID1 Russian {HDR}.ac3" -c:a libopus -b:a 128k -af volume=3.1dB -ac 2 -y -hide_banner "X:\temp\Kaleidoscope.S01E00.Black.2160p_temp\ID1 Russian {HDR}_3310543885.opus"

                Write-Host ("QAAC {0}.." -f $Gain) -ForegroundColor Yellow -NoNewline
                $OutputAAC = ("{0}\{1}.{2}" -f $InputFile.DirectoryName, $InputFile.BaseName, "opus")
                $ArgList = @("-i ""$InputFile""", 
                            "-c:a libopus", 
                            $OpusBitrate, 
                            $Gain, 
                            #"-ac 2", 
                            "-y", "-hide_banner",
                            """$OutputAAC""")

                Start-Process -Path $qaac -ArgumentList $ArgList -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
                Write-Host "`tOk" -ForegroundColor DarkYellow
            } else {
                <#
                ---------------------------------------------------------- 
                Convert to FLAC
                ---------------------------------------------------------- 
                #>
                Write-Host 'Converting to FLAC...' -ForegroundColor Yellow -NoNewline
                $OutputFlac= ("{0}\{1}.{2}" -f $InputFile.DirectoryName, $InputFile.BaseName, "flac")
                $ArgList = @("-i ""$InputFile""", 
                            $Gain, 
                            #"-ac 2", 
                            "-y", "-hide_banner",
                            """$OutputFlac""")

                Start-Process -Path $ffmpeg -ArgumentList $ArgList -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
                Write-Host "`tOk" -ForegroundColor DarkYellow
                
                <#
                ----------------------------------------------------------
                Encoding to AAC
                ----------------------------------------------------------
                #>
                Write-Host ("QAAC {0}.." -f $Gain) -ForegroundColor Yellow -NoNewline
                $OutputAAC = ("{0}\{1}.{2}" -f $InputFile.DirectoryName, $InputFile.BaseName, "m4a")
                $ArgList = @($qaacTVBRQuality,  """$OutputFlac""", " -o ""$OutputAAC""")

                Start-Process -Path $qaac -ArgumentList $ArgList -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
                Write-Host "`tOk" -ForegroundColor DarkYellow

                <#
                ----------------------------------------------------------
                Cleanup
                ----------------------------------------------------------
                #>
                Write-Host 'Cleaning up...' -ForegroundColor Yellow -NoNewline
                #if (Test-Path -LiteralPath $OutputGain) {Remove-Item -LiteralPath $OutputGain -Force}
                if (Test-Path -LiteralPath $OutputFlac) {
                    Remove-Item -LiteralPath $OutputFlac -Force
                    if (Test-Path $OutputFlac) {
                        Write-Host ("`tErr" -f $OutputFlac) -ForegroundColor DarkRed
                    } else {
                        Write-Host ("`t`tOk" -f $OutputFlac) -ForegroundColor DarkYellow
                    }
                } else {
                    Write-Host ("`tCan not find file: {0}..." -f $OutputFlac) -NoNewline -ForegroundColor DarkRed
                }
            }

            $fileSizeFrom = ("{0:0.00}" -f ($InputFile.Length/1Mb))
            $fileSizeTo   = ("{0:0.00}" -f ((Get-Item -LiteralPath $OutputAAC).Length/1Mb))
            Write-Host ("Size: {0} Mb ==> {1} Mb  ( {2:0.00}% )" -f $fileSizeFrom, $fileSizeTo, ($fileSizeTo/$fileSizeFrom*100)) -ForegroundColor DarkGreen
        }
        Write-Host "=========================================================="
        #Start-Sleep -Seconds 2
    }
}

# -----------------------------------

Clear-Host
$filePath = (Get-Item -LiteralPath $filePath).FullName

$files = Get-ChildItem -LiteralPath $filePath -File -Recurse | Where-Object {$_.Extension -iin $filterList}
Write-Host ("Найдено файлов: {0}" -f $files.Count) -ForegroundColor DarkGreen


$FileList = @()
foreach ($f in $files) {
    if ( Test-Path -LiteralPath $f.FullName ) {
        Write-Host ($f.Name) -ForegroundColor DarkGreen
        $FileList += ( Get-Item -LiteralPath $f )
    }
}
Convert-File -InputFileList $FileList

[datetime]$dtTo = Get-Date
Write-Host ("Выполнено за {0}" -f ($dtTo - $dtFrom)) -ForegroundColor Blue

<#
Convert-File -InputFile @(
    (Get-Item -LiteralPath 'x:\temp\test\Resident.Alien.2022.S02E01_{Kubik v Kube}_2ch_DELAY 0ms.ac3'),
    (Get-Item -LiteralPath 'x:\temp\test\Resident.Alien.2022.S02E01_{Kubik v Kube}_6ch_DELAY 0ms.ac3')
    )
#>