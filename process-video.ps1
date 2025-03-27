param(
    # [Parameter(Mandatory=$true)]
    [string]$InputVideo = 'y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\01\The.Walking.Dead.S01E01.mkv',
    # [Parameter(Mandatory=$true)]
    [string]$OutputVideo = 'y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\01\The.Walking.Dead.S01E01_test_out.mkv',
    [string]$tmpDir = 'y:\.temp',
    [int]$VmafTarget = 95,
    [int]$AudioBitrate = 160
)

Set-Location 'X:\Apps\_VideoEncoding\av1an\'

# Check if input file exists
if (!(Test-Path $InputVideo)) {
    Write-Error "Input video not found: $InputVideo"
    exit 1
}

# Check for required tools
$av1an = 'X:\Apps\_VideoEncoding\av1an\av1an++.exe'
$required_tools = @("vspipe", "scenedetect", $av1an, "mkvmerge")
foreach ($tool in $required_tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "Required tool not found: $tool"
        exit 1
    }
}

# Create temp directory
$temp_dir = Join-Path $tmpDir "temp_processing"
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null

# Run PySceneDetect
Write-Host "Detecting scenes..."
$scenes_file = Join-Path $temp_dir "scenes.csv"
scenedetect --input "$InputVideo" detect-content list-scenes --filename $scenes_file --skip-cuts --quiet

# Process each scene
$encoded_parts = @()
$scene_number = 0

$scenes = Import-Csv $scenes_file
foreach ($scene in $scenes) {
    $start_frame = [int]$scene.'Start Frame'
    $end_frame = [int]$scene.'End Frame'
    
    if ($start_frame -gt $end_frame) {
        Write-Error "Invalid frame range for scene ${scene_number}: ${start_frame} - ${end_frame}"
        continue
    }
    
    $scene_vs = Join-Path $temp_dir "scene_${scene_number}.vpy"
    $scene_out = Join-Path $temp_dir "scene_${scene_number}.mkv"
    
    # Create scene-specific VapourSynth script
    try {
        @"
import vapoursynth as vs
core = vs.core
clip = core.lsmas.LWLibavSource(r'$InputVideo')
clip = clip[${start_frame}:${end_frame}]
clip.set_output()
"@ | Set-Content $scene_vs
    }
    catch {
        Write-Error "Failed to create VapourSynth script for scene ${scene_number}: $_"
        continue
    }

    # Encode scene with av1an
    Write-Host "Encoding scene $scene_number..."
    & $av1an -i "$scene_vs" --target-quality $VMAFTarget `
            --audio-params "-c:a libopus -b:a ${AudioBitrate}k" `
            -o "$scene_out"

    if (Test-Path $scene_out) {
        $encoded_parts += $scene_out
    }
    else {
        Write-Error "Failed to encode scene $scene_number"
    }
    $scene_number++
}

if ($encoded_parts.Count -eq 0) {
    Write-Error "No scenes were successfully encoded"
    exit 1
}

# Join all parts using mkvmerge
Write-Host "Joining parts..."
$parts_list = ($encoded_parts | ForEach-Object { "`"$_`"" }) -join "+"
mkvmerge -o "$OutputVideo" $parts_list

# Cleanup
Write-Host "Cleaning up..."
Remove-Item -Recurse -Force $temp_dir

Write-Host "Processing complete! Output saved as: $OutputVideo"