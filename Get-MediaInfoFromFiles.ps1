
Add-Type -Path ('c:\Users\pauln\OneDrive\Documents\PowerShell\Modules\Get-MediaInfo\3.7\MediaInfoSharp.dll')
$file = ('
V:\Сериалы\Зарубежные\Потерянная комната (The Lost Room)\Потерянная комната (The Lost Room) (2006 WEB-DL)\The.Lost.Room.S01E03.The.Eye.and.the.Prime.Object.1080p.AMZN.WEB-DL.DD2.0.H.264.Rus.Eng.mkv
').Trim()


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

<# foreach ($a in $audioSummary) {
    Write-Host ('==============================') -ForegroundColor Black
    Write-Host ("ID      : {0}" -f $a.ID) -ForegroundColor Gray
    Write-Host ("Language: {0}" -f $a.Language) -ForegroundColor Yellow
    Write-Host ("CodecID : {0}" -f $a.CodecID) -ForegroundColor Green
    Write-Host ("Format  : {0}" -f $a.Format) -ForegroundColor Cyan
    Write-Host ("Channels: {0}" -f $a.Channels) -ForegroundColor Blue
    Write-Host ("Bitrate : {0}" -f $a.Bitrate) -ForegroundColor Magenta
} #>

$audioSummary | Format-Table -AutoSize
$videoSummary # | Out-GridView

