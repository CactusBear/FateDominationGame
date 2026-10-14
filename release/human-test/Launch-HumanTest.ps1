# Template only: not validated with a real human-test package.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][ValidateSet('client', 'server', 'signaling')][string]$Role)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$stage = 'PRECHECK'
$receipt = $null
$exitCode = 2

function Assert-SafePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $drive = [IO.Path]::GetPathRoot($full)
    # Refuse system-drive and UNC storage; never follow junctions/symlinks.
    if ($drive -notmatch '^[A-Za-z]:\\$' -or
        $drive.TrimEnd('\') -ieq $env:SystemDrive) { throw 'UNSAFE_STORAGE' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'REDIRECTED_STORAGE'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor.TrimEnd('\'))
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    # Quoted Windows argv and the printable command use this restricted alphabet.
    if ($full -match '["\r\n%&|<>^!]') { throw 'UNSAFE_PATH_CHARACTERS' }
    return $full
}

function Same-Path([string]$Left, [string]$Right) {
    if ([string]::IsNullOrWhiteSpace($Left)) { return $false }
    try { return [IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq $Right.TrimEnd('\') }
    catch { return $false }
}

function Write-Receipt([string]$Line) {
    Write-Host $Line
    if ($script:receipt) { Add-Content -LiteralPath $script:receipt -Value $Line -Encoding UTF8 }
}

try {
    $roleDirectory = Assert-SafePath $PSScriptRoot
    $packageRoot = Assert-SafePath ([IO.Path]::GetDirectoryName($roleDirectory))
    $stage = 'PROFILE'
    $profile = $Role
    if ($Role -eq 'client') {
        $hostRoot = Join-Path $packageRoot 'test-users\host'
        $guestRoot = Join-Path $packageRoot 'test-users\guest'
        if (-not [string]::IsNullOrEmpty($env:FD_CLIENT_PROFILE)) {
            if ($env:FD_CLIENT_PROFILE -cnotin @('host', 'guest')) { throw 'INVALID_PROFILE' }
            $profile = $env:FD_CLIENT_PROFILE
        } else {
            $hostApp = Same-Path $env:APPDATA (Join-Path $hostRoot 'appdata')
            $hostLocal = Same-Path $env:LOCALAPPDATA (Join-Path $hostRoot 'localappdata')
            $guestApp = Same-Path $env:APPDATA (Join-Path $guestRoot 'appdata')
            $guestLocal = Same-Path $env:LOCALAPPDATA (Join-Path $guestRoot 'localappdata')
            if ($hostApp -and $hostLocal) { $profile = 'host' }
            elseif ($guestApp -and $guestLocal) { $profile = 'guest' }
            elseif ($hostApp -or $hostLocal -or $guestApp -or $guestLocal) { throw 'MIXED_PROFILE' }
            else {
                $profile = Read-Host 'Client identity directory (host or guest; not a password)'
                if ($profile -cnotin @('host', 'guest')) { throw 'INVALID_PROFILE' }
            }
        }
    }
    $userRoot = Assert-SafePath (Join-Path $packageRoot ('test-users\' + $profile))
    $appData = Assert-SafePath (Join-Path $userRoot 'appdata')
    $localData = Assert-SafePath (Join-Path $userRoot 'localappdata')
    $tempData = Assert-SafePath (Join-Path $userRoot 'temp')
    $logDirectory = Assert-SafePath (Join-Path $userRoot 'launcher-evidence')

    $stage = 'BINARY_OR_CONFIG'
    $fileNames = @{ client = 'FateDomination.exe'; server = 'FateServer.exe'; signaling = 'FateSignaling.exe' }
    $binary = Assert-SafePath (Join-Path $roleDirectory $fileNames[$Role])
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw 'BINARY_MISSING' }
    $launchArguments = @()
    if ($Role -ne 'client') {
        $configName = if ($Role -eq 'server') { 'server.cfg' } else { 'signaling.json' }
        $configPath = Assert-SafePath (Join-Path $roleDirectory $configName)
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'CONFIG_MISSING' }
        # Existence only: never read, log or modify deployment configuration contents.
        $flag = if ($Role -eq 'server') { '--server-gateway' } else { '--server-signaling' }
        $launchArguments = @('--headless', '--', $flag, '--config', $configPath)
    }

    $stage = 'DIRECTORIES'
    foreach ($directory in @($appData, $localData, $tempData, $logDirectory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        Assert-SafePath $directory | Out-Null
    }
    $env:APPDATA = $appData
    $env:LOCALAPPDATA = $localData
    $env:TEMP = $tempData
    $env:TMP = $tempData
    $env:TMPDIR = $tempData
    $receipt = Join-Path $logDirectory (([Guid]::NewGuid().ToString('N')) + '.log')
    $quotedArguments = @($launchArguments | ForEach-Object { '"' + $_ + '"' })
    $argumentLine = $quotedArguments -join ' '
    Write-Receipt 'TEMPLATE_NOT_REAL_PACKAGE_VERIFIED'
    Write-Receipt ('ROLE=' + $Role + ' PROFILE=' + $profile)
    Write-Receipt ('WORKING_DIRECTORY="' + $roleDirectory + '"')
    Write-Receipt ('APPDATA="' + $appData + '"')
    Write-Receipt ('LOCALAPPDATA="' + $localData + '"')
    Write-Receipt ('TEMP="' + $tempData + '"')
    Write-Receipt ('COMMAND="' + $binary + '" ' + $argumentLine)
    # No readiness deadline, forced kill, background detach, config dump or stdout harvesting.
    # Windows PowerShell must wait explicitly even for a GUI executable.
    $stage = 'PROCESS'
    $start = @{ FilePath = $binary; WorkingDirectory = $roleDirectory; Wait = $true;
                PassThru = $true; NoNewWindow = $true }
    if ($launchArguments.Count -gt 0) { $start.ArgumentList = $argumentLine }
    $process = Start-Process @start
    $exitCode = $process.ExitCode
    if ($null -eq $exitCode) { throw 'EXIT_CODE_UNAVAILABLE' }
    Write-Receipt ('PROCESS_ID=' + $process.Id)
    Write-Receipt ('EXIT_CODE=' + $exitCode)
} catch {
    # Do not print exception/argument/config contents: they may contain private material.
    Write-Host ('LAUNCHER_ERROR_STAGE=' + $stage)
    if ($receipt) {
        try { Add-Content -LiteralPath $receipt -Value ('LAUNCHER_ERROR_STAGE=' + $stage) -Encoding UTF8 }
        catch { Write-Host 'LAUNCHER_RECEIPT_WRITE_FAILED' }
    }
    $exitCode = 2
}
Write-Host ('LAUNCHER_EXIT_CODE=' + $exitCode)
exit $exitCode
