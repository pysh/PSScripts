Clear-Host


$encoder = 'rav1e'
$targetQuality = '95.5'
$cqLevel = '30'
$prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
#$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 6" # Stereo ~516kbps



$prmRav1e = @(
    "--speed 6", 
    "--quantizer 100", 
    "--threads 8", 
    "--no-scene-detection", 
    "--tiles 8"
)

$prmX265 = @(
    "--crf 23 --preset slow --output-depth 10", 
    "--amp --subme 5 --max-merge 5 --rc-lookahead 40 --gop-lookahead 34 --ref 5", 
    # "--colorprim bt709 --colormatrix bt709 --transfer bt709 --range limited", 
    "--no-strong-intra-smoothing --constrained-intra"
)

$prmAOM = @(
    "--end-usage=q",
    ("--cq-level={0}" -f $cqLevel), 
    "--cpu-used=4", 
    "--threads=6", 
    "--tile-columns=2", 
    "--tile-rows=1", 
    "--bit-depth=10", 
    "--lag-in-frames=35", # Max number of frames to lag
    "--enable-fwd-kf=1", 
    "--kf-max-dist=250", # Maximum keyframe interval (frames)
    #"--min-q=50", "--max-q=150", 
    "--enable-chroma-deltaq=1", 
    "--quant-b-adapt=1"
    # "--frame-boost=1",          # Enable frame periodic boost (0: off (default), 1: on)
    # "--arnr-strength=4",        # AltRef filter strength (0..6)
    # "--arnr-maxframes=7",       # AltRef max frames (0..15)
)

$execAv1an = "x:\Apps\_VideoEncoding\av1an\av1an.exe"
if (!(Test-Path -Path $execAv1an)) {
    Write-Host ("{0} не найден. Проверьте настройки." -f $execAv1an) -ForegroundColor Red
    Exit
} else {
    Write-Host ("Используется {0}." -f $execAv1an) -ForegroundColor Green
}
Set-Location (Get-Item -Path $execAv1an).DirectoryName


function Convert-VideoFile {
    param (
        $InputFileName, 
        # $OutputFileName="", 
        $encoder = 'rav1e', 
        $targetQuality = '95', 
        $cqLevel = $(switch ($encoder) {
            'rav1e' {'100'}
            'aom'   {'22'}
            'x265'  {'23'}
            Default {''}
        }), 
        $prmVideo='', $prmAudio=''
    )
    $InputFile = (Get-Item -LiteralPath $InputFileName)
    $OutputFileNameSuffix = ("[av1an][{0}_vmaf-Q{1}]" -f $encoder, $targetQuality)
    $OutputFileName = (Join-Path -Path $InputFile.DirectoryName -ChildPath ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix))
    $logFileName = ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix)

    switch ($encoder) {
        "aom" {
            # AOMEnc
            $prmAv1an = @(
                ("-i ""{0}""" -f $InputFileName), 
                ("-o ""{0}""" -f $OutputFileName), 
                "--encoder aom", 
                ("--target-quality {0}" -f $targetQuality), 
                "--probes 6", 
                ("--video-params ""{0}""" -f ($prmAOM -join " ")), 
                "--concat mkvmerge", 
                "--extra-split 0", 
                # "--photon-noise 4", 
                # "--chroma-noise", 
                # "--keep",
                ("--audio-params ""{0}""" -f $prmLibOpus), 
                "--verbose", 
                ("--log-file ""{0}""" -f $logFileName), 
                "--log-level DEBUG"
            )
        }
        "x265" {
            # x265
            $prmAv1an = @(
                ("-i ""{0}""" -f $InputFileName), 
                ("-o ""{0}""" -f $OutputFileName), 
                "--encoder x265", 
                ("--target-quality {0}" -f $targetQuality), 
                #"--min-q=50", "--max-q=150", 
                #"--probes 6", 
                ("--video-params ""{0}""" -f ($prmX265 -join " ")),
                "--concat mkvmerge", 
                "--extra-split 0", 
                #"--photon-noise 10", 
                #"--chroma-noise", 
                # "--keep",
                ("--audio-params ""{0}""" -f $prmAAC), 
                "--verbose", 
                ("--log-file ""{0}""" -f $logFileName), 
                "--log-level DEBUG"
            )
        }
        Default {
            # rav1e
            $prmAv1an = @(
                ("-i ""{0}""" -f $InputFileName), 
                ("-o ""{0}""" -f $OutputFileName), 
                "--encoder rav1e", 
                ("--target-quality {0}" -f $targetQuality), 
                # "--min-q=50", "--max-q=150", 
                # "--probes 6", 
                ("--video-params ""{0}""" -f ($prmRav1e -join " ")),
                "--concat mkvmerge", 
                "--extra-split 0", 
                # "--photon-noise 10", 
                # "--chroma-noise", 
                # "--keep",
                ("--audio-params ""{0}""" -f $prmLibOpus), 
                ("--log-file ""{0}""" -f $logFileName), 
                "--log-level DEBUG",
                "--verbose", 
                "--workers 5"
            )
        }
    }

    Write-Host ("@echo {0}" -f $OutputFileName) -ForegroundColor DarkYellow
    if ((Test-Path -LiteralPath $OutputFileName -PathType Leaf) -eq $true) {
        Write-Host "@REM File exists, skipping..." -ForegroundColor Magenta
        Return
    } else {
        Write-Host ("""{0}""" -f $execAv1an) -ForegroundColor Cyan -NoNewline
        Write-Host " " $prmAv1an -ForegroundColor DarkBlue
        # Start-Process -FilePath $execAv1an -ArgumentList ($prmAv1an -join " ") -Wait -NoNewWindow -WhatIf
    }

} # End Function




$InputFileDirName = 'X:\Видео\Сериалы\Отечественные\Нулевой пациент\Nulevoj.pacient.S01.2022.WEB-DL.2160p\'

$filterList = @(".mkv", ".mp4", ".vpy")
$OutputFileDirName= Join-Path -Path $InputFileDirName -ChildPath 'out_[av1an]'
if (-not (Test-Path $OutputFileDirName)) { New-Item -Path $OutputFileDirName -ItemType Directory }
$InputFileList = Get-ChildItem -LiteralPath $InputFileDirName -File | Where-Object {(($_.Extension -iin $filterList) -and ($_.BaseName -inotlike '*`[av1an`]*'))}
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue

foreach ($InputFileName in $InputFileList) {
    Convert-VideoFile -InputFileName $InputFileName -encoder 'rav1e' -prmVideo $prmRav1e -prmAudio $prmLibOpus -targetQuality '95.5'
    Write-Host "@echo = = = = = = = = = = = = = = = = = = = = = = =`r`n" -ForegroundColor Gray
}