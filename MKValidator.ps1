Param (
    [String]$InputFileDirName = ('
    V:\
    ').Trim(), 
    [array] $filterList = @(
        ".mkv"
    ), 
    [Switch]$bRecurse = $false, 
    [Switch]$bCalcHash = $false, 
    [Switch]$bReCreateTable = $false, 
    [Switch]$isDebug = $false
)

# Types
Add-Type -Path 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\System.Data.SQLite.dll'

# Variables
[string]$InputFileDirNameEsc = [Management.Automation.WildcardPattern]::Escape($InputFileDirName)
[string]$execValidator = "mkvalidator.exe"
[switch]$bRecurse = $true
[string]$DBFileName = 'X:\files_db_DiskV.sqlite'
[Switch]$bCalcHash = $true

# Functions
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1'


# Deprecated functions


# Main script

# Clear-Host
Write-Host ('Ищем mkv файлы')
[array]$InputFileList = @()
if (Test-Path $InputFileDirNameEsc -PathType Leaf) {
    $InputFileList = @($InputFileDirNameEsc)
}
else {
    $InputFileList = Get-ChildItem ($InputFileDirNameEsc) -File -Recurse:$bRecurse | Where-Object { (($_.Extension -iin $filterList) ) }  #-and ($_.BaseName -inotlike '*`[av1an`]*')) }
}

$con = New-Object -TypeName System.Data.SQLite.SQLiteConnection
$con.ConnectionString = ("Data Source={0}" -f $DBFileName)
$con.Open()

If ($bReCreateTable) {
    $sql = $con.CreateCommand()
    $sql.CommandText = '
    DROP TABLE IF EXISTS files; 
    CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        dt DATETIME NOT NULL DEFAULT (datetime(''now'',''localtime'')), 
        di INTEGER(4) NOT NULL DEFAULT (strftime(''%s'',''now'')), 
        FileHashSHA265 TEXT(100), 
        FileHashMD5 TEXT(50), 
        FileCreationTime DATETIME,
        FileLastWriteTime DATETIME,
        FileSize INTEGER,
        FileName TEXT(256), 
        FilePath TEXT(2048), 
        MessageErr TEXT, 
        MessageOut TEXT
        );
        VACUUM;'
    $sql.CommandType = [System.Data.CommandType]::Text

    try {
        $sql.ExecuteNonQuery() | Out-Null
    }
    catch {
        <#Do this if a terminating exception happens#>
        Write-Host "Ошибка при создании таблицы files" -BackgroundColor DarkRed
    }
    finally {
        # $sql.Dispose()
    }

}

