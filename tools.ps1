# Load external functions
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\function_Invoke-Executable.ps1'
enum libVmafPool {
    mean
    harmonic_mean
}

$script:ColorRangeMappings = @{
    'tv' = @{
        'aomenc' = @{ param = '--color-range='; value = '0' };
        'x264'   = @{ param = '--range='; value = '0' };
        'x265'   = @{ param = '--range'; value = 'limited' };
        'svt'    = @{ param = '--color-range'; value = '0' } 
    }
    'pc' = @{
        'aomenc' = @{ param = '--color-range='; value = '1' };
        'x264'   = @{ param = '--range='; value = '1' };
        'x265'   = @{ param = '--range'; value = 'full' };
        'svt'    = @{ param = '--color-range'; value = '1' } 
    }
}

$script:ColorPrimariesMappings = @{
    'bt709'     = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt709' };
        'x264'   = @{ param = '--colorprim='; value = '1' };
        'x265'   = @{ param = '--colorprim'; value = 'bt709' };
        'svt'    = @{ param = '--color-primaries'; value = '1' } 
    }
    'bt470bg'   = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt470bg' };
        'x264'   = @{ param = '--colorprim='; value = '5' };
        'x265'   = @{ param = '--colorprim'; value = 'bt470bg' };
        'svt'    = @{ param = '--color-primaries'; value = '5' } 
    }
    'bt470m'    = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt470m' };
        'x264'   = @{ param = '--colorprim='; value = '4' };
        'x265'   = @{ param = '--colorprim'; value = 'bt470m' };
        'svt'    = @{ param = '--color-primaries'; value = '4' } 
    }
    'bt2020'    = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'bt2020' };
        'x264'   = @{ param = '--colorprim='; value = '9' };
        'x265'   = @{ param = '--colorprim'; value = 'bt2020' };
        'svt'    = @{ param = '--color-primaries'; value = '9' } 
    }
    'smpte170m' = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'smpte170' };
        'x264'   = @{ param = '--colorprim='; value = '6' };
        'x265'   = @{ param = '--colorprim'; value = 'smpte170m' };
        'svt'    = @{ param = '--color-primaries'; value = '6' } 
    }
    'smpte240m' = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'smpte240' };
        'x264'   = @{ param = '--colorprim='; value = '7' };
        'x265'   = @{ param = '--colorprim'; value = 'smpte240m' };
        'svt'    = @{ param = '--color-primaries'; value = '7' } 
    }
    'film'      = @{
        'aomenc' = @{ param = '--color-primaries='; value = 'film' };
        'x264'   = @{ param = '--colorprim='; value = '8' };
        'x265'   = @{ param = '--colorprim'; value = 'film' };
        'svt'    = @{ param = '--color-primaries'; value = '8' } 
    }
}

$script:TransferMappings = @{
    'bt709'     = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt709' };
        'x264'   = @{ param = '--transfer='; value = '1' };
        'x265'   = @{ param = '--transfer'; value = 'bt709' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '1' } 
    }
    'bt470bg'   = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt470bg' };
        'x264'   = @{ param = '--transfer='; value = '5' };
        'x265'   = @{ param = '--transfer'; value = 'bt470bg' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '5' } 
    }
    'bt470m'    = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt470m' };
        'x264'   = @{ param = '--transfer='; value = '4' };
        'x265'   = @{ param = '--transfer'; value = 'bt470m' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '4' } 
    }
    'bt2020-10' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt2020-10bit' };
        'x264'   = @{ param = '--transfer='; value = '14' };
        'x265'   = @{ param = '--transfer'; value = 'bt2020-10' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '14' } 
    }
    'bt2020-12' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'bt2020-12bit' };
        'x264'   = @{ param = '--transfer='; value = '15' };
        'x265'   = @{ param = '--transfer'; value = 'bt2020-12' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '15' } 
    }
    'smpte170m' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'unspecified' };
        'x264'   = @{ param = '--transfer='; value = '6' };
        'x265'   = @{ param = '--transfer'; value = 'smpte170m' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '6' } 
    }
    'smpte240m' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'unspecified' };
        'x264'   = @{ param = '--transfer='; value = '7' };
        'x265'   = @{ param = '--transfer'; value = 'smpte240m' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '7' } 
    }
    'smpte2084' = @{
        'aomenc' = @{ param = '--transfer-characteristics='; value = 'smpte2084' };
        'x264'   = @{ param = '--transfer='; value = '16' };
        'x265'   = @{ param = '--transfer'; value = 'smpte2084' };
        'svt'    = @{ param = '--transfer-characteristics'; value = '16' } 
    }
}

