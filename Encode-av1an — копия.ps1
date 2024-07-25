Param (
    [String]$InputFileDirName = ('
    X:\temp\Youtube\Стендап комики\
    ').Trim(), 
    [String]$encoder = 'av1an', 
    [String]$targetQuality = '92',
    [Int32]$prmAudioChannels = 0, 
    [Switch]$bRecurse = $false, 
    [Switch]$CommandLineGenerateOnly = $false
)

. C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Get-ColorSpaceFromVideoFile.ps1
. C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Get-MediaInfoFromFiles.ps1


Clear-Host

<#
    ########################
    Override variable values
    ########################
#>

$CommandLineGenerateOnly = $true
#$encoder = 'rav1e'
#$targetQuality = '92.5'
$cqLevel = '30'



<#  
    ########################
    Definitions
    ########################
#>

enum eEncoder {
    x265
    rav1e
    aom
}

$filterList = @(
    ".m2ts", 
    ".mkv"
    ".mp4", 
    ".vpy"
)




switch ($prmAudioChannels) {
    0 {
        $prmLibOpus = ''
        $prmAAC     = ''
    }
    2 {
        $prmLibOpus = "-c:a:0 libopus -b:a:0 160k -ac 2"
        $prmAAC     = "-c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
    }
    6 {
        $prmLibOpus = "-c:a libopus -b:a 320k -ac 6"
        $prmAAC     = "-c:a aac -q:a 4 -ac 6" # 5.1 ~516kbps
    }
    Default {
        $prmLibOpus = "-c:a libopus -b:a 320k -ac 6"
        $prmAAC     = "-c:a aac -q:a 4 -ac 6" # 5.1 ~516kbps
    }
}

# $prmLibOpus = '-c:a:1 libopus -b:a:1 320k -ac 6 -c:a:2 libopus -b:a:2 160k -ac 2'
# # $prmLibOpus = "-c:a:0 libopus -b:a:0 136k -ac 2  -c:a:1 libopus -b:a:1 320k -ac 6  -c:a:2 libopus -b:a:2 320k -ac 6"

# $prmLibOpus = '-c:a:0 copy -c:a:1 libopus -b:a:1 160k'

<# Black List
$prmLibOpus = (@(
    "-c:a:0 libopus -b:a:0 320k -ac:0 6 -disposition:0 0 -metadata:s:a:0 language=en -metadata:s:a:0 title='[Original | Opus 5.1 Audio]'", 
    "-c:a:1 libopus -b:a:1 320k -ac:1 6 -disposition:1 default -metadata:s:a:1 language=ru -metadata:s:a:1 title='[Lostfilm | Opus 5.1 Audio]'", 
    "-c:a:2 libopus -b:a:2 160k -ac:2 2 -disposition:2 0 -metadata:s:a:2 language=ru -metadata:s:a:2 title='[SET | Opus 2.0 Audio]'"
) -join ' ')
#>

<#
# Fargo
$prmLibOpus = (@(
    "-c:a:0 libopus -af:0 aformat=channel_layouts='7.1|5.1|stereo' -b:a:0 320k -ac:0 6 -disposition:0 0 -metadata:s:a:0 language=ru -metadata:s:a:0 title='[LostFilm | Opus 5.1 Audio]'", 
    "-c:a:1 libopus -af:1 aformat=channel_layouts='7.1|5.1|stereo' -b:a:1 320k -ac:1 6 -disposition:1 default -metadata:s:a:1 language=ru -metadata:s:a:1 title='[Кубик в Кубе | Opus 5.1 Audio]'", 
    "-c:a:2 libopus -af:2 aformat=channel_layouts='7.1|5.1|stereo' -b:a:2 320k -ac:2 6 -disposition:2 0 -metadata:s:a:2 language=ru -metadata:s:a:2 title='[NewStudio | Opus 5.1 Audio]'", 
    "-c:a:3 libopus -af:3 aformat=channel_layouts='7.1|5.1|stereo' -b:a:3 320k -ac:3 6 -disposition:3 0 -metadata:s:a:3 language=ru -metadata:s:a:3 title='[Ideafilm | Opus 5.1 Audio]'", 
    "-c:a:4 libopus -b:a:4 160k -ac:4 2 -disposition:4 0 -metadata:s:a:4 language=ru -metadata:s:a:4 title='[Первый канал | Opus 2.0 Audio]'",
    "-c:a:5 libopus -af:5 aformat=channel_layouts='7.1|5.1|stereo' -b:a:5 320k -ac:5 6 -disposition:5 0 -metadata:s:a:5 language=en -metadata:s:a:5 title='[Original | Opus 5.1 Audio]'", 
    "-c:a:6 libopus -b:a:6 160k -ac:6 2 -disposition:6 0 -metadata:s:a:6 language=en -metadata:s:a:6 title='[Commentary | Opus 2.0 Audio]'"
) -join ' ')
#>


<# $prmLibOpus = "-c:a libopus -b:a 136k -ac 2"
#$prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
#$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 6" # Stereo ~516kbps #>



$prmRav1e = @(
    '--speed 6', 
    '--quantizer 93', 
    '--threads 8', 
    '--tiles 4', 
    '--level 5.0',
    '--no-scene-detection'
)

$prmX265 = @(
    "--crf 23 --preset slow --output-depth 10", 
    "--amp --subme 5 --max-merge 5 --rc-lookahead 40 --gop-lookahead 34 --ref 5", 
    # "--colorprim bt709 --colormatrix bt709 --transfer bt709 --range limited", 
    "--no-strong-intra-smoothing --constrained-intra"
)

$prmAOM = @(
    # aomenc-av1 with grain synth and higher efficiency (no anime)
    # https://www.reddit.com/r/AV1/comments/n4si96/encoder_tuning_part_3_av1_grain_synthesis_how_it/
    '--bit-depth=10 --end-usage=q --cq-level=21 --cpu-used=4 --arnr-strength=4',
    '--tile-columns=1 --tile-rows=0 --lag-in-frames=35 --enable-fwd-kf=1 --kf-max-dist=240', 
    '--max-partition-size=64 --enable-qm=1 --enable-chroma-deltaq=1 --quant-b-adapt=1 --enable-dnl-denoising=0 --denoise-noise-level=8'
)

$execAv1an = "X:\Apps\_VideoEncoding\av1an\av1an.exe"
if (!(Test-Path -Path $execAv1an)) {
    Write-Host ("{0} не найден. Проверьте настройки." -f $execAv1an) -ForegroundColor Red
    Exit
}
else {
    Write-Host ("Используется {0}." -f $execAv1an) -ForegroundColor Green
}
Set-Location (Get-Item -Path $execAv1an).DirectoryName




<#  
    ########################
    Functions
    ########################
#>

function Convert-VideoFile {
    param (
        $InputFileName, 
        $OutputFileDirName = $InputFile.DirectoryName, 
        $encoder = [eEncoder]::rav1e, 
        $targetQuality = '92', 
        $cqLevel = $(switch ($encoder) {
                rav1e { '100' }
                aom { '22' }
                x265 { '23' }
                Default { '' }
            })
        # $prmVideo='', $prmAudio=''
    )
    $mInfo = Get-MI -file $InputFileName
    Clear-Variable "color_*"
    $color_params = Get-ColorSpaceFromVideoFile -inFileName $InputFileName
    # $color_params | Format-List
    $color_range = $color_params.color_range; 
    $color_space = $color_params.color_space; 
    $color_transfer = $color_params.color_transfer; 
    $color_primaries = $color_params.color_primaries; 
    #$color_matrix = $color_params.color_matrix 
    $color_matrix = $(switch ($color_space) {
            'bt2020nc' { 'BT2020NCL' }
            Default { $color_space }
        })
    [System.Array]$strScript = @()
    $prmColors = @()
    # RAV1E Color configuration
    # "--primaries BT2020 --transfer BT2020_10Bit --matrix BT2020NCL", 
    # "--primaries BT709  --transfer BT709        --matrix BT709      --range limited", 
    # if ($color_space -inotin @('','Unknown')) { $prmRav1e += ('--range {0}' -f $color_space) }
    if ($color_range -eq 'tv') { $prmColors += '--range limited' } else { $prmColors += ('--range limited') }
    if ($color_primaries -inotin @('', $null, 'Unknown')) { $prmColors += ('--primaries {0}' -f $color_primaries) } else { $prmColors += ('--primaries BT709') }
    if ($color_transfer -inotin @('', $null, 'Unknown')) { $prmColors += ('--transfer {0}' -f $color_transfer) } else { $prmColors += ('--transfer BT709') }
    if ($color_matrix -inotin @('', $null, 'Unknown')) { $prmColors += ('--matrix {0}' -f $color_matrix) } else { $prmColors += ('--matrix BT709') }
    # $prmColors += '--mastering-display G(8500,39850)B(6550,2300)R(35400,14600)WP(15635,16450)L(10000000,1)'
    # $prmColors += '--content-light 501,235'

    #if ($color_space -inotin @('', $null, 'Unknown')) { $prmColors += ('--matrix {0}' -f $color_space) }
    #if ($color_matrix -inotin @('', $null, 'Unknown')) { $prmColors += ('--matrix {0}' -f $color_matrix) }
    # $prmColors = $prmColors.Trim()

    if (-not (Test-Path -LiteralPath $OutputFileDirName)) { New-Item -Path $OutputFileDirName -ItemType Directory | Out-Null }
    $InputFile = (Get-Item -LiteralPath $InputFileName)
    $OutputFileNameSuffix = ("[av1an][{0}_vmaf-Q{1}]" -f $encoder, $targetQuality)
    $OutputFileName = (Join-Path -Path $OutputFileDirName -ChildPath ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix))
    $logFileName = ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix)

    # if ($mInfo.Height -gt 1100) {
    #     $vmafParam = '--vmaf-path "vmaf_4k_v0.6.1.json" --vmaf-res iw:ih' 
    # }
    # else { $vmafParam = '' }

    # $vmafParam = switch ($mInfo.Height) {
    #     ({ $_ -gt 1100 }) { '--vmaf-path "vmaf_4k_v0.6.1.json" --vmaf-res iw:ih' }
    #     ({ $_ -le 10 }) { '' }
    # }


    $prmCommon = @(
        ("-i ""{0}""" -f $InputFileName), 
        ("-o ""{0}""" -f $OutputFileName), 
        # '--ffmpeg "-vf crop=3840:1608:0:276"', 
        # '--ffmpeg "-vf crop=3840:1600:0:280"', '--vmaf-filter "crop=3840:1600:0:280"', '--vmaf-res "3840x1600"'
        # ('--log-file ".\logs\[{0:yyyyMMdd_HHmmss}]_{1}"' -f (Get-Date), $logFileName), "--log-level DEBUG",
        ('--log-file (".\logs\[{0}]_{1}" -f (Get-Date))' -f '{0:yyyyMMdd_HHmmss}', $logFileName), 
        "--chunk-method lsmash", 
        "--concat mkvmerge", 
        # "--extra-split 240", 
        # "--keep", 
        # "--photon-noise 4",
        # "--chroma-noise", 
        ("--target-quality {0}" -f $targetQuality)
        if ($mInfo.Height -gt 1100) {
            '--vmaf-path "vmaf_4k_v0.6.1.json"',
            '--vmaf-res iw:ih'
        }
        if ($encoder -eq $([eEncoder]::x265)) {
            '--workers 2'
        } else {
            '--workers 5'
        }
        '--resume'
        '--verbose'
    )

    switch ($encoder) {
        aom {
            # AOMEnc
            $prmAv1an = $prmCommon + @(
                "--encoder aom", 
                ("--video-params ""{0}""" -f ($prmAOM -join " ")), 
                ("--audio-params ""{0}""" -f $prmLibOpus)
            )
        }
        x265 {
            # x265
            $prmAv1an = $prmCommon + @(
                "--encoder x265", 
                ("--video-params ""{0}""" -f ($prmX265 -join " ")),
                ("--audio-params ""{0}""" -f $prmAAC)
            )
        }
        Default {
            # rav1e
            # $prmLibOpus = '-c:a:0 libopus -b:a:0 280k -c:a:1 libopus -b:a:1 280k -c:a:2 libopus -b:a:2 144k -c:a:3 libopus -b:a:3 144k'
            # $prmLibOpus = '-c:a:0 libopus -b:a:0 320k -ac:0 6 -filter:0 aformat=channel_layouts=5.1 -c:a:1 libopus -b:a:1 320k -ac:1 6 -filter:1 aformat=channel_layouts=5.1 -c:a:2 libopus -b:a:2 160k -c:a:3 libopus -b:a:3 160k'
            # $prmLibOpus = '-c:a:0 copy -c:a:1 libopus -b:a:1 160k'
            $prmAv1an = @(
                "--encoder rav1e", 
                ('--video-params "{0}"' -f (($prmRav1e.Trim() + $prmColors.Trim()) -join " ")), 
                ("--audio-params ""{0}""" -f $prmLibOpus), 
                "--min-q=60 --max-q=150"
            ) + $prmCommon
        }
    }

    # Write-Host ("@echo {0}" -f $OutputFileName) -ForegroundColor DarkYellow

    if ((Test-Path -LiteralPath $OutputFileName -PathType Leaf) -eq $true) {
        Write-Host "# File exists, skipping..." -ForegroundColor Magenta
        Return
    }
    else {
        # Write-Host 'Write-Host "Waiting 60 seconds..." -Foregroundcolor DarkYellow; Start-Sleep -Seconds 60'
        $strScript += @(
            '', 
            ('$fn=''{0}'';' -f $InputFileName),
            'Write-Host ("`r`n[{0}] {1}" -f (Get-Date), $fn) -ForegroundColor DarkMagenta;',
            ('Set-Location -LiteralPath ''{0}\'';' -f (Get-Item $execAv1an).Directory),
            ('. .\{0} {1}' -f (Get-Item $execAv1an).Name, ($prmAv1an -join ' '))
        )
        # $strScript += ('Set-Location -LiteralPath "{0}\";' -f (Get-Item $execAv1an).Directory)
        # $strScript += ('. .\{0} {1}' -f (Get-Item $execAv1an).Name, ($prmAv1an -join ' '))
        # Write-Host $strScript -ForegroundColor DarkBlue
        # Write-Host ('Set-Location -LiteralPath "{0}\";' -f (Get-Item $execAv1an).Directory) -ForegroundColor Cyan -NoNewline
        # Write-Host (' . .\{0} {1}' -f (Get-Item $execAv1an).Name, ($prmAv1an -join ' ')) -ForegroundColor DarkBlue
        if (-not $CommandLineGenerateOnly) {
            Start-Process -FilePath $execAv1an -ArgumentList ($prmAv1an -join ' ') -Wait -NoNewWindow
        }
    }
    Return $strScript
} # End Function