[System.Int32]$fc  = $InputFileList.Count
[System.Int64]$SizeTotal = ($InputFileList | Measure-Object -property length -sum).sum
Write-Host ("Найдено файлов: {0}" -f $fc) -ForegroundColor DarkBlue
Write-Host ("Общий размер: {0:N2} Gb" -f ($SizeTotal /1Gb))
# Start-Sleep -Seconds 5
[System.Int32]$c   = 0
[System.Int32]$prc = 0
[System.Int64]$SizeProcessed = 0
$dtFrom = Get-Date
$sql = $con.CreateCommand()
$PSStyle.Progress.View = 'Classic'
foreach ($FileItem in $InputFileList) {
    $InputFileNameEsc = [Management.Automation.WildcardPattern]::Escape($FileItem.FullName)
    if (Test-Path ($InputFileNameEsc) ) {
        $prmExec = ''
        $prmExec = @(
            '--no-warn',
            '--quick',
            '--quiet',
            ('"{0}"' -f $FileItem)
        )

        $sql.CommandText = ('SELECT COUNT(1) FROM files WHERE FilePath="{0}" AND FileName="{1}"' -f $FileItem.DirectoryName, $FileItem.Name)
        $sql.CommandType = [System.Data.CommandType]::Text
        #$sql.ExecuteNonQuery() | Out-Null
        [Int32]$RowCount = $sql.ExecuteScalar()

        if (($RowCount -gt 0) -and ((1) -and (1))) {
            # Файл уже есть в БД
            # Write-Host ("[{0:yyyyMMdd_HHmmss}] {1}`t Файл уже есть в БД, пропускаем." -f (Get-Date), $FileItem) -ForegroundColor DarkYellow
            # $dtFrom = Get-Date
            $fc -= 1
            $SizeTotal -= $FileItem.Length
        }
        else {
            # Добавляем новый файл
            [string]$HashMD5 = $Null
            [string]$HashSHA256 = $Null
            Write-Host ("[{0:yyyyMMdd_HHmmss}] {1}`t{2:N2} Gb`t" -f (Get-Date), $FileItem.FullName, ($FileItem.Length /1Gb)) -ForegroundColor DarkBlue
            if ($bCalcHash) {
                Write-Host ("MD5:`t") -ForegroundColor Cyan -NoNewline
                $HashMD5    = (Get-FileHash -Path $InputFileNameEsc -Algorithm MD5).Hash
                Write-Host ($HashMD5) -ForegroundColor Cyan
                Write-Host ("SHA256:`t") -ForegroundColor Cyan -NoNewline
                $HashSHA256 = (Get-FileHash -Path $InputFileNameEsc -Algorithm SHA256).Hash
                Write-Host ($HashSHA256) -ForegroundColor DarkCyan
            } else {} #$Hash = ("{0:N2} Gb" -f ($FileItem.Length /1Gb))}
            Write-Host ("MKValidator:`t") -ForegroundColor Cyan -NoNewline
            [pscustomobject]$retVal = $null
            $retVal = Invoke-Process -commandPath $execValidator -commandArguments ($prmExec -join ' ')
            switch ($retVal.ExitCode) {
                0 { Write-Host 'OK' -ForegroundColor Green }
                Default { Write-Host ("ERROR`r`n{0}" -f $retVal.stderr) -BackgroundColor DarkRed }
            }
            $sql = $con.CreateCommand()
            $sql.CommandText = "INSERT INTO files (FileHashMD5, FileHashSHA256, FileCreationTime, FileLastWriteTime, FileSize, FileName, FilePath, MessageErr, MessageOut) VALUES (@FileHashMD5, @FileHashSHA256, @FileCreationTime, @FileLastWriteTime, @FileSize, @FileName, @FilePath, @MessageErr, @MessageOut)"
            # $sql.Parameters.AddWithValue("@id", $null) | Out-Null
            $sql.Parameters.AddWithValue("@FileHashMD5", $HashMD5) | Out-Null
            $sql.Parameters.AddWithValue("@FileHashSHA256", $HashSHA256) | Out-Null
            $sql.Parameters.AddWithValue("@FileCreationTime", $FileItem.CreationTime) | Out-Null
            $sql.Parameters.AddWithValue("@FileLastWriteTime", $FileItem.LastWriteTime) | Out-Null
            $sql.Parameters.AddWithValue("@FileSize", $FileItem.Length) | Out-Null
            $sql.Parameters.AddWithValue("@FileName", $FileItem.Name) | Out-Null
            $sql.Parameters.AddWithValue("@FilePath", $FileItem.DirectoryName) | Out-Null
            $sql.Parameters.AddWithValue("@MessageErr", $retVal.stderr.ToString()) | Out-Null
            $sql.Parameters.AddWithValue("@MessageOut", $retVal.stdout.ToString()) | Out-Null
            $sql.ExecuteNonQuery() | Out-Null
            # $sql.Dispose()

            $SizeProcessed += $FileItem.Length
            $c += 1
            $prc = ($c / $fc * 100)
            $dtCurrent = Get-Date
            [timespan]$dtSec = $dtCurrent - $dtFrom
                $dtSec = [timespan]::FromSeconds([Math]::Round($dtSec.TotalSeconds))
            $intSeconds = [System.Math]::Round(($fc * $dtSec.TotalSeconds / $c) - $dtSec.TotalSeconds)
            # BySize
            $PrcBySize = ($SizeProcessed / $SizeTotal * 100)
            $intSecondsBySize = [System.Math]::Round(($SizeTotal * $dtSec.TotalSeconds / $SizeProcessed) - $dtSec.TotalSeconds)
            $dtTimeBySize = [timespan]::FromSeconds($intSecondsBySize)
            
            # Write-Host "= = = = = = ="
            # Write-Host ("{0} / {1}`tпрошло {2}`t{3:N2} / {4:N2} Gb`t= {5:N2}%" -f $c, $fc, $dtSec, ($SizeProcessed /1Gb), ($SizeTotal /1Gb), $prc) -ForegroundColor DarkGray
            Write-Host ("{0}/{1}`t{2:N2}Gb/{3:N2}Gb`t{4} ({5})`t= {6:N2}%`t~{7:N2} Mb/sec" -f 
                        $c, $fc, ($SizeProcessed /1Gb), ($SizeTotal /1Gb), $dtTimeBySize, ((Get-Date)+$dtTimeBySize), $PrcBySize, (($SizeProcessed / $dtSec.TotalSeconds) /1Mb)) -ForegroundColor Gray
            
            Write-Host ("= "*10)
            Write-Progress -Activity 'Scanning...' -Status $FileItem.Directory -PercentComplete $prc -CurrentOperation $FileItem.Name -SecondsRemaining $intSeconds
        }
    }
    else { 
        Write-Host ("[{0:yyyyMMdd_HHmmss}] {1}`t Файл не найден, пропускаем." -f (Get-Date), $FileItem) -ForegroundColor Red 
    }

}
Write-Progress -Activity 'Completed' -Completed:$true
$sql.Dispose()
$con.Close()