#requires -Version 5.1
<#
.SYNOPSIS
  Create (or reuse) a GitHub Release for an existing tag and upload one zip asset.
.NOTES
  Token: GITHUB_TOKEN env var only. PowerShell 5.1 compatible.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'BrenoBertucci/Terrarium',
    [string]$Tag = 'v1.18.0-mobile',
    [string]$Zip = 'publish-zip/TERRARIUM-1.18.0-mobile.zip',
    [string]$NotesFile = 'publish/BrenoBertucci@TERRARIUM/description.md',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# GitHub requires TLS 1.2+; older Windows defaults may still negotiate TLS 1.0.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Token (env only; never prompt, never write, never echo) ---
$token = $env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host 'GITHUB_TOKEN is not set.'
    Write-Host 'Set it for this session, then re-run:'
    Write-Host '  $env:GITHUB_TOKEN = ''ghp_your_token_here'''
    Write-Host 'Or permanently (User scope):'
    Write-Host '  [Environment]::SetEnvironmentVariable(''GITHUB_TOKEN'', ''ghp_your_token_here'', ''User'')'
    exit 1
}

$apiBase = 'https://api.github.com'
$headers = @{
    'Authorization' = "Bearer $token"
    'Accept'        = 'application/vnd.github+json'
    'User-Agent'    = 'Terrarium-publish_release.ps1'
}

function Write-ApiCall {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Extra
    )
    if ($Extra) {
        Write-Host ("[DryRun] {0} {1}  ({2})" -f $Method, $Uri, $Extra)
    }
    else {
        Write-Host ("[DryRun] {0} {1}" -f $Method, $Uri)
    }
}

function Invoke-GhApi {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Body = $null,
        [string]$InFile = $null,
        [string]$ContentType = $null,
        # When true, HTTP 404 is returned as $null instead of throwing.
        [switch]$AllowNotFound
    )

    $params = @{
        Method  = $Method
        Uri     = $Uri
        Headers = $headers
    }

    if ($null -ne $Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Compress -Depth 10)
        $params['ContentType'] = 'application/json'
    }

    if ($InFile) {
        $params['InFile'] = $InFile
        if ($ContentType) {
            $params['ContentType'] = $ContentType
        }
    }

    try {
        return Invoke-RestMethod @params
    }
    catch {
        $resp = $_.Exception.Response
        if ($AllowNotFound -and $null -ne $resp) {
            $code = [int]$resp.StatusCode
            if ($code -eq 404) {
                return $null
            }
        }
        # Surface GitHub error body when available (status + message).
        $detail = $_.Exception.Message
        if ($null -ne $resp) {
            try {
                $stream = $resp.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $text = $reader.ReadToEnd()
                    $reader.Close()
                    if (-not [string]::IsNullOrWhiteSpace($text)) {
                        $detail = $text
                    }
                }
            }
            catch {
                # keep $detail from Exception.Message
            }
        }
        throw ("GitHub API {0} {1} failed: {2}" -f $Method, $Uri, $detail)
    }
}

# --- Resolve paths relative to repo root (script lives in tools/) ---
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $repoRoot) {
    $repoRoot = (Get-Location).Path
}

function Resolve-RepoPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path $repoRoot $Path)
}

$zipPath = Resolve-RepoPath -Path $Zip
$notesPath = Resolve-RepoPath -Path $NotesFile

# --- Validate local files ---
# Write-Host, not Write-Error: $ErrorActionPreference is 'Stop' at the top of
# this script, so Write-Error throws a terminating error and the `exit 1`
# under it never runs -- a missing zip would come back as a stack trace
# instead of the one line that says which file is missing.
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    Write-Host ("Zip not found: {0}" -f $zipPath)
    Write-Host 'Build it first, then re-run.'
    exit 1
}
if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
    Write-Host ("Notes file not found: {0}" -f $notesPath)
    exit 1
}

$assetName = [System.IO.Path]::GetFileName($zipPath)
$notesBody = [System.IO.File]::ReadAllText($notesPath)

Write-Host ("Repo:  {0}" -f $Repo)
Write-Host ("Tag:   {0}" -f $Tag)
Write-Host ("Zip:   {0}" -f $zipPath)
Write-Host ("Notes: {0}" -f $notesPath)
if ($DryRun) {
    Write-Host 'Mode:  DryRun (no uploads, no mutations)'
}
Write-Host ''

# --- Validate tag exists on remote ---
# GET /repos/{owner}/{repo}/git/ref/tags/{tag}
$tagRefUri = "{0}/repos/{1}/git/ref/tags/{2}" -f $apiBase, $Repo, $Tag
Write-Host ("Checking tag ref: GET {0}" -f $tagRefUri)
if ($DryRun) {
    Write-ApiCall -Method 'GET' -Uri $tagRefUri
    # Still need a real check so DryRun fails early if the tag is missing.
    $tagRef = Invoke-GhApi -Method 'GET' -Uri $tagRefUri -AllowNotFound
}
else {
    $tagRef = Invoke-GhApi -Method 'GET' -Uri $tagRefUri -AllowNotFound
}
if ($null -eq $tagRef) {
    # Same reason as the file checks above: Write-Error would throw here.
    Write-Host ("Tag '{0}' not found on remote for {1}." -f $Tag, $Repo)
    Write-Host ("  git push origin {0}" -f $Tag)
    exit 1
}
Write-Host ("Tag OK: {0}" -f $tagRef.ref)

