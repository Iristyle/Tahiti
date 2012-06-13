Push-Location (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent)

# modules in default locations ($env:PSModulePath),
Import-Module posh-hg
Import-Module posh-git
#Import-Module PsRemoting

# Type overrides (starters compliments of Scott Hanselman)
Update-TypeData "My.Types.ps1xml"

function Get-Title { $host.UI.RawUI.WindowTitle }

function Test-IsAdmin
{
  $windowsIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $windowsPrincipal = New-Object `
  Security.Principal.WindowsPrincipal($windowsIdentity)

  return $windowsPrincipal.IsInRole("Administrators")
}

function Get-Batchfile ($file)
{
  $cmd = "`"$file`" & set"
  cmd /c $cmd |
  % {
    $p, $v = $_.split('=')
    Set-Item -path env:$p -value $v
  }
}

function VsVars32($version = "10.0")
{
  if ([intptr]::size -eq 8)
  {
    $key = "HKLM:SOFTWARE\Wow6432Node\Microsoft\VisualStudio\" + $version
  }
  else
  {
    $key = "HKLM:SOFTWARE\Microsoft\VisualStudio\" + $version
  }
  $VsKey = Get-ItemProperty $key
  $VsInstallPath = [System.IO.Path]::GetDirectoryName($VsKey.InstallDir)
  $VsToolsDir = [System.IO.Path]::GetDirectoryName($VsInstallPath)
  $VsToolsDir = [System.IO.Path]::Combine($VsToolsDir, "Tools")
  $BatchFile = [System.IO.Path]::Combine($VsToolsDir, "vsvars32.bat")
  Get-Batchfile $BatchFile
  #[Console]::Title = "Visual Studio " + $version + " Windows Powershell"
  Set-ConsoleIcon "vspowershell.ico"
}

function Get-FreeSpace
{
  Get-WMIObject Win32_LogicalDisk -filter 'DriveType=3' |
    Select SystemName,DeviceID,VolumeName,
    @{
      Name='size(GB)';
      Expression={'{0:N1}' -f($_.size/1gb)}},
      @{
        Name='freespace(GB)';
        Expression={'{0:N1}' -f($_.freespace/1gb)
      }
    }
}

#inspired by batcharge.py - http://pastebin.com/Q41YbCdM
function Get-BatteryIndicator
{
  $rightFull = [char]0x25B6 #'▶'
  $rightEmpty = [char]0x25B7 #'▷'
  $leftFull = [char]0x25C0 #'◀'
  $leftEmpty = [char]0x25C1 #'◁'

  #these extended unicode characters only work in ISE or console2
  $battery = Get-WmiObject -Class Win32_Battery
  if (-not $battery)
  {
    return ("$rightFull" * 10), 10
  }

  $filled = [Math]::Ceiling($battery.EstimatedChargeRemaining / 10)

  switch ($battery.BatteryStatus)
  {
    #power connected / charging statuses
    { @(2, 6, 7, 8, 9) -contains $_ } { $full = $rightFull; $empty = $rightEmpty }
    default { $full = $leftFull; $empty = $leftEmpty }
  }

  return (($full * $filled) + ($empty * (10 - $filled))), $filled
}

# http://winterdom.com/2008/08/mypowershellprompt
function Shorten-Path([string] $path)
{
   $loc = $path.Replace($HOME, '~')
   # remove prefix for UNC paths
   $loc = $loc -replace '^[^:]+::', ''
   # make path shorter like tabs in Vim,
   # handle paths starting with \\ and . correctly
   return ($loc -replace '\\(\.?)([^\\])[^\\]*(?=\\)','\$1$2')
}

function Test-Hg
{
  $errorCount = $Error.Count
  &hg branch 2>&1 | Out-Null
  $success = $?
  if ($errorCount -ne $Error.Count) { $Error.RemoveAt(0)}
  return $success
}

function Test-Git
{
  $errorCount = $Error.Count
  &git branch 2>&1 | Out-Null
  $success = $?
  if ($errorCount -ne $Error.Count) { $Error.RemoveAt(0)}
  return $success
}

