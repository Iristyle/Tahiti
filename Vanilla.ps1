#TODO: ensure that Set-ExecutionPolicy Unrestricted is hooked up before running this

function Test-IsAdmin
{
  $windowsIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $windowsPrincipal = New-Object `
  Security.Principal.WindowsPrincipal($windowsIdentity)

  return $windowsPrincipal.IsInRole("Administrators")
}

function Add-ToPath([string] $path)
{
  $Env:PATH += ";$path"
  [Environment]::SetEnvironmentVariable("PATH", $Env:PATH, [EnvironmentVariableTarget]::Machine)  
}

$IsSytem32Bit = (($Env:PROCESSOR_ARCHITECTURE -eq 'x86') `
  -and ($Env:PROCESSOR_ARCHITEW6432 -eq $null))
$IsProcess32Bit = ([IntPtr]::size -ne 8)

if (!Test-IsAdmin) { throw 'Administrators group permission required'}

$client = New-Object Net.WebClient
#chocolatey
$client.DownloadString('http://bit.ly/psChocInstall') | Invoke-Expression

cinst msysgit
cint 7zip
Add-ToPath "${ENV:\ProgramFiles}\7-Zip"
cinst Console2
cinst curl
#TODO: figure out what version of ST2 is installed
#cinst sublimetext2
cinst Growl

#TODO: which node package
cinst nodejs
cinst nodejs.install

$tortoiseUrl = if ($IsSytem32Bit) `
  {  'http://bitbucket.org/tortoisehg/thg/downloads/tortoisehg-2.4-hg-2.2.1-x86.msi'  }
  else { 'http://bitbucket.org/tortoisehg/thg/downloads/tortoisehg-2.4-hg-2.2.1-x64.msi' }

$tortoiseFIle = "${env:temp}\tortoisehg.msi"
$client.DownloadFile($tortoiseUrl, $tortoiseFIle)

msiexec /i `""$tortoiseFIle"`" /quiet
#only needs to be done for the current shell, since system env variables are established
$Env:PATH += ";${ENV:\ProgramFiles}\tortoisehg"


$client.DownloadString("http://psget.net/GetPsGet.ps1") | Invoke-Expression
Import-Module psget
Install-Module posh-hg
Install-Module posh-git
Install-Module find-string
Install-Module pester
Install-Module pswatch
Install-Module send-growl