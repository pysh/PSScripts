Add-Type -AssemblyName System.Core

# Configuration
$ffmpegApp = 'ffmpeg.exe'
$encoderApp = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe'
$pipeName = "av1_encode_pipe_$(Get-Random -Minimum 1000 -Maximum 9999)"
$fullPipePath = "\\.\pipe\$pipeName"

# Create a scriptblock for the pipe server
$pipeServerScript = {
    param($pipeName)
    
    try {
        # Create NamedPipeServerStream
        $pipeStream = New-Object System.IO.Pipes.NamedPipeServerStream(
            $pipeName, 
            [System.IO.Pipes.PipeDirection]::InOut, 
            1, 
            [System.IO.Pipes.PipeTransmissionMode]::Byte
        )

        # Wait for client connection
        $pipeStream.WaitForConnection()

        # FFmpeg process parameters
        $ffmpegParams = @(
            '-y',
            "-i", "Y:\.temp\YT_y\Стендап комики 4k\Илья Соболев - Третий (Концерт, 2023) [4k].tmp\Илья Соболев - Третий (Концерт, 2023) [4k].avs",
            '-pix_fmt', 'yuv420p', 
            '-f', 'yuv4mpegpipe', 
            '-strict', '-1', 
            '-'
        )

        # Start FFmpeg process with pipe output
        $ffmpegProcess = Start-Process -FilePath $ffmpegApp -ArgumentList $ffmpegParams -NoNewWindow -PassThru -RedirectStandardOutput $pipeStream

        # Wait for FFmpeg to complete
        $ffmpegProcess.WaitForExit()

        # Close the pipe
        $pipeStream.Disconnect()
        $pipeStream.Close()
    }
    catch {
        Write-Error "Pipe Server Error: $_"
    }
}

# Create a scriptblock for the encoder
$encoderScript = {
    param($pipeName)
    
    try {
        # Encoder parameters
        $encoderParams = @(
            '--rc', '0',
            '--crf', '30',
            '--preset', '3',
            '--spy-rd', '0',
            '--input', $pipeName,
            '--output', "Y:\.temp\YT_y\Стендап комики 4k\Илья Соболев - Третий (Концерт, 2023) [4k].tmp\test_crf=30_preset=3_spy-rd 0.ivf"
        )

        # Start encoder process
        $encoderProcess = Start-Process -FilePath $encoderApp -ArgumentList $encoderParams -NoNewWindow -PassThru -Wait

        # Check encoder exit code
        if ($encoderProcess.ExitCode -ne 0) {
            throw "Encoder process failed with exit code $($encoderProcess.ExitCode)"
        }
    }
    catch {
        Write-Error "Encoder Error: $_"
    }
}

# Run pipe server and encoder in parallel jobs
$pipeJob = Start-Job -ScriptBlock $pipeServerScript -ArgumentList $pipeName
$encoderJob = Start-Job -ScriptBlock $encoderScript -ArgumentList $fullPipePath

# Wait for both jobs to complete
Wait-Job $pipeJob, $encoderJob

# Receive job results (optional)
Receive-Job $pipeJob
Receive-Job $encoderJob

# Clean up jobs
Remove-Job $pipeJob, $encoderJob




<# $ffmpegApp     = 'ffmpeg.exe'
$encoderApp    = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe'
$vspipeParams  = ''
$ffmpegParams  = @('-y'
    '-i "Y:\.temp\YT_y\Стендап комики 4k\Илья Соболев - Третий (Концерт, 2023) [4k].tmp\Илья Соболев - Третий (Концерт, 2023) [4k].avs"'
    '-pix_fmt yuv420p -f yuv4mpegpipe -strict -1 -'
)
$encoderParams = @(
    '--rc', '0',
    '--crf', '30',
    '--preset', '3',
    '--spy-rd', '0',
    '--input', 'stdin',
    '--output', "Y:\.temp\YT_y\Стендап комики 4k\Илья Соболев - Третий (Концерт, 2023) [4k].tmp\test_crf=30_preset=3_spy-rd 0.ivf"
)

$ffmpegProcess = Start-Process -FilePath $ffmpegApp -ArgumentList $ffmpegParams -NoNewWindow -PassThru
$encoderProcess= Start-Process -FilePath $encoderApp -ArgumentList $encoderParams -NoNewWindow -PassThru -RedirectStandardInput $ffmpegProcess.StandardInput -Wait
#>