#inspiration from a number of zsh variants
#http://net.tutsplus.com/tutorials/tools-and-tips/how-to-customize-your-command-prompt/
#https://github.com/robbyrussell/oh-my-zsh
#http://stevelosh.com/blog/2010/02/my-extravagant-zsh-prompt/
function prompt
{
  $realLASTEXITCODE = $LASTEXITCODE

  #default for GIT
  # Reset color, which can be messed up by Enable-GitColors
  #$Host.UI.RawUI.ForegroundColor = $GitPromptSettings.DefaultForegroundColor

  #$cdelim = [ConsoleColor]:: #DarkCyan
  $chost = [ConsoleColor]::DarkCyan #Green
  $cloc = [ConsoleColor]::Cyan #Cyan

  $currentPath = Shorten-Path ($PWD).Path
  Write-Host "$($env:USERNAME.ToLower())@$($env:COMPUTERNAME.ToLower()): " -ForegroundColor $chost -NoNewLine
  Write-Host $currentPath -ForegroundColor $cloc -NoNewLine

  Write-VcsStatus

  $whitespace = [Console]::WindowWidth - [Console]::CursorLeft - 10
  $battery, $batteryLevel = Get-BatteryIndicator

  $foreColor = if ($batteryLevel -gt 6) { 'Green' }
    elseif ($batteryLevel -gt 4) { 'Yellow' }
    else { 'Red' }

  Write-Host (' ' * $whitespace) -NoNewLine
  Write-Host $battery -ForegroundColor $foreColor

  $title = $currentPath

  if ($windowTitle -ne $null)
  {
      $title = "$title  $([char]0x0BB)  $windowTitle"
  }

  $host.UI.RawUI.WindowTitle = $title

  #git gets ± as a prompt, hg gets ☿, default is §
  $promptChar = if (Test-Hg) { "$([char]0x263F) " }
    elseif (Test-Git) { "$([char]0x0B1) " }
    else { "$([char]0x0A7) " }

  $global:LASTEXITCODE = $realLASTEXITCODE

  return $promptChar
}

# Keep the existing window title
$windowTitle = (Get-Title).Trim()

if ($windowTitle.StartsWith("Administrator:")) {
  $windowTitle = $windowTitle.Substring(14).Trim()
}

# Remove default things we don't want

# We override with clear.ps1
#if (test-path alias:\clear)           { remove-item -force alias:\clear }
# ri conflicts with Ruby
#if (test-path alias:\ri)              { remove-item -force alias:\ri }

# We override with cd.ps1
#if (test-path alias:\cd)              { remove-item -force alias:\cd }
# We override with an alias to cd.ps1
#if (test-path alias:\chdir)           { remove-item -force alias:\chdir }

# We override with md.ps1
#if (test-path alias:\md)              { remove-item -force alias:\md }

# Conflicts with \Windows\System32\sc.exe
#if (test-path alias:\sc)              { remove-item -force alias:\sc }
# We override with md.ps1
#if (test-path function:\md)           { remove-item -force function:\md }
# We override with an alias to md.ps1
#if (test-path function:\mkdir)        { remove-item -force function:\mkdir }

# We override with prompt.ps1
#if (test-path function:\prompt)       { remove-item -force function:\prompt }

# Aliases/functions

set-alias grep   select-string
set-alias wide   format-wide
set-alias whoami get-username
#set-alias chdir  cd
set-alias mkdir  md

set-content function:\mklink "cmd /c mklink `$args"

# Development overrides

set-content env:\TERM "msys"    # To shut up Git 1.7.10+

Enable-GitColors

Start-SshAgent -Quiet

#if(-not (Test-Path Function:\DefaultTabExpansion)) {
#    Rename-Item Function:\TabExpansion DefaultTabExpansion
#}

# Set up tab expansion and include hg expansion
#function TabExpansion($line, $lastWord) {
#    $lastBlock = [regex]::Split($line, '[|;]')[-1]
#
#    switch -regex ($lastBlock) {
#        # mercurial and tortoisehg tab expansion
#        '(hg|thg) (.*)' { HgTabExpansion($lastBlock) }
#        # Fall back on existing tab expansion
#        default { DefaultTabExpansion $line $lastWord }
#    }
#}

Pop-Location