param(
    # [Parameter(Mandatory=$true)]
    [string]$InputFile = 'y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\01\The.Walking.Dead.S01E01.mkv',
    # [Parameter(Mandatory=$true)]
    [string]$OutputFile = 'y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 01\test\01\The.Walking.Dead.S01E01_test_out.mkv',
    [string]$tmpDir = 'y:\.temp',
    [int]$VmafTarget = 95,
    [int]$AudioBitrate = 160
)

Set-Location 'X:\Apps\_VideoEncoding\av1an\'

# Validate input file
if (-not (Test-Path $InputFile)) {
    Write-Error "Input file does not exist: $InputFile"
    exit 1
}

# Check required tools
$requiredTools = @("scenedetect", "vspipe", "av1an++", "mkvmerge")
foreach ($tool in $requiredTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "Required tool not found: $tool"
        exit 1
    }
}

# Create work directory
$workDir = Join-Path $tmpDir "processing_temp"
try {
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
} catch {
    Write-Error "Failed to create working directory: $_"
    exit 1
}

# Scene detection
Write-Host "Detecting scenes..."
try {
    scenedetect -i $InputFile -o $workDir detect-content split-video
} catch {
    Write-Error "Scene detection failed: $_"
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Verify scenes were created
$scenes = Get-ChildItem -Path $workDir -Filter "*.mkv"
if ($scenes.Count -eq 0) {
    Write-Error "No scenes were detected in the input file"
    Remove-Item -Path $workDir -Recurse -Force
    exit 1
}

# Generate VapourSynth scripts for each scene
foreach ($scene in $scenes) {
    $vsScript = @"
import vapoursynth as vs
import havsfunc as haf
core = vs.core
clip = core.lsmas.LWLibavSource(r'$($scene.FullName)')
#clip = haf.Deblock_QED(clip)
clip.set_output()
"@
    $vsFile = Join-Path $workDir "$($scene.BaseName).vpy"
    try {
        $vsScript | Out-File -FilePath $vsFile -Encoding utf8
    } catch {
        Write-Error "Failed to create VapourSynth script for scene $($scene.Name): $_"
        Remove-Item -Path $workDir -Recurse -Force
        exit 1
    }
}

# Encode each scene
$encodedScenes = @()
foreach ($scene in $scenes) {
    $vsFile = Join-Path $workDir "$($scene.BaseName).vpy"
    $outputScene = Join-Path $workDir "$($scene.BaseName)_encoded.mkv"
    
    Write-Host "Encoding scene: $($scene.Name)"
    try {
        av1an -i $vsFile --vmaf-target $VmafTarget `
            --audio-params "-c:a libopus -b:a ${AudioBitrate}k" `
            -o $outputScene

        if (Test-Path $outputScene) {
            $encodedScenes += $outputScene
        } else {
            throw "Encoded file was not created"
        }
    } catch {
        Write-Error "Failed to encode scene $($scene.Name): $_"
        Remove-Item -Path $workDir -Recurse -Force
        exit 1
    }
}

# Join encoded scenes
$sceneList = Join-Path $workDir "scenes.txt"
try {
    $encodedScenes | Out-File -FilePath $sceneList
    mkvmerge -o $OutputFile --merge-files "@$sceneList"

    if (-not (Test-Path $OutputFile)) {
        throw "Output file was not created"
    }
} catch {
    Write-Error "Failed to merge scenes: $_"
    Remove-Item -Path $workDir -Recurse -Force
    exit 1
}

# Cleanup
try {
    Remove-Item -Path $workDir -Recurse -Force
} catch {
    Write-Warning "Failed to clean up temporary files: $_"
}

Write-Host "Processing complete. Output saved to: $OutputFile"