# Get-Item -LiteralPath ".\05.mkv" -Stream '.gltth'

Clear-Host
$ffmpeg = 'X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.exe'
$InputPath = ('
    W:\.temp\Youtube\[2023-04-18] Ламповый стендап-концерт от комика-миллениала Антона Овчарова\
').Trim()

$InputFilesMask = @("*.webm", "*.mp4")
$OutputPath = '' #'w:\.temp\Youtube\Разгоны_out'
Write-Host "Scanning the directory for files..."
$InputFileList = (Get-ChildItem -LiteralPath $InputPath -File -Include $InputFilesMask -Recurse)
Write-Host ("Found files: {0}" -f $InputFileList.Count) -ForegroundColor Yellow
$n = 0
foreach ($InputMP4 in $InputFileList) {
    $n++
    if ($OutputPath -eq '') {
        #$OutputMKV      = ("{0}\{1}.{2}" -f $InputMP4.DirectoryName, $InputMP4.BaseName, "mkv")
        #$OutputMKV      = ("{0}\{1}.{2}" -f $InputMP4.DirectoryName, $InputMP4.Directory.Name, "mkv")
        $OutputMKV = ("{0}\{1}_[{3}].{2}" -f $InputMP4.DirectoryName, $InputMP4.Directory.Name, "mkv", $InputMP4.Extension.Remove(0, 1))
    }
    else {
        #$OutputMKV = ("{0}\{1}.{2}" -f $OutputPath, $InputMP4.BaseName, "mkv")
        $OutputMKV = ("{0}\{1}_[{3}].{2}" -f $OutputPath, $InputMP4.Directory.Name, "mkv", $InputMP4.Extension.Remove(0, 1))
    }
    
    if (Test-Path -LiteralPath $OutputMKV -PathType Leaf) {
        Write-Host ("File {0} exists. Skipping." -f $OutputMKV) -ForegroundColor Magenta
    }
    else {
        Write-Host ("{0} / {1}" -f $n, $InputFileList.Count) -ForegroundColor Cyan
        #$InputCover = ("{0}\{1}" -f $InputMP4.DirectoryName, "cover.jpg")
        $InputCover = Get-ChildItem -LiteralPath $InputMP4.DirectoryName -File -Filter '*.jpg'
        $InputDescr = Get-ChildItem -LiteralPath $InputMP4.DirectoryName -File -Filter '*description*.txt'
        $ArgList = ("-hide_banner", "-i ""$InputMP4""", 
            '-map 0:0 -map 0:1 -map_metadata -1:s:0 -map_metadata 0:g:0 -c copy -metadata:s:a:0 language=ru -metadata:s:v:0 language=rus', 
            "-attach ""$InputCover"" -metadata:s:t:0 mimetype=image/jpeg -metadata:s:t:0 filename=cover.jpg", 
            "-attach ""$InputDescr"" -metadata:s:t:1 mimetype=text/plain -metadata:s:t:1 filename=description.txt", 
            "-y", 
            """$OutputMKV""")
        #Write-Host "Remuxing file: " -NoNewLine
        Write-Host ("{0}\" -f $OutputPath) -NoNewLine -ForegroundColor Blue
        Write-Host $InputMP4.Name -ForegroundColor DarkBlue
        Write-Host $ArgList -ForegroundColor DarkYellow
        Start-Process $ffmpeg -ArgumentList $ArgList -Wait -NoNewWindow # -WindowStyle Normal -Wait #| Out-Null
        Write-Host $OutputMKV -ForegroundColor Green
        Write-Host "-------------------------------------------------------------------" #`r`n"
        #Start-Sleep -Seconds 2
    }
}
#Write-Host $ArgList -ForegroundColor Green
<#
"C:\Program Files\MKVToolNix\mkvmerge.exe" 
--ui-language ru 
--priority lower 
--output ^"V:\ТВ передачи\Царьвидео и Кирилл Сиэтлов\Сковорода\[2019-05-27] Стахович vs Шамутило _ СКОВОБАТТЛ {v=2MmUYSPdtpg}\Стахович vs Шамутило - СКОВОБАТТЛ+.mkv^" 
--no-track-tags 
--language 0:ru 
--display-dimensions 0:1920x1080 
--color-matrix-coefficients 0:1 
--chroma-siting 0:1,2 
--color-range 0:1 
--color-transfer-characteristics 0:1 
--color-primaries 0:1 
--language 1:ru ^"^(^" ^"V:\ТВ передачи\Царьвидео и Кирилл Сиэтлов\Сковорода\[2019-05-27] Стахович vs Шамутило _ СКОВОБАТТЛ {v=2MmUYSPdtpg}\Стахович vs Шамутило _ СКОВОБАТТЛ ^(1080p_25fps_H264-128kbit_AAC^).mkv^" ^"^)^" 
--title ^"Стахович vs Шамутило ^| СКОВОБАТТЛ^" 
--track-order 0:0,0:1
#>