$OutputDirName = Join-Path -Path $InputFileDirName -ChildPath 'out_[av1an]'
if (-not (Test-Path -LiteralPath $OutputDirName)) { New-Item -Path $OutputDirName -ItemType Directory | Out-Null }
$InputFileList = Get-ChildItem -LiteralPath $InputFileDirName -File -Recurse:$bRecurse | Where-Object { (($_.Extension -iin $filterList) -and ($_.BaseName -inotlike '*`[av1an`]*')) }
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue



$strScript1 = @()
foreach ($InputFileName in $InputFileList) {
    <#
    $s = @(
        ("`r`n`$fn = '{0}'" -f $InputFileName),
        'Write-Host ("`r`n[{0}] {1}" -f (Get-Date), $fn) -ForegroundColor DarkMagenta'
    )
    Write-Host ($s -join "`r`n")
    #>

    $strScript1 += Convert-VideoFile -InputFileName $InputFileName -OutputFileDirName $OutputDirName -encoder $encoder -targetQuality $targetQuality # -prmVideo $prmX265 -prmAudio $prmAAC

}

Write-Host ($strScript1 -join "`r`n") -ForegroundColor Green

$striptFileName = (Join-Path -Path $InputFileDirName -ChildPath 'encode++.ps1')
$strScript1 | Out-File $striptFileName -Encoding utf8 -Force