$script:MatrixMappings = @{
    'bt709'     = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '1' };
        'x264'   = @{ param = '--colormatrix='; value = '1' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt709' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '1' } 
    }
    'fcc'       = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '4' };
        'x264'   = @{ param = '--colormatrix='; value = '4' };
        'x265'   = @{ param = '--colormatrix'; value = 'fcc' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '4' } 
    }
    'bt470bg'   = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '5' };
        'x264'   = @{ param = '--colormatrix='; value = '5' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt470bg' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '5' } 
    }
    'smpte170m' = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '6' };
        'x264'   = @{ param = '--colormatrix='; value = '6' };
        'x265'   = @{ param = '--colormatrix'; value = 'smpte170m' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '6' } 
    }
    'smpte240m' = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '7' };
        'x264'   = @{ param = '--colormatrix='; value = '7' };
        'x265'   = @{ param = '--colormatrix'; value = 'smpte240m' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '7' } 
    }
    'bt2020nc'  = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '9' };
        'x264'   = @{ param = '--colormatrix='; value = '9' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt2020nc' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '9' } 
    }
    'bt2020c'   = @{
        'aomenc' = @{ param = '--matrix-coefficients='; value = '10' };
        'x264'   = @{ param = '--colormatrix='; value = '10' };
        'x265'   = @{ param = '--colormatrix'; value = 'bt2020c' };
        'svt'    = @{ param = '--matrix-coefficients'; value = '10' } 
    }
}

function Get-XPSNRValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distorted,
        [Parameter(Mandatory = $true)]
        [string]$Reference,
        [int]$TrimStartSeconds = 0,
        [int]$DurationSeconds = 0,
        [libVmafPool]$Pool = [libVmafPool]::harmonic_mean,
        [string]$OutputLog
    )

    $prmXPSNR = @(
        '-filter_complex "'
        if ($TrimStartSeconds -gt 0 -and $DurationSeconds -gt 0) {
            "[0:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds)[dist];"
            "[1:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds)[ref];"
        }
        else { "[0:v]null[dist];[1:v]null[ref];" }
        "[dist][ref]"
        "xpsnr=eof_action=endall"
        #$(if ($OutputLog) {":stats_file='$($OutputLog)'"})
        '"'
    )

    $cmdXPSNR = @(
        "-hide_banner -y -nostats"
        ('-i "{0}" -i "{1}"' -f $Distorted, $Reference)
        ($prmXPSNR -join "")
        "-an -sn -dn -f null -"
    ) -join " "

    Write-Verbose "Launching ffmpeg with args: $cmdXPSNR"
    $outputPSNR = Invoke-Executable -sExeFile 'ffmpeg' -cArgs $cmdXPSNR -sWorkDir (Get-Location).Path 
    $regexp = '.*XPSNR  y: (?<xpsnr_y>\d+\.?\d+).*u: (?<xpsnr_u>\d+\.?\d+).*v: (?<xpsnr_v>\d+\.?\d+)'
    if ($outputPSNR.StdErr -match $regexp) {
        $xpsnr = @{
            Y   = [double]$Matches.xpsnr_y
            U   = [double]$Matches.xpsnr_u
            V   = [double]$Matches.xpsnr_v
            AVG = [double]($Matches.xpsnr_y, $Matches.xpsnr_u, $Matches.xpsnr_v | Measure-Object -Average).Average
        }
    }
    else {
        throw "Failed to extract XPSNR score from output"
    }
    if (-not $xpsnr.AVG) {
        throw "Failed to extract XPSNR score from output"
    }
    return [double]$xpsnr.AVG
}

