[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\grill-powers'),
    [string]$DiscoveryRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agents\skills'),
    [string]$MattSourceRoot,
    [string]$SuperpowersSourceRoot,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent $scriptRoot
$configRoot = Join-Path $repositoryRoot 'config'
$sourcesLockPath = Join-Path $configRoot 'sources.lock.json'
$selectionPath = Join-Path $configRoot 'skill-selection.json'
$originalSkillSource = Join-Path $repositoryRoot 'skills\grill-powers'

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $candidateFull = (Resolve-FullPath -Path $Candidate) + '\'
    $parentFull = (Resolve-FullPath -Path $Parent) + '\'
    $candidateFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePointInExistingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $current = Resolve-FullPath -Path $Path
    while ($current) {
        $item = Get-PathItem -Path $current
        if ($null -ne $item -and
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            throw "$Label cannot traverse a reparse point: $current"
        }
        $parent = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parent) {
            break
        }
        $current = $parent.FullName
    }
}

function Get-PathItem {
    param([Parameter(Mandatory = $true)][string]$Path)

    Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Assert-PathAvailable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($null -ne (Get-PathItem -Path $Path)) {
        throw "Refusing to overwrite existing path: $Path"
    }
}

function Assert-File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Label`: $Path"
    }
}

function Assert-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Missing $Label`: $Path"
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingTree
    )

    $gitArguments = @()
    if ($WorkingTree) {
        $safePath = (Resolve-FullPath -Path $WorkingTree).Replace('\', '/')
        $gitArguments += @('-c', "safe.directory=$safePath")
    }
    $gitArguments += $Arguments

    $output = @(& git @gitArguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $rendered = ($output | Out-String).Trim()
        throw "Git command failed (git $($Arguments -join ' ')): $rendered"
    }
    ($output | Out-String).Trim()
}

function Get-SkillSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)]$SourceConfig,
        [Parameter(Mandatory = $true)]$SelectionConfig,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $relativePath = $SkillName
    if ($SelectionConfig.PSObject.Properties.Name -contains 'paths') {
        $pathProperty = $SelectionConfig.paths.PSObject.Properties[$SkillName]
        if ($null -eq $pathProperty) {
            throw "Missing source-path mapping for skill: $SkillName"
        }
        $relativePath = [string]$pathProperty.Value
    }
    Join-Path (Join-Path $SourceRoot ([string]$SourceConfig.skillsDirectory)) $relativePath
}

function Assert-GitCheckout {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)]$SourceConfig,
        [Parameter(Mandatory = $true)]$SelectionConfig
    )

    $sourceFull = Resolve-FullPath -Path $SourceRoot
    Assert-Directory -Path $sourceFull -Label "$($SourceConfig.name) source directory"
    if ($null -eq (Get-PathItem -Path (Join-Path $sourceFull '.git'))) {
        throw "Source is not a complete Git checkout: $sourceFull"
    }

    $actualCommit = Invoke-Git -WorkingTree $sourceFull -Arguments @('-C', $sourceFull, 'rev-parse', 'HEAD')
    if (-not $actualCommit.Equals([string]$SourceConfig.commit, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Source commit mismatch for $($SourceConfig.name). Expected $($SourceConfig.commit); found $actualCommit"
    }

    $status = Invoke-Git -WorkingTree $sourceFull -Arguments @('-C', $sourceFull, 'status', '--porcelain', '--untracked-files=all')
    if ($status) {
        throw "Source checkout contains local changes: $sourceFull"
    }

    Assert-File -Path (Join-Path $sourceFull ([string]$SourceConfig.licenseFile)) -Label "$($SourceConfig.name) license"
    foreach ($skillName in @($SelectionConfig.active) + @($SelectionConfig.inactive)) {
        $skillRoot = Get-SkillSourcePath `
            -SourceRoot $sourceFull `
            -SourceConfig $SourceConfig `
            -SelectionConfig $SelectionConfig `
            -SkillName $skillName
        Assert-File -Path (Join-Path $skillRoot 'SKILL.md') -Label "$($SourceConfig.name) skill $skillName"
    }
}

function Copy-LocalCheckout {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Copy-Item -LiteralPath (Resolve-FullPath -Path $SourceRoot) -Destination $Destination -Recurse -Force
}

