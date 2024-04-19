Add-Type -Path 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\System.Data.SQLite.dll' 
$con = New-Object -TypeName System.Data.SQLite.SQLiteConnection 
$con.ConnectionString = "Data Source=X:\files_db_DiskV.sqlite"
$con.Open()
$sql = $con.CreateCommand()
$sql.CommandText = 'SELECT * FROM files WHERE FileName="2x01 Valley of the Shadow [ОРТ]+[ENG].mkv"'
$sql.CommandType = [System.Data.CommandType]::Text 
$DBReader = $sql.ExecuteReader()  
if ($DBReader.HasRows) {
    ForEach ($r in $DBReader) {
        Write-Host $r.Item('FileName')
    }
}
$sql.Dispose()
$con.Close()
$con.Dispose()