function Get-VMAFValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distorted,
        [Parameter(Mandatory = $true)]
        [string]$Reference,
        [int]$MaxThreads = [Environment]::ProcessorCount,
        [int]$TrimStartSeconds = 0,
        [int]$DurationSeconds = 0,
        [string]$ModelVersion = 'vmaf_v0.6.1',
        [ValidateSet('json', 'xml', 'csv')]
        [string]$LogFormat = 'json',
        [string]$OutputLog
    )

    $prmVMAF = @(
        '-filter_complex "'
        if ($TrimStartSeconds -gt 0 -and $DurationSeconds -gt 0) {
            "[0:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds),settb=AVTB,setpts=PTS-STARTPTS[dist];"
            "[1:v]trim=start=$($TrimStartSeconds):duration=$($DurationSeconds),settb=AVTB,setpts=PTS-STARTPTS[ref];"
        }
        else { "[0:v]null[dist];[1:v]null[ref];" }
        ("[dist][ref]libvmaf=eof_action=endall",
        "log_fmt=$($LogFormat)",
        "log_path='$($OutputLog)'",
        "n_threads=$($MaxThreads)",
        "n_subsample=3",
        "pool=$($Pool)",
        "model=version=$($ModelVersion)" -join ':')
        '"'
    )
    $cmdVMAF = @(
        "-hide_banner -y -nostats",
        ('-i "{0}" -i "{1}"' -f $Distorted, $Reference)
        ($prmVMAF -join ""),
        "-an -sn -dn -f null -"
    ) -join " "

    Write-Verbose "Launching ffmpeg with args: $cmdVMAF"
    $outputVMAF = Invoke-Executable -sExeFile 'ffmpeg' -cArgs $cmdVMAF -sWorkDir (Get-Location).Path
    $vmaf = $outputVMAF.StdErr | Select-String "VMAF score: (\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    if (-not $vmaf) {
        throw "Failed to extract VMAF score from output"
    }
    return [double]$vmaf
}

function Get-VideoStats {
    param([Parameter(Mandatory = $true)][string]$VideoPath)
    
    $size = (Get-Item -LiteralPath $VideoPath).Length
    # $sizeGB = [math]::Round($size/1GB, 3)
    
    # Get fps using ffprobe
    $outputFPS = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$VideoPath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get video FPS: $outputFPS"
    }
    
    # Calculate FPS from ratio (usually comes as "24000/1001" or similar)
    $fps = if ($outputFPS -match '(\d+)/(\d+)') {
        [math]::Round([decimal]$matches[1] / [decimal]$matches[2], 3)
    }
    else {
        [decimal]$outputFPS
    }

    # Get frame count using ffprobe
    $outputFrameCount = & ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$VideoPath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get video frame count: $outputFrameCount"
    }
    [decimal]$frameCount = [math]::Round($outputFrameCount)
    
    return @{
        Path   = $VideoPath
        Name   = (Get-Item -LiteralPath $VideoPath).Name
        Size   = $size
        Frames = [int]$frameCount
        FPS    = $fps
    }
}