function Get-RemoteCheckout {
    param(
        [Parameter(Mandatory = $true)]$SourceConfig,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination | Out-Null
    [void](Invoke-Git -Arguments @('init', '--quiet', $Destination))
    [void](Invoke-Git -WorkingTree $Destination -Arguments @('-C', $Destination, 'remote', 'add', 'origin', [string]$SourceConfig.repository))
    [void](Invoke-Git -WorkingTree $Destination -Arguments @('-C', $Destination, 'fetch', '--quiet', '--depth', '1', 'origin', [string]$SourceConfig.commit))
    [void](Invoke-Git -WorkingTree $Destination -Arguments @('-C', $Destination, 'checkout', '--quiet', '--detach', [string]$SourceConfig.commit))
}

function New-DirectoryJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )

    Assert-PathAvailable -Path $Path
    Assert-Directory -Path $Target -Label 'junction target'
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
}

function Remove-DirectoryJunction {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-PathItem -Path $Path
    if ($null -eq $item) {
        return
    }
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to remove a non-junction path during rollback: $Path"
    }
    [System.IO.Directory]::Delete($item.FullName, $false)
}

function Remove-InstallTree {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Selection
    )

    foreach ($skillName in @($Selection.mattpocock.active)) {
        Remove-DirectoryJunction -Path (Join-Path $Path "routing\mattpocock\$skillName")
    }
    foreach ($skillName in @($Selection.superpowers.active)) {
        Remove-DirectoryJunction -Path (Join-Path $Path "routing\superpowers\$skillName")
    }
    foreach ($supportPath in @($Selection.superpowers.supportPaths)) {
        Remove-DirectoryJunction -Path (Join-Path $Path "routing\superpowers\$supportPath")
    }

    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to recursively remove an install-root junction: $Path"
        }
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Get-FileHashRecords {
    param([Parameter(Mandatory = $true)][string]$Root)

    $fullRoot = Resolve-FullPath -Path $Root
    @(
        Get-ChildItem -LiteralPath $fullRoot -File -Recurse |
            Sort-Object -Property FullName |
            ForEach-Object {
                [PSCustomObject]@{
                    path = $_.FullName.Substring($fullRoot.Length).TrimStart('\').Replace('\', '/')
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
    )
}

Assert-File -Path $sourcesLockPath -Label 'source lock'
Assert-File -Path $selectionPath -Label 'skill selection config'
Assert-File -Path (Join-Path $originalSkillSource 'SKILL.md') -Label 'GrillPowers skill'
Assert-File -Path (Join-Path $scriptRoot 'verify.ps1') -Label 'verification script'

$sourcesLock = Get-Content -LiteralPath $sourcesLockPath -Raw | ConvertFrom-Json
$selection = Get-Content -LiteralPath $selectionPath -Raw | ConvertFrom-Json
if ($sourcesLock.schemaVersion -ne 1 -or $selection.schemaVersion -ne 1) {
    throw 'Unsupported GrillPowers config schema.'
}
foreach ($source in @($sourcesLock.sources.mattpocock, $sourcesLock.sources.superpowers)) {
    if (-not ([string]$source.commit -match '^[0-9a-f]{40}$')) {
        throw "Invalid pinned commit for $($source.name): $($source.commit)"
    }
}

$installFull = Resolve-FullPath -Path $InstallRoot
$discoveryFull = Resolve-FullPath -Path $DiscoveryRoot
Assert-NoReparsePointInExistingPath -Path $installFull -Label 'InstallRoot'
Assert-NoReparsePointInExistingPath -Path $discoveryFull -Label 'DiscoveryRoot'
Assert-NoReparsePointInExistingPath -Path $originalSkillSource -Label 'Packaged GrillPowers skill path'
if ($installFull.Equals($discoveryFull, [System.StringComparison]::OrdinalIgnoreCase) -or
    (Test-PathWithin -Candidate $installFull -Parent $discoveryFull) -or
    (Test-PathWithin -Candidate $discoveryFull -Parent $installFull)) {
    throw 'InstallRoot and DiscoveryRoot must be separate, non-nested paths.'
}
if ((Test-PathWithin -Candidate $installFull -Parent $originalSkillSource) -or
    $installFull.Equals((Resolve-FullPath -Path $originalSkillSource), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'InstallRoot cannot be inside the packaged GrillPowers skill.'
}
if ((Test-PathWithin -Candidate $discoveryFull -Parent $originalSkillSource) -or
    $discoveryFull.Equals((Resolve-FullPath -Path $originalSkillSource), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'DiscoveryRoot cannot be inside the packaged GrillPowers skill.'
}

Assert-PathAvailable -Path $installFull
$discoveryItem = Get-PathItem -Path $discoveryFull
if ($null -ne $discoveryItem -and -not $discoveryItem.PSIsContainer) {
    throw "DiscoveryRoot must be a directory: $discoveryFull"
}

$discoveryPaths = @{
    original = Join-Path $discoveryFull ([string]$selection.discoveryLinks.original)
    mattpocock = Join-Path $discoveryFull ([string]$selection.discoveryLinks.mattpocock)
    superpowers = Join-Path $discoveryFull ([string]$selection.discoveryLinks.superpowers)
}
foreach ($path in $discoveryPaths.Values) {
    Assert-PathAvailable -Path $path
}

$localSourceMap = @{
    mattpocock = $MattSourceRoot
    superpowers = $SuperpowersSourceRoot
}
$sourceConfigMap = @{
    mattpocock = $sourcesLock.sources.mattpocock
    superpowers = $sourcesLock.sources.superpowers
}
$selectionMap = @{
    mattpocock = $selection.mattpocock
    superpowers = $selection.superpowers
}

foreach ($sourceKey in @('mattpocock', 'superpowers')) {
    $localSource = [string]$localSourceMap[$sourceKey]
    if ($localSource) {
        $localFull = Resolve-FullPath -Path $localSource
        Assert-NoReparsePointInExistingPath -Path $localFull -Label "$($sourceConfigMap[$sourceKey].name) source path"
        if ((Test-PathWithin -Candidate $installFull -Parent $localFull) -or
            $installFull.Equals($localFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "InstallRoot cannot be inside local source checkout: $localFull"
        }
        if ((Test-PathWithin -Candidate $discoveryFull -Parent $localFull) -or
            $discoveryFull.Equals($localFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "DiscoveryRoot cannot be inside local source checkout: $localFull"
        }
        Assert-GitCheckout -SourceRoot $localFull -SourceConfig $sourceConfigMap[$sourceKey] -SelectionConfig $selectionMap[$sourceKey]
        $localSourceMap[$sourceKey] = $localFull
    }
}

if ($WhatIf) {
    [PSCustomObject]@{
        status = 'planned'
        mode = 'WhatIf'
        installRoot = $installFull
        discoveryRoot = $discoveryFull
        sourceCommits = [ordered]@{
            mattpocock = [string]$sourcesLock.sources.mattpocock.commit
            superpowers = [string]$sourcesLock.sources.superpowers.commit
        }
        discoveryLinks = $discoveryPaths
    } | ConvertTo-Json -Depth 5
    return
}

$installParent = Split-Path -Parent $installFull
$stagingRoot = Join-Path $installParent ('.' + (Split-Path -Leaf $installFull) + '.staging.' + [guid]::NewGuid().ToString('N'))
$createdInstallRoot = $false
$createdDiscoveryLinks = [System.Collections.Generic.List[string]]::new()

try {
    if (-not (Test-Path -LiteralPath $installParent -PathType Container)) {
        New-Item -ItemType Directory -Path $installParent -Force | Out-Null
    }
    New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'sources') -Force | Out-Null

    foreach ($sourceKey in @('mattpocock', 'superpowers')) {
        $sourceConfig = $sourceConfigMap[$sourceKey]
        $destination = Join-Path $stagingRoot "sources\$($sourceConfig.checkoutDirectory)"
        $localSource = [string]$localSourceMap[$sourceKey]
        if ($localSource) {
            Copy-LocalCheckout -SourceRoot $localSource -Destination $destination
        }
        else {
            Get-RemoteCheckout -SourceConfig $sourceConfig -Destination $destination
        }
        Assert-GitCheckout -SourceRoot $destination -SourceConfig $sourceConfig -SelectionConfig $selectionMap[$sourceKey]
    }

    New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'skills') -Force | Out-Null
    Copy-Item -LiteralPath $originalSkillSource -Destination (Join-Path $stagingRoot 'skills\grill-powers') -Recurse -Force
    Copy-Item -LiteralPath $configRoot -Destination (Join-Path $stagingRoot 'config') -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination (Join-Path $stagingRoot 'scripts\install.ps1')
    Copy-Item -LiteralPath (Join-Path $scriptRoot 'verify.ps1') -Destination (Join-Path $stagingRoot 'scripts\verify.ps1')

    # Directory.Move fails when the destination appeared after preflight. Unlike
    # Move-Item, it cannot nest staging inside a raced-in directory and then
    # make rollback treat that unrelated directory as installer-owned.
    [System.IO.Directory]::Move($stagingRoot, $installFull)
    $createdInstallRoot = $true

    $mattInstall = Join-Path $installFull "sources\$($sourcesLock.sources.mattpocock.checkoutDirectory)"
    $superpowersInstall = Join-Path $installFull "sources\$($sourcesLock.sources.superpowers.checkoutDirectory)"
    $mattRouting = Join-Path $installFull 'routing\mattpocock'
    $superpowersRouting = Join-Path $installFull 'routing\superpowers'
    New-Item -ItemType Directory -Path $mattRouting -Force | Out-Null
    New-Item -ItemType Directory -Path $superpowersRouting -Force | Out-Null

    foreach ($skillName in @($selection.mattpocock.active)) {
        $skillTarget = Get-SkillSourcePath `
            -SourceRoot $mattInstall `
            -SourceConfig $sourcesLock.sources.mattpocock `
            -SelectionConfig $selection.mattpocock `
            -SkillName $skillName
        New-DirectoryJunction `
            -Path (Join-Path $mattRouting $skillName) `
            -Target $skillTarget
    }
    foreach ($skillName in @($selection.superpowers.active)) {
        New-DirectoryJunction `
            -Path (Join-Path $superpowersRouting $skillName) `
            -Target (Join-Path $superpowersInstall "skills\$skillName")
    }
    foreach ($supportPath in @($selection.superpowers.supportPaths)) {
        $supportParent = Split-Path -Parent (Join-Path $superpowersRouting $supportPath)
        New-Item -ItemType Directory -Path $supportParent -Force | Out-Null
        New-DirectoryJunction `
            -Path (Join-Path $superpowersRouting $supportPath) `
            -Target (Join-Path $superpowersInstall "skills\$supportPath")
    }

    if (-not (Test-Path -LiteralPath $discoveryFull -PathType Container)) {
        New-Item -ItemType Directory -Path $discoveryFull -Force | Out-Null
    }
    New-DirectoryJunction -Path $discoveryPaths.original -Target (Join-Path $installFull 'skills\grill-powers')
    $createdDiscoveryLinks.Add($discoveryPaths.original)
    New-DirectoryJunction -Path $discoveryPaths.mattpocock -Target $mattRouting
    $createdDiscoveryLinks.Add($discoveryPaths.mattpocock)
    New-DirectoryJunction -Path $discoveryPaths.superpowers -Target $superpowersRouting
    $createdDiscoveryLinks.Add($discoveryPaths.superpowers)

    $manifest = [ordered]@{
        schemaVersion = 1
        profile = [string]$selection.profile
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        installRoot = $installFull
        discoveryRoot = $discoveryFull
        sourceCommits = [ordered]@{
            mattpocock = [string]$sourcesLock.sources.mattpocock.commit
            superpowers = [string]$sourcesLock.sources.superpowers.commit
        }
        discoveryLinks = [ordered]@{
            original = $discoveryPaths.original
            mattpocock = $discoveryPaths.mattpocock
            superpowers = $discoveryPaths.superpowers
        }
        originalSkillFiles = @(Get-FileHashRecords -Root (Join-Path $installFull 'skills\grill-powers'))
        configurationFiles = @(Get-FileHashRecords -Root (Join-Path $installFull 'config'))
        managementFiles = @(Get-FileHashRecords -Root (Join-Path $installFull 'scripts'))
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $installFull 'install-manifest.json') -Encoding UTF8

    & (Join-Path $scriptRoot 'verify.ps1') -InstallRoot $installFull -DiscoveryRoot $discoveryFull | Out-Null

    [PSCustomObject]@{
        status = 'installed'
        installRoot = $installFull
        discoveryRoot = $discoveryFull
        sourceCommits = $manifest.sourceCommits
        discoveryLinks = $manifest.discoveryLinks
    } | ConvertTo-Json -Depth 5
}
catch {
    $originalError = $_
    foreach ($createdLink in @($createdDiscoveryLinks) | Sort-Object -Descending) {
        Remove-DirectoryJunction -Path $createdLink
    }
    if ($createdInstallRoot -and (Test-Path -LiteralPath $installFull)) {
        Remove-InstallTree -Path $installFull -Selection $selection
    }
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    # Parent scaffolding is deliberately retained. Its creation can race with
    # another process, so rollback never claims ownership of those directories.
    throw $originalError
}
