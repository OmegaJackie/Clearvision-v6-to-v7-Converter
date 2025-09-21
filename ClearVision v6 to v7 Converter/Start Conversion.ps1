<#
Start Conversion.ps1
Interactive v6 -> v7 converter (GUI).
Usage: Double-click the .bat which launches this script. The script:
 - Prompts you to select a v6 .theme.css file.
 - Makes a backup copy of the selected v6 file.
 - Prompts whether to create a New v7 file or Overwrite an existing v7 file.
   * New: writes a New file next to the selected v6 with "(Converted)" appended.
   * Overwrite: prompts you to choose an existing v7 file, backs it up, then replaces its first :root block with the generated v7 variables.
 - The generated v7 :root block is produced from the selected v6's CSS variables.
 - The script preserves the remaining contents of any overwritten v7 file (it replaces only the first :root { ... } block).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO

function Select-FileDialog([string]$title='Select a file', [string]$filter='CSS files (*.css)|*.css|All files (*.*)|*.*') {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = $filter
    $ofd.Title = $title
    $ofd.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    $ofd.Multiselect = $false
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $ofd.FileName } else { return $null }
}

function Save-FileDialog([string]$title='Save file as', [string]$defaultName='output.theme.css') {
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'CSS files (*.css)|*.css|All files (*.*)|*.*'
    $sfd.Title = $title
    $sfd.FileName = $defaultName
    $sfd.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $sfd.FileName } else { return $null }
}