# --- Get existing release or create one ---
# GET /repos/{owner}/{repo}/releases/tags/{tag}
$releaseByTagUri = "{0}/repos/{1}/releases/tags/{2}" -f $apiBase, $Repo, $Tag
Write-Host ("Looking up release: GET {0}" -f $releaseByTagUri)
if ($DryRun) {
    Write-ApiCall -Method 'GET' -Uri $releaseByTagUri
}
$release = Invoke-GhApi -Method 'GET' -Uri $releaseByTagUri -AllowNotFound

if ($null -ne $release) {
    Write-Host ("Reusing existing release id={0}" -f $release.id)
}
else {
    # POST /repos/{owner}/{repo}/releases
    $createUri = "{0}/repos/{1}/releases" -f $apiBase, $Repo
    $createBody = @{
        tag_name   = $Tag
        name       = $Tag
        body       = $notesBody
        draft      = $false
        prerelease = $false
    }
    if ($DryRun) {
        Write-ApiCall -Method 'POST' -Uri $createUri -Extra 'create release'
        Write-Host ("[DryRun] body: tag_name={0}, name={1}, draft=false, prerelease=false, body from {2}" -f $Tag, $Tag, $notesPath)
        # DryRun must not mutate: stop after describing create + would-be upload.
        $uploadTemplate = 'https://uploads.github.com/repos/{0}/releases/{{id}}/assets{{?name,label}}' -f $Repo
        $uploadUri = $uploadTemplate.Replace('{?name,label}', ("?name={0}" -f [Uri]::EscapeDataString($assetName)))
        Write-ApiCall -Method 'POST' -Uri $uploadUri -Extra ("upload InFile={0} ContentType=application/zip" -f $zipPath)
        Write-Host ''
        Write-Host ("[DryRun] Would publish release for tag {0} (no html_url yet — release not created)." -f $Tag)
        exit 0
    }
    Write-Host ("Creating release: POST {0}" -f $createUri)
    $release = Invoke-GhApi -Method 'POST' -Uri $createUri -Body $createBody
    Write-Host ("Created release id={0}" -f $release.id)
}

# --- Replace asset if same file name already present ---
# upload_url looks like: https://uploads.github.com/.../assets{?name,label}
$existingAsset = $null
if ($null -ne $release.assets) {
    foreach ($a in $release.assets) {
        if ($a.name -eq $assetName) {
            $existingAsset = $a
            break
        }
    }
}

if ($null -ne $existingAsset) {
    $deleteUri = "{0}/repos/{1}/releases/assets/{2}" -f $apiBase, $Repo, $existingAsset.id
    if ($DryRun) {
        Write-ApiCall -Method 'DELETE' -Uri $deleteUri -Extra ("remove existing asset '{0}'" -f $assetName)
    }
    else {
        Write-Host ("Deleting existing asset '{0}' (id={1}): DELETE {2}" -f $assetName, $existingAsset.id, $deleteUri)
        # DELETE often returns empty body; IgnoreResponse body via RestMethod is fine.
        Invoke-GhApi -Method 'DELETE' -Uri $deleteUri | Out-Null
    }
}

# Strip GitHub's URI template suffix and append the asset name query.
# Example: .../assets{?name,label} -> .../assets?name=foo.zip
$uploadBase = $release.upload_url
if ($uploadBase -match '\{') {
    $uploadBase = $uploadBase.Substring(0, $uploadBase.IndexOf('{'))
}
$uploadUri = "{0}?name={1}" -f $uploadBase, [Uri]::EscapeDataString($assetName)

if ($DryRun) {
    Write-ApiCall -Method 'POST' -Uri $uploadUri -Extra ("upload InFile={0} ContentType=application/zip" -f $zipPath)
    Write-Host ''
    if ($release.html_url) {
        Write-Host ("[DryRun] Release URL: {0}" -f $release.html_url)
    }
    else {
        Write-Host ("[DryRun] Would upload to existing/new release for tag {0}." -f $Tag)
    }
    exit 0
}

Write-Host ("Uploading asset: POST {0}" -f $uploadUri)
Write-Host ("  InFile: {0}" -f $zipPath)
$uploaded = Invoke-GhApi -Method 'POST' -Uri $uploadUri -InFile $zipPath -ContentType 'application/zip'
Write-Host ("Uploaded asset id={0} name={1}" -f $uploaded.id, $uploaded.name)

Write-Host ''
Write-Host $release.html_url
exit 0
