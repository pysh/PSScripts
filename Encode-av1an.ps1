Param (
    [String]$InputFileDirName = 'w:\Видео\Сериалы\Отечественные\И снова здравствуйте\И.снова.здравствуйте!.2021.WEB-DL.2160p\', 
    [String]$encoder = 'aom', 
    [String]$targetQuality = '95.3',
    [System.Diagnostics.Switch]$bRecurse = $true
)


Clear-Host


#$encoder = 'rav1e'
#$targetQuality = '95.3'
$cqLevel = '30'
$prmAudioChannels = 2
$filterList = @(".mkv", ".mp4", ".vpy")

switch ($prmAudioChannels) {
    2 {
        $prmLibOpus = "-c:a libopus -b:a 136k -ac 2"
        $prmAAC     = "-c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
    }
    6 {
        $prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
        $prmAAC     = "-c:a aac -q:a 4 -ac 6" # Stereo ~516kbps
    }
    Default {
        $prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
        $prmAAC     = "-c:a aac -q:a 4 -ac 6" # Stereo ~516kbps
    }
}


<# $prmLibOpus = "-c:a libopus -b:a 136k -ac 2"
#$prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
#$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 6" # Stereo ~516kbps #>



$prmRav1e = @(
    "--speed 6", 
    "--quantizer 100", 
    # "--threads 8", 
    "--tiles 8", 
    "--no-scene-detection"
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
    "--tile-columns=4", 
    "--tile-rows=2", 
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
        $targetQuality = '95.5', 
        $cqLevel = $(switch ($encoder) {
            'rav1e' {'100'}
            'aom'   {'22'}
            'x265'  {'23'}
            Default {''}
        }) 
        # $prmVideo='', $prmAudio=''
    )
    $InputFile = (Get-Item -LiteralPath $InputFileName)
    $OutputFileNameSuffix = ("[av1an][{0}_vmaf-Q{1}]" -f $encoder, $targetQuality)
    $OutputFileName = (Join-Path -Path $InputFile.DirectoryName -ChildPath ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix))
    $logFileName = ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix)

    $prmCommon = @(
        ("-i ""{0}""" -f $InputFileName), 
        ("-o ""{0}""" -f $OutputFileName), 
        ("--log-file ""{0}""" -f $logFileName), "--log-level DEBUG",
        ("--target-quality {0}" -f $targetQuality), 
        "--chunk-method lsmash",         
        "--concat mkvmerge", 
        # "--extra-split 240", 
        # "--keep", 
        # "--photon-noise 4", 
        # "--chroma-noise", 
        "--probes 6", 
        # "--workers 6", 
        # "--passes 1", 
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
                ("--video-params ""{0}""" -f ($prmRav1e -join " ")), 
                ("--audio-params ""{0}""" -f $prmLibOpus)
                # "--min-q=50", "--max-q=150"
            ) + $prmCommon
        }
    }

    Write-Host ("@echo {0}" -f $OutputFileName) -ForegroundColor DarkYellow
    if ((Test-Path -LiteralPath $OutputFileName -PathType Leaf) -eq $true) {
        Write-Host "@REM File exists, skipping..." -ForegroundColor Magenta
        Return
    } else {
        Write-Host ("""{0}""" -f $execAv1an) -ForegroundColor Cyan -NoNewline
        Write-Host " " $prmAv1an -ForegroundColor DarkBlue
        # Start-Process -FilePath $execAv1an -ArgumentList ($prmAv1an -join " ") -Wait -NoNewWindow
    }

} # End Function






$OutputFileDirName= Join-Path -Path $InputFileDirName -ChildPath 'out_[av1an]'
if (-not (Test-Path -LiteralPath $OutputFileDirName)) { New-Item -Path $OutputFileDirName -ItemType Directory | Out-Null }
$InputFileList = Get-ChildItem -LiteralPath $InputFileDirName -File -Recurse $bRecurse | Where-Object {(($_.Extension -iin $filterList) -and ($_.BaseName -inotlike '*`[av1an`]*'))}
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue

foreach ($InputFileName in $InputFileList) {
    Convert-VideoFile -InputFileName $InputFileName -encoder $encoder -targetQuality $targetQuality # -prmVideo $prmX265 -prmAudio $prmAAC
    Write-Host "@echo = = = = = = = = = = = = = = = = = = = = = = =`r`n" -ForegroundColor Gray
}