function Get-VideoQuality {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distorted,
        [Parameter(Mandatory = $true)]
        [string]$Reference,
        [switch]$calcXPSNR,
        [switch]$calcVMAF,
        [int]$TrimStartSeconds = 0,
        [int]$DurationSeconds = 0,
        [int]$MaxThreads = [Environment]::ProcessorCount,
        [switch]$WriteLog = $false
    )

    # Create temp files for metrics output
    if ($WriteLog) {
        # $rndFileName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName())
        $logXPSNR = [System.IO.Path]::ChangeExtension($Distorted, "xpsnr.log").Replace('\', '/').Replace(':', '\:')
        $logVMAF = [System.IO.Path]::ChangeExtension($Distorted, "vmaf.json").Replace('\', '/').Replace(':', '\:')
    }
    else {
        $logXPSNR = $null
        $logVMAF = $null
    }

    try {
        # Set working directory to avoid ffmpeg creating files in random locations
        Set-Location -LiteralPath (Get-Item -LiteralPath $Distorted).Directory.FullName

        # Calculate XPSNR score
        $xpsnr = if ($calcXPSNR) {
            Get-XPSNRValue -Distorted $Distorted `
                -Reference $Reference `
                -TrimStartSeconds $TrimStartSeconds `
                -DurationSeconds $DurationSeconds `
                -OutputLog $logXPSNR
        }

        # Calculate VMAF score
        $vmaf = if ($calcVMAF) {
            Get-VMAFValue  -Distorted $Distorted `
                -Reference $Reference `
                -TrimStartSeconds $TrimStartSeconds `
                -DurationSeconds $DurationSeconds `
                -OutputLog $logVMAF `
                -MaxThreads $MaxThreads
        }

        return @{
            VMAF  = $vmaf
            XPSNR = $xpsnr
        }
    }
    catch {
        Write-Error "Error in Get-VideoQuality: $_"
        throw
    }
    finally {
        # Optional: Clean up temp files if not WriteLog
        if (-not $WriteLog) {
            if ($logXPSNR -and (Test-Path -LiteralPath $logXPSNR)) {
                Remove-Item $logXPSNR -Force
            }
            if ($logVMAF -and (Test-Path -LiteralPath $logVMAF)) {
                Remove-Item $logVMAF -Force
            }
        }
    }
}

function Get-VideoColorParams {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoPath
    )

    $colorParams = & ffprobe -v error -select_streams v:0 `
        -show_entries "stream=color_range,color_space,color_transfer,color_primaries" `
        -of default=noprint_wrappers=1 "$VideoPath" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get video color parameters: $colorParams"
    }

    $result = @{}
    $colorParams | ForEach-Object {
        if ($_ -match '(.+)=(.+)') {
            $key = $matches[1]
            $value = $matches[2]
            if ($value -ne 'unknown') {
                $result[$key] = $value
            }
        }
    }

    return @{
        ColorRange     = $result['color_range']
        ColorSpace     = $result['color_space']      # Matrix coefficients
        ColorTransfer  = $result['color_transfer']   # Transfer characteristics
        ColorPrimaries = $result['color_primaries']
    }
}

function Get-VideoColorMappings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoPath
    )

    $colorParams = Get-VideoColorParams -VideoPath $VideoPath
    $mappings = @{}

    # Map color range
    if ($colorParams.ColorRange -and $script:ColorRangeMappings[$colorParams.ColorRange]) {
        $mappings['Range'] = $script:ColorRangeMappings[$colorParams.ColorRange]
    }

    # Map color primaries
    if ($colorParams.ColorPrimaries -and $script:ColorPrimariesMappings[$colorParams.ColorPrimaries]) {
        $mappings['Primaries'] = $script:ColorPrimariesMappings[$colorParams.ColorPrimaries]
    }

    # Map transfer characteristics
    if ($colorParams.ColorTransfer -and $script:TransferMappings[$colorParams.ColorTransfer]) {
        $mappings['Transfer'] = $script:TransferMappings[$colorParams.ColorTransfer]
    }

    # Map matrix coefficients
    if ($colorParams.ColorSpace -and $script:MatrixMappings[$colorParams.ColorSpace]) {
        $mappings['Matrix'] = $script:MatrixMappings[$colorParams.ColorSpace]
    }

    return $mappings
}

# Using:
# $audioParams = Get-FFmpegAudioParameters -InputFileName "video.mkv" -Codec libopus -MaxChannels 6
function Get-FFmpegAudioParameters {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFileName,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('libopus', 'libfdk_aac')]
        [string]$Codec = 'libopus',
        
        [Parameter(Mandatory = $false)]
        [int]$MaxChannels = 0
    )

    # Get audio tracks info using ffprobe
    $consoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $audioTracks = (. ffprobe -v error -select_streams a -show_entries `
            "stream=index,codec_name,channels,channel_layout:stream_disposition:stream_tags=language,title" `
            -of json "$InputFileName") | ConvertFrom-Json
    [Console]::OutputEncoding = $consoleEncoding

    $audioParams = @()
    $trackIndex = 0
    foreach ($track in $audioTracks.streams) {
        $index = $track.index
        $channels = $track.channels
        $channelLayout = $track.channel_layout

        # Limit channels if MaxChannels specified
        if ($MaxChannels -gt 0 -and $channels -gt $MaxChannels) {
            $channels = $MaxChannels
        }

        # Set bitrate based on channels and codec
        $bitrate = switch ($Codec) {
            'libopus' {
                switch ($channels) {
                    { $_ -le 2 } { '160k'; break }
                    { $_ -le 6 } { '384k'; break }
                    default { '512k' }
                }
            }
            'libfdk_aac' {
                switch ($channels) {
                    { $_ -le 2 } { '192k'; break }
                    { $_ -le 6 } { '512k'; break }
                    default { '768k' }
                }
            }
        }

        # Build parameter string for this track
        $trackParams = @(
            "-map 0:a:$TrackIndex"
            "-c:a:$trackIndex $Codec"
            if ($Codec -eq 'libfdk_aac') {
                "-vbr 5"  # High quality VBR mode for libfdk_aac
            }
            else {
                "-b:a:$trackIndex $bitrate"
            }
            "-ac:a:$trackIndex $channels"
        )

        # Add channel layout conversion if needed
        if ($channels -ne $track.channels -and $channelLayout -like "*(side)*") {
            $trackParams += "-af:a:$trackIndex aformat=channel_layouts='7.1|5.1|stereo'"
        }

        # Add metadata
        if ($track.tags.language) {
            $trackParams += "-metadata:s:a:$trackIndex language=$($track.tags.language)"
        }
        if ($track.tags.title) {
            $trackParams += "-metadata:s:a:$trackIndex title='$($track.tags.title)'"
        }
        elseif ($track.disposition.original -eq 1) {
            $trackParams += "-metadata:s:a:$trackIndex title='Original Audio'"
        }

        # Set disposition
        $disposition = if ($track.disposition.default -eq 1) { 'default' } else { '0' }
        $trackParams += "-disposition:a:$trackIndex $disposition"

        $audioParams += ($trackParams -join ' ')
        $trackIndex++
    }

    return $audioParams
}

function Save-VideoTags {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoPath
    )
    
    $exclusionTags = @('Writing application', 'Writing library', 'ENCODER')
    
    try {
        # Get tags using ffprobe
        $consoleEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $tags = (. ffprobe -v error -show_entries format_tags -of json "$VideoPath") | ConvertFrom-Json
        [Console]::OutputEncoding = $consoleEncoding

        # Convert tags to MKVToolNix XML format
        $xmlTags = New-Object System.Xml.XmlDocument
        $xmlTags.AppendChild($xmlTags.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
        $root = $xmlTags.CreateElement("Tags")
        $xmlTags.AppendChild($root) | Out-Null
        $tagElement = $xmlTags.CreateElement("Tag")
        $root.AppendChild($tagElement) | Out-Null

        foreach ($tag in $tags.format.tags.PSObject.Properties) {
            if ($tag.Name -notin $exclusionTags) {
                $simpleElement = $xmlTags.CreateElement("Simple")
                $nameElement = $xmlTags.CreateElement("Name")
                $nameElement.InnerText = [System.Web.HttpUtility]::HtmlEncode($tag.Name)
                $simpleElement.AppendChild($nameElement) | Out-Null
                $valueElement = $xmlTags.CreateElement("String")
                $valueElement.InnerText = [System.Web.HttpUtility]::HtmlEncode($tag.Value)
                $simpleElement.AppendChild($valueElement) | Out-Null
                $tagElement.AppendChild($simpleElement) | Out-Null
            }
        }

        # Save tags to XML
        $xmlPath = [System.IO.Path]::ChangeExtension($VideoPath, "tags.xml")
        $xmlTags.Save($xmlPath)


        # Save tags to JSON
        $jsonPath = [System.IO.Path]::ChangeExtension($VideoPath, "tags.json")
        $tags.format | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8 -Force
        
        
        Write-Host "Tags saved to: $jsonPath"
        return $jsonPath
    }
    catch {
        Write-Error "Failed to save video tags: $_"
        Write-Host $_
    }
}

function Set-VideoTags {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TagsPath
    )
    
    try {
        # Read tags from JSON
        # $tags = Get-Content -LiteralPath $TagsPath -Raw | ConvertFrom-Json
        
        # Build mkvpropedit commands
        $commands = @('"--tags global:{0}"' -f $TagsPath)
        # foreach ($tag in $tags.format.tags.PSObject.Properties) {

        #     $commands += "--set ""$($tag.Name)=$($tag.Value)"""
        # }
        
        # Execute mkvpropedit
        Write-Host $commands -ForegroundColor Yellow
        $consoleEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $result = & mkvpropedit "$VideoPath" $commands
        [Console]::OutputEncoding = $consoleEncoding
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Tags successfully applied to: $VideoPath"
            return $true
        }
        else {
            throw "mkvpropedit failed with exit code: $LASTEXITCODE `r`n$result"
        }
    }
    catch {
        Write-Error "Failed to set video tags: $_"
        return $false
    }
}