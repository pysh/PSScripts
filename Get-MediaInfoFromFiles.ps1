Function Get-MI {
    Param (
        [string]$file = ('
        y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\The.Boys.2019.S01E01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8.mp4
    ').Trim()
    )
    . C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1
    Add-Type -Path ('c:\Users\pauln\OneDrive\Documents\PowerShell\Modules\Get-MediaInfo\3.7\MediaInfoSharp.dll')

    $videoSummary = @([PSCustomObject]@{
            CompleteName     = [IO.Path]::GetFileName($file) #$mi.GetInfo('General', 0, 'CompleteName'); 
            MovieName        = ''; 
            ID               = ''; 
            Language         = ''; 
            Title            = '';
            Format           = ''; 
            CodecID          = ''; 
            Width            = 0; 
            Height           = 0;
            DAR              = '';
            Bitrate          = 0;
            BitrateString    = '';
            ScanType         = '';
            BitDepth         = 0;
            FrameRate        = '';
            FrameRateFrc     = '';
            FrameRateNum     = 0;
            FrameRateMode    = '';
            FrameCount       = 0;
            Duration         = '';
            StreamSize       = '';
            Default          = '';
            EncodingSettings = ''
        })


    function Convert-StrToDouble {
        param (
            [string]$inStr = ''
        )
        $num = $null
        $success = [Double]::TryParse($inStr, [ref]$num)
        if ($success) {
            return $num
        }
    }

    if ([System.IO.Path]::GetExtension($file) -eq '.vpy') {
        Write-Host $file -ForegroundColor Magenta
        $prc = Invoke-Process -commandTitle "" -commandPath "vspipe.exe" -commandArguments ('--info "{0}"' -f $file)
        if ($prc.ExitCode -eq 0) {
            $vpyInfo = $prc.stdout
            <#             
            $videoSummary = [PSCustomObject]@{
                Width        = 0;
                Height       = 0;
                Frames       = 0;
                FPS          = '';
                FormatName   = '';
                ColorFamily  = '';
                Alpha        = $false;
                SampleType   = '';
                Bits         = 0;
                SubSamplingW = 0;
                SubSamplingH = 0
            }
            #>
            foreach ($prmString in (($vpyInfo -split "`n") | Where-Object { $_ -like '*: *' } )) {
                # Write-Host $prmString
                $prmName = $prmString.Split(':')[0].Trim()
                $prmValue = $prmString.Split(':')[1].Trim()
                switch ($prmName) {
                    <#
                    'Width' { $videoSummary.Width = $prmValue }
                    'Height' { $videoSummary.Height = $prmValue }
                    'Frames' { $videoSummary.Frames = $prmValue }
                    'FPS' { $videoSummary.FPS = $prmValue }
                    'Format Name' { $videoSummary.FormatName = $prmValue }
                    'Color Family' { $videoSummary.ColorFamily = $prmValue }
                    'Alpha' { $videoSummary.Alpha = $prmValue }
                    'Sample Type' { $videoSummary.SampleType = $prmValue }
                    'Bits' { $videoSummary.Bits = $prmValue }
                    'SubSampling W' { $videoSummary.SubSamplingW = $prmValue }
                    'SubSampling H' { $videoSummary.SubSamplingH = $prmValue }
                    #>
                    'Width' { $videoSummary[0].Width = $prmValue }
                    'Height' { $videoSummary[0].Height = $prmValue }
                    'Frames' { $videoSummary[0].FrameCount = $frameCount = $prmValue }
                    'FPS' { $videoSummary[0].FrameRate = $fps_t = $prmValue }
                    'Bits' { $videoSummary[0].BitDepth = $prmValue }
                    Default {}
                }
            }
            $fps_t -match '^(?<fps1>.*) \((?<fps2>.*) fps\)' | Out-Null
            if ($Matches.Count -eq 3) {
                [string]$fps_frc = $($Matches.fps1)
                [double]$fps_dbl = [double]($Matches.fps2)
                $videoSummary[0].FrameRateFrc = $fps_frc
                $videoSummary[0].FrameRateNum = $fps_dbl
                $videoSummary[0].Duration = ("{0:hh\:mm\:ss\.fff}" -f [System.TimeSpan]::FromSeconds($frameCount/$fps_dbl))
            }
        }
    }
    else {
        $mi = New-Object MediaInfoSharp -ArgumentList $file
        $audioSummary = @(@())
        for ($a = 0; $a -lt ($mi.GetCount('Audio')); $a++) {
            $audioSummary += @([PSCustomObject]@{
                    ID            = $mi.GetInfo('Audio', $a, 'ID'); 
                    Language      = $mi.GetInfo('Audio', $a, 'Language'); 
                    Title         = $mi.GetInfo('Audio', $a, 'Title')
                    Format        = $mi.GetInfo('Audio', $a, 'Format'); 
                    CodecID       = $mi.GetInfo('Audio', $a, 'CodecID'); 
                    Channels      = $mi.GetInfo('Audio', $a, 'Channels'); 
                    ChannelLayout = $mi.GetInfo('Audio', $a, 'ChannelLayout')
                    Bitrate       = $mi.GetInfo('Audio', $a, 'BitRate');
                    SamplingRate  = $mi.GetInfo('Audio', $a, 'SamplingRate');
                    StreamSize    = $mi.GetInfo('Audio', $a, 'StreamSize'); # /1Mb)
                    Default       = $mi.GetInfo('Audio', $a, 'Default')
                })
        }

        $videoSummary = @(@())
        for ($v = 0; $v -lt ($mi.GetCount('Video')); $v++) {
            $videoSummary += @([PSCustomObject]@{
                    CompleteName     = [IO.Path]::GetFileName($file) #$mi.GetInfo('General', 0, 'CompleteName'); 
                    MovieName        = $mi.GetInfo('General', 0, 'MovieName'); 
                    ID               = $mi.GetInfo('Video', $v, 'ID'); 
                    Language         = $mi.GetInfo('Video', $v, 'Language'); 
                    Title            = $mi.GetInfo('Video', $v, 'Title')
                    Format           = $mi.GetInfo('Video', $v, 'Format'); 
                    CodecID          = $mi.GetInfo('Video', $v, 'CodecID'); 
                    Width            = $mi.GetInfo('Video', $v, 'Width'); 
                    Height           = $mi.GetInfo('Video', $v, 'Height');
                    DAR              = $mi.GetInfo('Video', $v, 'DisplayAspectRatio/String');
                    Bitrate          = $mi.GetInfo('Video', $v, 'BitRate');
                    BitrateString    = $mi.GetInfo('Video', $v, 'BitRate/String');
                    ScanType         = $mi.GetInfo('Video', $v, 'ScanType');
                    BitDepth         = $mi.GetInfo('Video', $v, 'BitDepth');
                    FrameRate        = $mi.GetInfo('Video', $v, 'FrameRate');
                    FrameRateMode    = $mi.GetInfo('Video', $v, 'FrameRate_Mode');
                    FrameCount       = $mi.GetInfo('Video', $v, 'FrameCount');
                    Duration         = $mi.GetInfo('Video', $v, 'Duration/String4');
                    StreamSize       = $mi.GetInfo('Video', $v, 'StreamSize');
                    Default          = $mi.GetInfo('Video', $v, 'Default');
                    EncodingSettings = $mi.GetInfo('Video', $v, 'EncodingSettings')
                })
        }

        $mi.Dispose()
    }

    <# foreach ($a in $audioSummary) {
    Write-Host ('==============================') -ForegroundColor Black
    Write-Host ("ID      : {0}" -f $a.ID) -ForegroundColor Gray
    Write-Host ("Language: {0}" -f $a.Language) -ForegroundColor Yellow
    Write-Host ("CodecID : {0}" -f $a.CodecID) -ForegroundColor Green
    Write-Host ("Format  : {0}" -f $a.Format) -ForegroundColor Cyan
    Write-Host ("Channels: {0}" -f $a.Channels) -ForegroundColor Blue
    Write-Host ("Bitrate : {0}" -f $a.Bitrate) -ForegroundColor Magenta
} #>

    # $audioSummary | Format-Table -AutoSize
    # $videoSummary # | Out-GridView
    return $videoSummary
}

# Get-MI -file 'Y:\.temp\Zolotoe.Dno\vpy_dgdecnv\Zolotoe.dno.s01e01.vpy'