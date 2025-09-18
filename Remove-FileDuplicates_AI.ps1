function Remove-DuplicateFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$CacheDatabase = "X:\temp2\FileDuplicatesCache.db",
        [ValidateSet("Oldest", "LongestPath", "AlphabeticalName", "ShortestName")]
        [string]$Priority = "LongestPath",
        [switch]$Recurse,
        [switch]$Quiet,
        [int]$BatchSize = 50000
    )

    $sqliteDllPath = "X:\temp2\System.Data.SQLite.dll"
    Add-Type -Path $sqliteDllPath -ErrorAction Stop
    
    function Open-SQLiteConnection {
        param($dbPath)
        try {
            $conn = [System.Data.SQLite.SQLiteConnection]::new("Data Source=$dbPath;Version=3;")
            $conn.Open()
            return $conn
        }
        catch {
            if (-not $Quiet) { Write-Error "Connection failed: $_" }
            return $null
        }
    }

    function Invoke-SQLiteCommand {
        param($connection, $query, $parameters = @{})
        try {
            $command = $connection.CreateCommand()
            $command.CommandText = $query
            foreach ($key in $parameters.Keys) {
                [void]$command.Parameters.AddWithValue("@$key", $parameters[$key])
            }
            [void]$command.ExecuteNonQuery()
        }
        catch {
            if (-not $Quiet) { Write-Warning "SQL error: $_" }
        }
    }

    function Get-SQLiteData {
        param($connection, $query, $parameters = @{})
        try {
            $command = $connection.CreateCommand()
            $command.CommandText = $query
            foreach ($key in $parameters.Keys) {
                [void]$command.Parameters.AddWithValue("@$key", $parameters[$key])
            }

            $adapter = [System.Data.SQLite.SQLiteDataAdapter]::new($command)
            $dataSet = [System.Data.DataSet]::new()
            [void]$adapter.Fill($dataSet)
            return $dataSet.Tables[0]
        }
        catch {
            if (-not $Quiet) { Write-Warning "SQL query failed: $_" }
            return $null
        }
    }

    if (-not (Test-Path -Path $Path -PathType Container)) {
        if (-not $Quiet) { Write-Error "Directory does not exist: $Path" }
        return
    }

    $connection = Open-SQLiteConnection $CacheDatabase
    if (-not $connection) { return }

    Invoke-SQLiteCommand $connection @"
    CREATE TABLE IF NOT EXISTS FileHashes (
        FilePath TEXT PRIMARY KEY,
        FileSize INTEGER,
        LastWriteTime TEXT,
        MD5Hash TEXT
    );
