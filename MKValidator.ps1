Param (
    [String]$InputFileDirName = ('
    V:\
    ').Trim(), 
    [array] $filterList = @(
        ".mkv"
    ), 
    [Switch]$bRecurse = $false, 
    [Switch]$bCalcHash = $false, 
    [Switch]$isDebug = $false
)

# Types
Add-Type -Path 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\System.Data.SQLite.dll'

# Variables
[string]$InputFileDirNameEsc = [Management.Automation.WildcardPattern]::Escape($InputFileDirName)
[string]$execValidator = "mkvalidator.exe"
[switch]$bRecurse = $true

# Functions
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1'


# Deprecated functions


# Main script

Clear-Host
Write-Host ('Ищем mkv файлы')
[array]$InputFileList = @()
if (Test-Path $InputFileDirNameEsc -PathType Leaf) {
    $InputFileList = @($InputFileDirNameEsc)
}
else {
    $InputFileList = Get-ChildItem ($InputFileDirNameEsc) -File -Recurse:$bRecurse | Where-Object { (($_.Extension -iin $filterList) ) }  #-and ($_.BaseName -inotlike '*`[av1an`]*')) }
}
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor DarkBlue

$con = New-Object -TypeName System.Data.SQLite.SQLiteConnection
$con.ConnectionString = "Data Source=X:\files_db_DiskV.sqlite"
$con.Open()


$sql = $con.CreateCommand()
$sql.CommandText = '
DROP TABLE IF EXISTS files; 
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    dt DATETIME NOT NULL DEFAULT (datetime(''now'',''localtime'')), 
    di INTEGER(4) NOT NULL DEFAULT (strftime(''%s'',''now'')), 
    FileHash VARCHAR(256), 
    FileCreationTime DATETIME,
    FileLastWriteTime DATETIME,
    FileSize INTEGER,
    FileName VARCHAR(256), 
    FilePath VARCHAR(2048), 
    MessageErr TEXT, 
    MessageOut TEXT
    );
    VACUUM;'


$sql.CommandType = [System.Data.CommandType]::Text
$sql.ExecuteNonQuery() | Out-Null
$sql.Dispose()


foreach ($InputFileName in $InputFileList) {
    $InputFileNameEsc = [Management.Automation.WildcardPattern]::Escape($InputFileName)
    if (Test-Path ($InputFileNameEsc) ) {
        $prmExec = ''
        $prmExec = @(
            '--no-warn',
            '--quick',
            '--quiet',
            ('"{0}"' -f $InputFileName)
        )

    }
    [string]$Hash = ''
    Write-Host ("[{0:yyyyMMdd_HHmmss}] {1}`t" -f (Get-Date), $InputFileName) -ForegroundColor DarkBlue -NoNewline
    if ($bCalcHash) {
        $Hash = (Get-FileHash -Path $InputFileNameEsc -Algorithm MD5).Hash
    }
    Write-Host ("{0}`t" -f $Hash) -ForegroundColor Cyan  -NoNewline
    # Write-Host ("Verifying: {0}... " -f $InputFileName) -ForegroundColor Blue -NoNewline
    # Write-Host ($prmExec -join ' ') -ForegroundColor Cyan
    # [System.Diagnostics.Process]$retVal = Execute-Command -commandPath $execValidator -commandArguments ($prmExec -join ' ')
    [pscustomobject]$retVal = $null
    $retVal = Invoke-Process -commandPath $execValidator -commandArguments ($prmExec -join ' ')
    switch ($retVal.ExitCode) {
        0 { Write-Host 'OK' -ForegroundColor Green }
        Default { Write-Host ("ERROR`r`n{0}" -f $retVal.stderr) -BackgroundColor DarkRed }
    }
    $sql = $con.CreateCommand()
    $sql.CommandText = "INSERT INTO files (FileHash, FileCreationTime, FileLastWriteTime, FileSize, FileName, FilePath, MessageErr, MessageOut) VALUES (@FileHash, @FileCreationTime, @FileLastWriteTime, @FileSize, @FileName, @FilePath, @MessageErr, @MessageOut)"
    # $sql.Parameters.AddWithValue("@id", $null) | Out-Null
    $sql.Parameters.AddWithValue("@FileHash", $Hash) | Out-Null
    $sql.Parameters.AddWithValue("@FileCreationTime", $InputFileName.CreationTime) | Out-Null
    $sql.Parameters.AddWithValue("@FileLastWriteTime", $InputFileName.LastWriteTime) | Out-Null
    $sql.Parameters.AddWithValue("@FileSize", $InputFileName.Length) | Out-Null
    $sql.Parameters.AddWithValue("@FileName", $InputFileName.Name) | Out-Null
    $sql.Parameters.AddWithValue("@FilePath", $InputFileName.DirectoryName) | Out-Null
    $sql.Parameters.AddWithValue("@MessageErr", $retVal.stderr.ToString()) | Out-Null
    $sql.Parameters.AddWithValue("@MessageOut", $retVal.stdout.ToString()) | Out-Null
    $sql.ExecuteNonQuery() | Out-Null
    $sql.Dispose()
}


$sql.Dispose()
$con.Close()