function Read-FileRaw([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Write-FileUtf8([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, [System.Text.Encoding]::UTF8)
}

function Extract-RootBlock([string]$cssText) {
    $m = [regex]::Match($cssText, ':\s*root\s*\{')
    if (-not $m.Success) { return $null }
    $start = $m.Index + $m.Length
    $depth = 1
    $i = $start
    while ($i -lt $cssText.Length -and $depth -gt 0) {
        if ($cssText[$i] -eq '{') { $depth++ } elseif ($cssText[$i] -eq '}') { $depth-- }
        $i++
    }
    if ($depth -ne 0) { return $null }
    return $cssText.Substring($start, $i - $start - 1).Trim()
}

function Parse-CSS-Vars([string]$text) {
    $dict = @{}
    $pattern = '(--[\w-]+)\s*:\s*([^;]+);'
    foreach ($m in [regex]::Matches($text, $pattern)) {
        $name = $m.Groups[1].Value.Trim()
        $value = $m.Groups[2].Value.Trim()
        $dict[$name] = $value
    }
    return $dict
}

$V7_FROM_V6_MAP = @{
    '--main-color' = @('--main-color','--accent','--accent-color')
    '--hover-color' = @('--hover-color','--accent-hover')
    '--success-color' = @('--success-color','--green','--ok-color')
    '--danger-color' = @('--danger-color','--error','--red')
    '--url-color' = @('--url-color','--link-color','--main-color')
    '--online-color' = @('--online-color','--status-online')
    '--idle-color' = @('--idle-color','--status-idle')
    '--dnd-color' = @('--dnd-color','--status-dnd')
    '--streaming-color' = @('--streaming-color','--status-streaming')
    '--offline-color' = @('--offline-color','--status-offline','--muted-color')
    '--background-image' = @('--background-image','--bg-image','--background')
    '--background-position' = @('--background-position','--bg-position')
    '--background-size' = @('--background-size','--bg-size')
    '--background-attachment' = @('--background-attachment','--bg-attachment')
    '--background-brightness' = @('--background-brightness','--bg-brightness')
    '--background-contrast' = @('--background-contrast','--bg-contrast')
    '--background-saturation' = @('--background-saturation','--bg-saturation')
    '--background-invert' = @('--background-invert','--bg-invert')
    '--background-grayscale' = @('--background-grayscale','--bg-grayscale')
    '--background-sepia' = @('--background-sepia','--bg-sepia')
    '--background-blur' = @('--background-blur','--bg-blur')
    '--background-overlay' = @('--background-overlay','--bg-overlay')
    '--backdrop-overlay' = @('--backdrop-overlay')
    '--home-icon' = @('--home-icon')
    '--home-size' = @('--home-size')
    '--main-font' = @('--main-font','--font-family')
    '--code-font' = @('--code-font','--mono-font')
    '--text-normal' = @('--text-normal','--normal-text','--text-color')
    '--text-muted' = @('--text-muted','--muted-text')
    '--channel-unread' = @('--channel-unread','--unread-color')
    '--channel-unread-hover' = @('--channel-unread-hover')
    '--channel-color' = @('--channel-color')
    '--channel-text-selected' = @('--channel-text-selected')
    '--muted-color' = @('--muted-color')
    '--channels-width' = @('--channels-width')
    '--members-width' = @('--members-width')
    '--server-unread' = @('--server-unread')
}

function Choose-V6Value($v6vars, $candidates) {
    foreach ($c in $candidates) { if ($v6vars.ContainsKey($c)) { return $v6vars[$c] } }
    return $null
}

function Build-OverrideRootBlock($v6vars) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(':root {') | Out-Null
    foreach ($kv in $V7_FROM_V6_MAP.GetEnumerator()) {
        $v7var = $kv.Key
        $cands = $kv.Value
        $val = Choose-V6Value -v6vars $v6vars -candidates $cands
        if ($null -ne $val) { $lines.Add(('    {0}: {1};' -f $v7var, $val)) | Out-Null }
    }
    $lines.Add('') | Out-Null
    $lines.Add('    /* Original v6 variables (copied to preserve custom values) */') | Out-Null
    foreach ($name in $v6vars.Keys | Sort-Object) {
        if ($V7_FROM_V6_MAP.ContainsKey($name)) { continue }
        $val = $v6vars[$name]
        $lines.Add(('    {0}: {1};' -f $name, $val)) | Out-Null
    }
    $lines.Add('}') | Out-Null
    return ($lines -join "")
}

$standardHeader = @'
/**
 * @name ClearVision V7 for BetterDiscord
 * @author ClearVision Team
 * @version 7.0.1
 * @description Highly customizable theme for BetterDiscord.
 * @source https://github.com/ClearVision/ClearVision-v7
 * @website https://clearvision.github.io
 * @invite dHaSxn3
 */
/* IMPORT CSS */
@import url("https://clearvision.github.io/ClearVision-v7/main.css");
@import url("https://clearvision.github.io/ClearVision-v7/betterdiscord.css");
/* SETTINGS */
'@

[System.Windows.Forms.Application]::EnableVisualStyles()
# Determine BetterDiscord themes folder and ensure it exists
try {
    $themesDir = Join-Path -Path $env:APPDATA -ChildPath 'BetterDiscord\themes'
    if (-not (Test-Path -Path $themesDir)) {
        New-Item -ItemType Directory -Path $themesDir -Force | Out-Null
    }
} catch {
    # If we can't access APPDATA, fall back to saving next to the selected v6 file later.
    $themesDir = $null
}

$caption = 'Start Conversion — interactive'

$v6Path = Select-FileDialog -title 'Select ClearVision v6 theme to convert'
if (-not $v6Path) { [System.Windows.Forms.MessageBox]::Show('No v6 file selected. Exiting.', $caption); exit 0 }

try {
    $v6Backup = Join-Path -Path (Split-Path -Path $v6Path -Parent) -ChildPath ((Split-Path -Leaf $v6Path) + '.bak')
    [System.IO.File]::Copy($v6Path, $v6Backup, $true)
} catch {
    [System.Windows.Forms.MessageBox]::Show(('Failed to backup selected v6: {0}' -f $_), $caption, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

try { $v6Text = Read-FileRaw -path $v6Path } catch { [System.Windows.Forms.MessageBox]::Show(('Failed to read v6 file: {0}' -f $_), $caption, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error); exit 1 }

$rootBlock = Extract-RootBlock -cssText $v6Text
if ($null -eq $rootBlock) { $v6vars = Parse-CSS-Vars -text $v6Text } else { $v6vars = Parse-CSS-Vars -text $rootBlock }

$overrideRoot = Build-OverrideRootBlock -v6vars $v6vars

$choice = [System.Windows.Forms.MessageBox]::Show('Choose conversion type: 
Yes = Create New v7 file 
No = Overwrite existing v7 file', 'Create New or Overwrite?', [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Question)
if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { exit 0 }

if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
    $v6Base = (Split-Path -Leaf $v6Path)
    $baseNoExt = [System.IO.Path]::GetFileNameWithoutExtension($v6Base)
    $NewFileName = $baseNoExt + ' (Converted).theme.css'
    $outPath = if ($themesDir) { Join-Path -Path $themesDir -ChildPath $newFileName } else { Join-Path -Path (Split-Path -Path $v6Path -Parent) -ChildPath $newFileName }
    $content = $standardHeader.TrimEnd("") + "" + $overrideRoot + ""
    try {
        Write-FileUtf8 -path $outPath -text $content
        [System.Windows.Forms.MessageBox]::Show(('New v7 file created:{0}' -f $outPath), $caption)
    } catch {
        [System.Windows.Forms.MessageBox]::Show(('Failed to write New file: {0}' -f $_), $caption, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    exit 0
}

$v7Path = Select-FileDialog -title 'Select existing v7 .theme.css file to Overwrite'
if (-not $v7Path) { [System.Windows.Forms.MessageBox]::Show('No v7 file selected. Exiting.', $caption); exit 0 }

try {
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $v7Bak = Join-Path -Path (Split-Path -Path $v7Path -Parent) -ChildPath ((Split-Path -Leaf $v7Path) + '.backup.' + $timestamp)
    [System.IO.File]::Copy($v7Path, $v7Bak, $true)
} catch {
    [System.Windows.Forms.MessageBox]::Show(('Failed to backup v7 file: {0}' -f $_), $caption, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

try {
    $v7Text = Read-FileRaw -path $v7Path
    $m = [regex]::Match($v7Text, ':\s*root\s*\{')
    if (-not $m.Success) {
        $NewV7 = $standardHeader.TrimEnd("") + "" + $overrideRoot + "" + $v7Text
    } else {
        $startIdx = $m.Index
        $openMatch = [regex]::Match($v7Text.Substring($startIdx), '\{')
        $startBrace = $openMatch.Index + $startIdx
        $pos = $startBrace + 1
        $depth = 1
        while ($pos -lt $v7Text.Length -and $depth -gt 0) {
            if ($v7Text[$pos] -eq '{') { $depth++ } elseif ($v7Text[$pos] -eq '}') { $depth-- }
            $pos++
        }
        if ($depth -ne 0) { throw 'Unbalanced braces in target v7 file.' }
        $suffix = $v7Text.Substring($pos)
        $NewV7 = $standardHeader.TrimEnd("") + "" + $overrideRoot + "" + $suffix
    }

    Write-FileUtf8 -path $v7Path -text $NewV7

    $v6Base = (Split-Path -Leaf $v6Path)
    $baseNoExt = [System.IO.Path]::GetFileNameWithoutExtension($v6Base)
    $extraName = $baseNoExt + ' - v6 to v7 Overwrite.theme.css'
    $extraPath = if ($themesDir) { Join-Path -Path $themesDir -ChildPath $extraName } else { Join-Path -Path (Split-Path -Path $v7Path -Parent) -ChildPath $extraName }
    Write-FileUtf8 -path $extraPath -text $NewV7

    [System.Windows.Forms.MessageBox]::Show(('Overwrite complete. Original v7 backed up to:{0}New file written to:{1}Also wrote extra copy:{2}' -f $v7Bak, $v7Path, $extraPath), $caption)
} catch {
    [System.Windows.Forms.MessageBox]::Show(('Failed during Overwrite: {0}' -f $_), $caption, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