"@

    # Загружаем все данные из БД в память
    $cacheTable = Get-SQLiteData $connection "SELECT FilePath, LastWriteTime FROM FileHashes"
    $cache = @{}
    if ($cacheTable -and $cacheTable.Count -gt 0) {
        foreach ($row in $cacheTable) {
            $cache[$row.FilePath] = [datetime]::Parse($row.LastWriteTime)
        }
    }

    $allFiles = @(Get-ChildItem -Path $Path -File -Recurse:$Recurse.IsPresent)
    if (-not $Quiet) { Write-Host "Found $($allFiles.Count) files for processing" -ForegroundColor Cyan }

    # Удаляем отсутствующие файлы из БД
    $existingPaths = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in $allFiles) { [void]$existingPaths.Add($f.FullName) }

    $pathsToRemove = $cache.Keys | Where-Object { -not $existingPaths.Contains($_) }
    if ($pathsToRemove.Count -gt 0) {
        if (-not $Quiet) { Write-Verbose "Removing $($pathsToRemove.Count) stale DB entries" }
        Invoke-SQLiteCommand $connection "BEGIN TRANSACTION"
        foreach ($p in $pathsToRemove) {
            Invoke-SQLiteCommand $connection "DELETE FROM FileHashes WHERE FilePath = @filePath" @{ filePath = $p }
        }
        Invoke-SQLiteCommand $connection "COMMIT"
    }

    $filesToUpdate = [System.Collections.Generic.List[object]]::new()
    $fileCounter = 0

    foreach ($file in $allFiles) {
        $fileCounter++
        if (-not $Quiet) {
            $percentComplete = ($fileCounter / $allFiles.Count) * 100
            Write-Progress -Activity "Analyzing files" -Status "File $fileCounter of $($allFiles.Count)" `
                -CurrentOperation $file.FullName -PercentComplete $percentComplete
        }

        $needsUpdate = $true
        if ($cache.ContainsKey($file.FullName)) {
            $cachedLast = $cache[$file.FullName]
            try {
                $cachedDt = [datetime]::Parse($cachedLast)
                if ($cachedDt -eq $file.LastWriteTime) {
                    $needsUpdate = $false
                }
            } catch { }
        }

        if ($needsUpdate) {
            $hashObj = Get-FileHash -Path $file.FullName -Algorithm MD5 -ErrorAction SilentlyContinue
            if ($hashObj) {
                $filesToUpdate.Add([PSCustomObject]@{
                    FilePath      = $file.FullName
                    FileSize      = $file.Length
                    LastWriteTime = $file.LastWriteTime.ToString("o")
                    MD5Hash       = $hashObj.Hash
                })

                if ($filesToUpdate.Count -ge $BatchSize) {
                    if (-not $Quiet) { Write-Verbose "Writing batch of ${BatchSize} records" }
                    Invoke-SQLiteCommand $connection "BEGIN TRANSACTION"
                    foreach ($item in $filesToUpdate) {
                        Invoke-SQLiteCommand $connection @"
                        INSERT OR REPLACE INTO FileHashes
                            (FilePath, FileSize, LastWriteTime, MD5Hash)
                        VALUES
                            (@filePath, @fileSize, @lastWriteTime, @md5Hash)
"@ @{
                            filePath      = $item.FilePath
                            fileSize      = $item.FileSize
                            lastWriteTime = $item.LastWriteTime
                            md5Hash       = $item.MD5Hash
                        }
                    }
                    Invoke-SQLiteCommand $connection "COMMIT"
                    $filesToUpdate.Clear()
                }
            }
        }
    }

    # Обработка оставшихся файлов
    if ($filesToUpdate.Count -gt 0) {
        if (-not $Quiet) { Write-Verbose "Writing final batch of $($filesToUpdate.Count) records" }
        Invoke-SQLiteCommand $connection "BEGIN TRANSACTION"
        foreach ($item in $filesToUpdate) {
            Invoke-SQLiteCommand $connection @"
            INSERT OR REPLACE INTO FileHashes 
                (FilePath, FileSize, LastWriteTime, MD5Hash)
            VALUES 
                (@filePath, @fileSize, @lastWriteTime, @md5Hash)
"@ @{
                filePath      = $item.FilePath
                fileSize      = $item.FileSize
                lastWriteTime = $item.LastWriteTime
                md5Hash       = $item.MD5Hash
            }
        }
        Invoke-SQLiteCommand $connection "COMMIT"
    }

    if (-not $Quiet) { Write-Progress -Activity "Analyzing files" -Completed }


    $duplicateGroups = Get-SQLiteData $connection @"
    SELECT MD5Hash, COUNT(*) as Count, GROUP_CONCAT(FilePath, '|') as Files
    FROM FileHashes
    GROUP BY MD5Hash
    HAVING COUNT(*) > 1
"@

    $totalDeleted = 0
    $totalSpace = 0
    $deletedFilesCache = [System.Collections.Generic.List[string]]::new()


    $groupCounter = 0
    if ($duplicateGroups -and $duplicateGroups.Rows.Count -gt 0) {
        if (-not $Quiet) {
            Write-Progress -Activity "Processing duplicates" -Status "Preparing..."
        }
        foreach ($group in $duplicateGroups) {
            $groupCounter++

            if (-not $Quiet) {
                $percentComplete = ($groupCounter / $duplicateGroups.Rows.Count) * 100
                Write-Progress -Activity "Processing duplicates" `
                    -Status "Group $groupCounter of $($duplicateGroups.Rows.Count)" `
                    -PercentComplete $percentComplete
            }

            $filePaths = ($group.Files -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

            $files = @()
            $missingNow = [System.Collections.Generic.List[string]]::new()
            foreach ($fp in $filePaths) {
                if (Test-Path $fp) {
                    try {
                        $files += Get-Item -LiteralPath $fp -ErrorAction Stop
                    } catch {
                    }
                } else {
                    $missingNow.Add($fp)
                }
            }

            if ($missingNow.Count -gt 0) {
                if (-not $Quiet) { Write-Verbose "Removing $($missingNow.Count) entries for files missing during processing" }
                Invoke-SQLiteCommand $connection "BEGIN TRANSACTION"
                foreach ($p in $missingNow) {
                    Invoke-SQLiteCommand $connection "DELETE FROM FileHashes WHERE FilePath = @filePath" @{ filePath = $p }
                }
                Invoke-SQLiteCommand $connection "COMMIT"
                if ($files.Count -lt 2) { continue }
            }

            switch ($Priority) {
                "LongestPath" { $sortedFiles = $files | Sort-Object { $_.FullName.Length }, LastWriteTime }
                "AlphabeticalName" { $sortedFiles = $files | Sort-Object Name, LastWriteTime }
                "ShortestName" { $sortedFiles = $files | Sort-Object { $_.Name.Length }, LastWriteTime }
                Default { $sortedFiles = $files | Sort-Object LastWriteTime }
            }

            $filesToDelete = $sortedFiles | Select-Object -SkipLast 1

            foreach ($file in $filesToDelete) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Delete duplicate file")) {
                    if (Test-Path $file.FullName) {
                        try {
                            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                            if (-not $Quiet) { Write-Host "DELETED: $($file.FullName)" -ForegroundColor Red }
                            $totalDeleted++
                            $totalSpace += $file.Length
                            $deletedFilesCache.Add($file.FullName)
                        }
                        catch {
                            if (-not $Quiet) { Write-Warning "Failed to delete $($file.FullName): $_" }
                        }
                    } else {
                        if (-not $Quiet) { Write-Warning "File not found at deletion time: $($file.FullName) - removing DB entry" }
                        Invoke-SQLiteCommand $connection "DELETE FROM FileHashes WHERE FilePath = @filePath" @{ filePath = $file.FullName }
                    }
                }
                else {
                    $totalDeleted++
                    $totalSpace += $file.Length
                }
            }
        }
    }

    if ($deletedFilesCache.Count -gt 0) {
        if (-not $Quiet) { Write-Verbose "Cleaning cache for $($deletedFilesCache.Count) deleted files" }

        Invoke-SQLiteCommand $connection "BEGIN TRANSACTION"
        foreach ($filePath in $deletedFilesCache) {
            Invoke-SQLiteCommand $connection `
                "DELETE FROM FileHashes WHERE FilePath = @filePath" @{
                filePath = $filePath
            }
        }
        Invoke-SQLiteCommand $connection "COMMIT"
    }

    $connection.Close()

    $report = [PSCustomObject]@{
        TotalFilesProcessed  = $allFiles.Count
        DuplicateGroupsFound = if ($duplicateGroups) { $duplicateGroups.Rows.Count } else { 0 }
        DeletedFiles         = $totalDeleted
        SpaceFreedMB         = [math]::Round($totalSpace / 1MB, 2)
        CacheLocation        = $CacheDatabase
    }

    if (-not $Quiet) {
        Write-Host "`n=== Duplicate Cleanup Report ===" -ForegroundColor Green
        $report | Format-List | Out-String | Write-Host
    }

    return $report
}
Write-Host 'Remove-DuplicateFiles...'
Remove-DuplicateFiles -Path 'X:\temp2\xuk\' -Recurse -Verbose -Debug -Confirm:$true