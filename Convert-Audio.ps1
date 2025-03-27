Param (
    [string]$filePath = 'g:\.temp\StaxRipTemp\Ходячие мертвецы - s05e01 - Убежища нет [2014-10-12][1080p][AVC]_temp\',
    [string]$OutputDirectory = 'g:\.temp\StaxRipTemp\Ходячие мертвецы - s05e01 - Убежища нет [2014-10-12][1080p][AVC]_temp\'
)

# Comments
<#
QAAC quality
Ch    q217        q118        q109        q100        q91           q82
---   --------    --------    --------    --------    --------     --------
7.1   999 Kbps    933 Kbps    865 Kbps                731 Kbps    
6.1   875 Kbps    816 Kbps    757 Kbps                639 Kbps    
5.1   750 Kbps    700 Kbps    649 Kbps    432 Kbps    548 Kbps     384 Kbps
2.0   250 Kbps    233 Kbps    216 Kbps                183 Kbps    
1.0   125 Kbps    117 Kbps    108 Kbps                 91 Kbps    
#>


#region Configuration
# General Settings
[datetime]$dtFrom = Get-Date
[string]$OutputCodec = 'AAC' # (AAC, Opus)
[bool]$Normalize = $false
[bool]$deleteFlac = $true
[string]$extraParams = '' #'-itsoffset 5.000' #'-ss 0.000'

# Tools configuration
[string]$ffmpeg = 'X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.exe'
[string]$opusenc = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\opus\opusenc.exe'
[string]$qaac = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\qaac\qaac64.exe'
$requiredTools = @($ffmpeg, $opusenc, $qaac)
foreach ($tool in $requiredTools) {
    if (-not (Test-Path $tool)) {
        throw "Required tool not found: $tool"
    }
}

# Import required functions
$functionPath = 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1'
if (-not (Test-Path $functionPath)) {
    throw "Required function file not found: $functionPath"
}
. $functionPath


# Clean up and validate file path
$filePath = [System.IO.Path]::GetFullPath($filePath.Trim())
if (-not (Test-Path -LiteralPath $filePath)) {
    throw "Invalid file path: $filePath"
}

# Clean up and validate output directory
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory.Trim())
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

# Filters configuration
$filterList = @('.ac3', '.eac3', '.mp3', '.wav', '.thd', '.dtshd')
$extraFilter = '*'

# FLAC Configuration
$cmdLinesFlac = @()

# AAC Configuration
[string]$qaacTVBRQuality = '--tvbr 91'

# Opus configuration depend on extraFilter
[string]$OpusBitrate2ch = "160"
[string]$OpusBitrate6ch = "384"
[string]$OpusBitrate = switch -Wildcard ($extraFilter) {
    '*2Ch*' { $OpusBitrate2ch }
    '*6Ch*' { $OpusBitrate6ch }
    default { "250" }
}
#endregion

