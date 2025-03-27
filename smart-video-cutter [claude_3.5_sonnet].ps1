param(
    # [Parameter(Mandatory=$true)]
    [string]$InputFile = 'y:\.temp\YT_y\[20241228] Звёзды. Камызяки. Новогодний концерт.mkv',
    # [Parameter(Mandatory=$true)]
    [double]$Start = 20,
    # [Parameter(Mandatory=$true)]
    [double]$End = 3345.296
)

# Validate input file
if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Error "Input file not found: $InputFile"
    exit 1
}

# Get video properties
$ffmpegOutput = . ffmpeg -hide_banner -i $InputFile -f null -c copy -map 0:v:0 - 2>&1
$size = (Select-String 'video:(?<bitrate>\d*)KiB' -InputObject $ffmpegOutput).Matches.Groups[1].Value
$codec = ffprobe -hide_banner -loglevel error -select_streams v:0 -show_entries stream=codec_name -of default=nk=1:nw=1 $InputFile
$duration = ffprobe -hide_banner -loglevel error -select_streams v:0 -show_entries format=duration -of default=nk=1:nw=1 $InputFile
$bitrate = [math]::Round(($size / $duration) * 8.192)

Write-Host "Finding keyframes in $InputFile"
$keyFramesFile = "${InputFile}_keyframes.json"

if (-not (Test-Path -LiteralPath $keyFramesFile)) {
    $keyFramesArgs = @(
        '-hide_banner'
        '-loglevel error'
        '-select_streams v:0'
        '-show_frames'
        # '-show_entries frame=pkt_dts_time,frame_number,pict_type'
        '-print_format json'
        ('-i "{0}"' -f $InputFile)
        ('-o "{0}"' -f $keyFramesFile)
    )
    Start-Process -FilePath 'ffprobe.exe' -ArgumentList $keyFramesArgs -NoNewWindow -Wait
    if (-not (Test-Path -LiteralPath $keyFramesFile)) {
        Write-Error "Error processing video file: $InputFile"
        exit 1
    }
}

$keyframes = (Get-Content -Raw -LiteralPath $keyFramesFile | ConvertFrom-Json).frames | 
    Where-Object pict_type -eq "I" | 
    ForEach-Object { [double]$_.pkt_dts_time }

if ($keyframes -contains $Start) {
    Write-Host "$Start is a keyframe, doing a keyframe cut"
    $outputFile = "$InputFile-cut.mp4"
    ffmpeg -hide_banner -loglevel error -ss $Start -i $InputFile -t $End `
        -c:v copy -map '0:0' -map '0:1' -map_metadata 0 -movflags use_metadata_tags `
        -ignore_unknown -f mp4 -y $outputFile
    exit 0
}

Write-Host "$Start is not a keyframe"
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# Find next keyframe after start position
$nextKeyFrame = $keyframes | Where-Object { $_ -gt $Start } | Select-Object -First 1
$endPos = $nextKeyFrame - 0.000001

Write-Host "Re-encoding from $Start until the last frame before a new keyframe ($endPos)"
$output0 = Join-Path $tempDir "output0.mp4"
ffmpeg -hide_banner -loglevel error -i $InputFile -ss $Start -to $endPos `
    -c:a copy -map '0:0' -map '0:1' -map_metadata 0 -movflags use_metadata_tags `
    -ignore_unknown -c:v $codec -b:v "$($bitrate)k" -f mp4 -y $output0

Write-Host "Extracting video from the next keyframe ($nextKeyFrame) to the end $End"
$output1 = Join-Path $tempDir "output1.mp4"
ffmpeg -hide_banner -loglevel error -ss $nextKeyFrame -i $InputFile -to $End `
    -c:v copy -map '0:0' -map '0:1' -map_metadata 0 -movflags use_metadata_tags `
    -ignore_unknown -f mp4 -y $output1

$fileList = Join-Path $tempDir "filelist.txt"
@"
file '$output0'
file '$output1'
"@ | Set-Content $fileList -Encoding UTF8

Write-Host "Merging files..."
$outputFile = "$InputFile-cut.mp4"
ffmpeg -hide_banner -loglevel error -f concat -i $fileList -c copy $outputFile

# Cleanup
Remove-Item -Recurse -Force $tempDir
Write-Host "Done! Output saved as: $outputFile"