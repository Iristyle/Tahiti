$script:sessionHome = ($env:PSModulePath).Split(';')[0]
$script:sessionPath = Join-path $sessionHome 'Sessions.xml'
$script:masterKeyPath = Join-path $sessionHome 'MasterKey.xml'
$script:sessionDefinitions = @()
$script:masterPassword = $null
#random 256-bit key
$script:secureStringKey = (172,126,35,1,85,249,169,187,162,172,2,141,253,38,11,25,
109,38,254,210,45,177,53,14,116,43,185,152,43,85,0,255)
#random 48-bit entropy
$script:DpEntropy = [byte[]](5,8,27,34,19)

if (Test-Path $sessionPath)
{
    $script:SessionDefinitions = Import-CliXml -Path $sessionPath
}

#first time run store a key
if (!(Test-Path $masterKeyPath))
{
    Write-Host @'
A master password must be entered.
This
'@
    Set-MasterPassword
}

function Set-MasterPassword
{
    $pass = Read-Host -AsSecureString | ConvertFrom-SecureString -Key $key
    $bytes = [byte[]][char[]]$pass

    $csp = New-Object Security.Cryptography.CspParameters
    $csp.KeyContainerName = "RemotingSessionMasterKey"
    $csp.Flags = $csp.Flags -bor [Security.Cryptography.CspProviderFlags]::UseMachineKeyStore
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider(5120, $csp)
    $rsa.PersistKeyInCsp = $true

    $script:masterPassword = $rsa.Encrypt($bytes, $true)
    $script:masterPassword | Export-Clixml $script:masterKeyPath
}

function Get-MasterPassword
{
    if ($script:masterPassword) { return $script:masterPassword }

    $encrypted = Import-Clixml 'C:\Dropbox\My Dropbox\scripts\word.xml'

    $csp = New-Object Security.Cryptography.CspParameters
    $csp.KeyContainerName = "RemotingSessionMasterKey"
    $csp.Flags = $csp.Flags -bor [Security.Cryptography.CspProviderFlags]::UseMachineKeyStore
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider -ArgumentList 5120,$csp
    $rsa.PersistKeyInCsp = $true

    $password = [char[]]$rsa.Decrypt($encrypted, $true) -join "" |
        ConvertTo-SecureString -Key $key
    $cred = New-Object Management.Automation.PsCredential 'tome', $password
}

function Get-Creds
{
    param($UserName, $Password)

    New-Object Management.Automation.PsCredential($UserName, `
        (ConvertTo-SecureString $Password -AsPlainText -force))
}

function Start-RemoteSession
{
    param(
        [parameter(Mandatory=$true)]
        [string] $HostName,

        [parameter(Mandatory=$true)]
        [string] $UserName,

        [parameter(Mandatory=$true)]
        [string] $Password
    )

    $params = @{
        ComputerName = $HostName;
        Credential = (Get-Creds $UserName $Password);
    }

    Enter-PSSession @params
}

function Enter-NamedSession
{
    param(
        [parameter(Mandatory=$true)]
        [ValidateScript({})]
        [string] $Name
    )
    #TODO: ensure the name exists in Get-PSSession
    #and if not, that it exists in the global list of configured sessions

    Enter-PSSession -Session (Get-PSSession -Name $Name)
}

#function ConvertFrom-SecureString
#{
#    param(
#        [Parameter(Mandatory=$true)]
#        [string]
#        $Text
#    )
#    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($text)
#  $result = [Runtime.InteropServices.Marshal]::PtrToStringUni($pointer)
#  [Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($pointer)
#  $result
#}

function ConvertTo-ProtectedDataBase64
{
    param(
        [Parameter(Mandatory=$true)]
        $Text
    )

    $passwordBytes = [Text.Encoding]::Unicode.GetBytes($Text)
    $scope = [Security.Cryptography.DataProtectionScope]::CurrentUser
    $protectedData = [Security.Cryptography.ProtectedData]::Protect(
        $passwordBytes, $script:DpEntropy, $scope)

    [Convert]::ToBase64String($protectedData)
}

function ConvertFrom-ProtectedDataBase64
{
    param(
        [Parameter(Mandatory=$true)]
        $Text
    )

    $base64Bytes = [Convert]::FromBase64String($Text)

    $scope = [Security.Cryptography.DataProtectionScope]::CurrentUser
    $unprotectedData = [Security.Cryptography.ProtectedData]::Unprotect(
        $base64Bytes, $script:DpEntropy, $scope)
    [Text.Encoding]::Unicode.GetString($unprotectedData)
}

function Add-NamedSession
{
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $ComputerName,

        [Parameter(Mandatory=$true)]
        [string]
        $Name,

        [Parameter(Mandatory=$false)]
        [string]
        $Credential = Get-Credential,

        [Parameter(Mandatory=$true)]
        [bool]
        $AutoStart = $false
    )

    #TODO: don't allow duplicate names for computerName or Name
    $session = @{
        ComputerName = $ComputerName;
        Name = $Name;
        UserName = $Credential.UserName;
        Password = (ConvertTo-ProtectedDataBase64 `
            -Text (ConvertFrom-SecureString $Credential.Password));
        AutoStart = $AutoStart;
    }

    $script:sessionDefinitions += @($session,)
    $script:sessionDefinitions | Export-Clixml -Path $script:sessionPath
}

function Get-NamedSession
{
    $script:SessionDefinitions
}


$Servers | ? { $_.AutoStart } |
    % { New-PSSession -ComputerName $_.ComputerName -Name $_.Name -Credential $_.Credential }


Export-ModuleMember -Function Add-NamedSession