function Convert-File {
    param (
        [array]$InputFileList
    )
    
    if (-not $InputFileList -or $InputFileList.Count -eq 0) {
        Write-Host "Нечего конвертировать" -ForegroundColor DarkRed
        Return $null
    }
    $n = 0
    Write-Host ''
    Write-Host '=========================================================='
    foreach ($InputFile in [array]$InputFileList) {
        $n++
        $OutputAAC = ("{0}\{1}.{2}" -f $OutputDirectory, $InputFile.BaseName, "m4a")
        Write-Host ("{0}/{1}  {2}" -f $n, $InputFileList.Count, $InputFile.Name) -ForegroundColor Magenta

        if (Test-Path -LiteralPath $OutputAAC) {
            Write-Host ("Output file exists, skipping..." -f (Get-Item -LiteralPath $OutputAAC).Name) -ForegroundColor DarkMagenta
        }
        else {
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
                
                $exec = Invoke-Process -commandTitle "Volumedetect" -commandPath $ffmpeg -commandArguments ($ArgList -join " ")

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
                    Write-Host ("Gain {0} is too high. Check regex: ""{1}""" -f $GainValue, $RegExp) -BackgroundColor Red
                    Write-Host $exec.stderr -BackgroundColor Red
                    Exit
                }
                Write-Host ("`t{0}{1}dB" -f $SignValue, $GainValue) -ForegroundColor DarkYellow
            }
            else {
                $Gain = ''
                Write-Host 'Пропускаем нормализацию громкости' -ForegroundColor Yellow
            }

            $InputFile.BaseName -match '^.*{(?<track_title>.*)}.*'
            if ($Matches.Count -ge 1) {
                [string]$track_title = $Matches.track_title
                if ($track_title -like '`[*`]') {
                    $track_title = $track_title.Replace('AC3', 'Opus')
                    $track_title = $track_title.Replace('dts', 'Opus')
                    $track_title = $track_title.Replace(' _ ', ' | ')
                }
            }
            <#
                ---------------------------------------------------------- 
                Convert to FLAC
                ---------------------------------------------------------- 
                #>
            $OutputFlac = ("{0}\{1}.{2}" -f $OutputDirectory, $InputFile.BaseName, "flac")
            $ArgList = @(
                #"-ac 2"
                "-y", "-hide_banner"
                "-i ""$InputFile"""
                $extraParams
                $Gain
                """$OutputFlac""")
            #$cmdLinesFlac += ("{0} {1}" -f $ffmpeg, ($ArgList -join " "))
            Write-Host ("{0} {1}" -f $ffmpeg, ($ArgList -join " ")) -ForegroundColor DarkBlue
            Write-Host 'Converting to FLAC...' -ForegroundColor Yellow -NoNewline
            Start-Process -Path $ffmpeg -ArgumentList $ArgList -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
            Write-Host "`tOk" -ForegroundColor DarkYellow



            if ($OutputCodec -eq 'Opus') {
                <#
                ---------------------------------------------------------- 
                Convert to Opus
                ---------------------------------------------------------- 
                #>
                $OutputFile = ("{0}\{1}.{2}" -f $OutputDirectory, $InputFile.BaseName, "opus")
                $ArgList = @( ('--vbr --bitrate {0}' -f $OpusBitrate),
                            ('--title "{0}"' -f $track_title),
                    """$OutputFlac""", 
                    """$OutputFile""")
                Write-Host ("{0} {1}" -f $opusenc, ($ArgList -join " ")) -ForegroundColor Gray
                Write-Host ("Opus --bitrate {0}..." -f $OpusBitrate) -ForegroundColor Yellow -NoNewline
                Start-Process -Path $opusenc -ArgumentList $ArgList -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
                Write-Host "`tOk" -ForegroundColor DarkYellow
            }
            elseif ($OutputCodec -eq 'AAC') {
                <#
                ----------------------------------------------------------
                Encoding to AAC
                ----------------------------------------------------------
                #>
                $OutputFile = ("{0}\{1}.{2}" -f $OutputDirectory, $InputFile.BaseName, "m4a")
                $ArgList = @(
                    $qaacTVBRQuality, 
                    ('--title "{0}"' -f $track_title),
                    """$OutputFlac""",
                    " -o ""$OutputFile"""
                )
                Write-Host ("{0} {1}" -f $qaac, ($ArgList -join " ")) -ForegroundColor DarkBlue
                Write-Host ("QAAC {0}.." -f $Gain) -ForegroundColor Yellow -NoNewline
                Start-Process -Path $qaac -ArgumentList $ArgList -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
                Write-Host "`tOk" -ForegroundColor DarkYellow
            }
            elseif ($OutputCodec -in @('none', '', $null)) {
                Write-Host "Пропускаем конвертацию в Opus/AAC" -ForegroundColor DarkMagenta
            }

            <#
            ----------------------------------------------------------
            Cleanup
            ----------------------------------------------------------
            #>
            Write-Host 'Cleaning up...' -ForegroundColor Yellow -NoNewline
            # if (Test-Path -LiteralPath $OutputGain) {Remove-Item -LiteralPath $OutputGain -Force}
            if ($deleteFlac -and (Test-Path -LiteralPath $OutputFlac)) {
                Remove-Item -LiteralPath $OutputFlac -Force
                if (Test-Path -LiteralPath $OutputFlac) {
                    Write-Host ("`tErr" -f $OutputFlac) -ForegroundColor DarkRed
                }
                else {
                    Write-Host ("`t`tOk" -f $OutputFlac) -ForegroundColor DarkYellow
                }
            }
            else {
                Write-Host ("`tФайл не найден: {0}..." -f $OutputFlac) -NoNewline -ForegroundColor DarkRed
            }
            

            $fileSizeFrom = ("{0:0.00}" -f ($InputFile.Length / 1Mb))
            $fileSizeTo = ("{0:0.00}" -f ((Get-Item -LiteralPath $OutputFile).Length / 1Mb))
            Write-Host ("Size: {0} Mb ==> {1} Mb  ( {2:0.00}% )" -f $fileSizeFrom, $fileSizeTo, ($fileSizeTo / $fileSizeFrom * 100)) -ForegroundColor Green
        }
        Write-Host "=========================================================="
        #Start-Sleep -Seconds 2
    }
}

# -----------------------------------

Clear-Host
$filePath = (Get-Item -LiteralPath $filePath).FullName

$files = Get-ChildItem -LiteralPath $filePath -File -Recurse |
Where-Object {
            ($_.Extension -iin $filterList) -and
            ($_.BaseName -like $extraFilter)
}
Write-Host ("Найдено файлов: {0}" -f $files.Count) -ForegroundColor DarkGreen


$FileList = @()
foreach ($f in $files) {
    if ( Test-Path -LiteralPath $f.FullName ) {
        Write-Host ($f.Name) -ForegroundColor DarkGreen
        $FileList += ( Get-Item -LiteralPath $f )
    }
}
Write-Host 'Pause 10 sec...'
Start-Sleep -Seconds 10

Convert-File -InputFileList $FileList

Write-Host ($cmdLinesFlac) -ForegroundColor DarkBlue

[datetime]$dtTo = Get-Date
Write-Host ("Выполнено за {0}" -f ($dtTo - $dtFrom)) -ForegroundColor Blue

<#
Convert-File -InputFile @(
    (Get-Item -LiteralPath 'x:\temp\test\Resident.Alien.2022.S02E01_{Kubik v Kube}_2ch_DELAY 0ms.ac3'),
    (Get-Item -LiteralPath 'x:\temp\test\Resident.Alien.2022.S02E01_{Kubik v Kube}_6ch_DELAY 0ms.ac3')
    )
#>