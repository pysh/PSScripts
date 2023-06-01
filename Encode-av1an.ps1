Param (
    [String]$InputFileDirName = ('
    v:\Сериалы\Отечественные\ЮНОСТЬ\Yunost.S01.WEB-DL.1080p.MrMittens\
    ').Trim(), 
    [String]$encoder = 'rav1e', 
    [String]$targetQuality = '95',
    [Int32]$prmAudioChannels = 2, 
    [Switch]$bRecurse = $false, 
    [Switch]$CommandLineGenerateOnly = $false
)

. C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Get-ColorSpaceFromVideoFile.ps1


Clear-Host

$CommandLineGenerateOnly = $true
#$encoder = 'rav1e'
#$targetQuality = '95.3'
$cqLevel = '30'

$filterList = @(
    ".mkv", 
    ".mp4", 
    ".vpy"
)

switch ($prmAudioChannels) {
    0 {
        $prmLibOpus = ''
        $prmAAC = ''
    }
    2 {
        $prmLibOpus = "-c:a libopus -b:a 136k -ac 2"
        $prmAAC = "-c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
    }
    6 {
        $prmLibOpus = "-c:a libopus -b:a 320k -ac 6"
        $prmAAC = "-c:a aac -q:a 4 -ac 6" # Stereo ~516kbps
    }
    Default {
        $prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
        $prmAAC = "-c:a aac -q:a 4 -ac 6" # Stereo ~516kbps
    }
}

# $prmLibOpus = "-c:a:0 libopus -b:a:0 136k -ac 2  -c:a:1 libopus -b:a:1 320k -ac 6  -c:a:2 libopus -b:a:2 320k -ac 6"

<# $prmLibOpus = "-c:a libopus -b:a 136k -ac 2"
#$prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
#$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 6" # Stereo ~516kbps #>



$prmRav1e = @(
    "--speed 5", 
    "--quantizer 100", 
    "--threads 8", 
    "--tiles 8", 
    # "--primaries BT2020 --transfer BT2020_10Bit --matrix BT2020NCL", 
    # "--primaries BT709 --transfer BT709 --matrix BT709 --range limited", 
    "--no-scene-detection"
)

$prmX265 = @(
    "--crf 23 --preset slow --output-depth 10", 
    "--amp --subme 5 --max-merge 5 --rc-lookahead 40 --gop-lookahead 34 --ref 5", 
    # "--colorprim bt709 --colormatrix bt709 --transfer bt709 --range limited", 
    "--no-strong-intra-smoothing --constrained-intra"
)

$prmAOM = @(
    <# 
    "--end-usage=q",
    ("--cq-level={0}" -f $cqLevel), 
    "--cpu-used=4", 
    "--threads=6", 
    "--tile-columns=4", 
    "--tile-rows=2", 
    "--bit-depth=10", 
    "--lag-in-frames=35", # Max number of frames to lag
    "--enable-fwd-kf=1", 
    "--kf-max-dist=250", # Maximum keyframe interval (frames)
    "--enable-chroma-deltaq=1", 
    "--quant-b-adapt=1"
    # "--frame-boost=1",          # Enable frame periodic boost (0: off (default), 1: on)
    # "--arnr-strength=4",        # AltRef filter strength (0..6)
    # "--arnr-maxframes=7",       # AltRef max frames (0..15)
#>
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








function Convert-VideoFile {
    param (
        $InputFileName, 
        $OutputFileDirName = $InputFile.DirectoryName, 
        $encoder = 'rav1e', 
        $targetQuality = '95.5', 
        $cqLevel = $(switch ($encoder) {
                'rav1e' { '100' }
                'aom' { '22' }
                'x265' { '23' }
                Default { '' }
            }) 
        # $prmVideo='', $prmAudio=''
    )

    Clear-Variable "color_*"
    $color_params    = Get-ColorSpaceFromVideoFile -inFileName $InputFileName
    $color_range     = $color_params.color_range; 
    $color_space     = $color_params.color_space; 
    $color_transfer  = $color_params.color_transfer; 
    $color_primaries = $color_params.color_primaries; 
    $color_matrix    = $color_params.color_matrix 

    # RAV1E Color configuration
    # "--primaries BT2020 --transfer BT2020_10Bit --matrix BT2020NCL", 
    # "--primaries BT709  --transfer BT709        --matrix BT709      --range limited", 
    # if ($color_space -inotin @('','Unknown')) { $prmRav1e += ('--range {0}' -f $color_space) }
    if ($color_range -eq 'tv') { $prmRav1e += '--range limited' }
    if ($color_transfer -inotin @('', 'Unknown')) { $prmRav1e += ('--transfer {0}' -f $color_transfer) }
    if ($color_primaries -inotin @('', 'Unknown')) { $prmRav1e += ('--primaries {0}' -f $color_primaries) }
    if ($color_space -inotin @('', $null, 'Unknown')) { $prmRav1e += ('--matrix {0}' -f $color_space) }
    #if ($color_matrix -inotin @('', $null, 'Unknown')) { $prmRav1e += ('--matrix {0}' -f $color_matrix) }
    $prmRav1e = $prmRav1e.Trim()

    if (-not (Test-Path -LiteralPath $OutputFileDirName)) { New-Item -Path $OutputFileDirName -ItemType Directory | Out-Null }
    $InputFile = (Get-Item -LiteralPath $InputFileName)
    $OutputFileNameSuffix = ("[av1an][{0}_vmaf-Q{1}]" -f $encoder, $targetQuality)
    $OutputFileName = (Join-Path -Path $OutputFileDirName -ChildPath ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix))
    $logFileName = ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix)

    $prmCommon = @(
        ("-i ""{0}""" -f $InputFileName), 
        ("-o ""{0}""" -f $OutputFileName), 
        # '--ffmpeg "-vf crop=3840:1608:0:276"', 
        # '--ffmpeg "-vf crop=3840:1600:0:280"', '--vmaf-filter "crop=3840:1600:0:280"', '--vmaf-res "3840x1600"'
        ("--log-file "".\logs\[{0:yyyyMMdd_HHmmss}]_{1}""" -f (Get-Date), $logFileName), "--log-level DEBUG",
        "--chunk-method lsmash", 
        "--concat mkvmerge", 
        # "--extra-split 240", 
        # "--keep", 
        # "--photon-noise 4",
        # "--chroma-noise", 
        ("--target-quality {0}" -f $targetQuality), 
        # "--probes 6", 
        '--vmaf-path "vmaf_4k_v0.6.1.json"'
        "--workers 6", 
        # "--passes 2", 
        "--resume", 
        "--verbose"
    )

    switch ($encoder) {
        "aom" {
            # AOMEnc
            $prmAv1an = $prmCommon + @(
                "--encoder aom", 
                ("--video-params ""{0}""" -f ($prmAOM -join " ")), 
                ("--audio-params ""{0}""" -f $prmLibOpus)
            )
        }
        "x265" {
            # x265
            $prmAv1an = $prmCommon + @(
                "--encoder x265", 
                ("--video-params ""{0}""" -f ($prmX265 -join " ")),
                ("--audio-params ""{0}""" -f $prmAAC)
            )
        }
        Default {
            # rav1e
            $prmAv1an = @(
                "--encoder rav1e", 
                ("--video-params ""{0}""" -f ($prmRav1e -join " ").Trim()), 
                ("--audio-params ""{0}""" -f $prmLibOpus)
                "--min-q=60", "--max-q=180"
            ) + $prmCommon
        }
    }

    Write-Host ("@echo {0}" -f $OutputFileName) -ForegroundColor DarkYellow
    if ((Test-Path -LiteralPath $OutputFileName -PathType Leaf) -eq $true) {
        Write-Host "@REM File exists, skipping..." -ForegroundColor Magenta
        Return
    }
    else {
        Write-Host ("""{0}""" -f $execAv1an) -ForegroundColor Cyan -NoNewline
        Write-Host " " $prmAv1an -ForegroundColor DarkBlue
        if (-not $CommandLineGenerateOnly) {
            Start-Process -FilePath $execAv1an -ArgumentList ($prmAv1an -join " ") -Wait -NoNewWindow
        }
    }

} # End Function






$OutputDirName = Join-Path -Path $InputFileDirName -ChildPath 'out_[av1an]'
if (-not (Test-Path -LiteralPath $OutputDirName)) { New-Item -Path $OutputDirName -ItemType Directory | Out-Null }
$InputFileList = Get-ChildItem -LiteralPath $InputFileDirName -File -Recurse:$bRecurse | Where-Object { (($_.Extension -iin $filterList) -and ($_.BaseName -inotlike '*`[av1an`]*')) }
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue

foreach ($InputFileName in $InputFileList) {
    Convert-VideoFile -InputFileName $InputFileName -OutputFileDirName $OutputDirName -encoder $encoder -targetQuality $targetQuality # -prmVideo $prmX265 -prmAudio $prmAAC
    Write-Host "@echo = = = = = = = = = = = = = = = = = = = = = = =`r`n" -ForegroundColor Gray
}