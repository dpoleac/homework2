#region Paramaters
param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$appId,
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$password,
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$tenant
)
#endregion

#region Find VMs Creds and IPs

$passwd = ConvertTo-SecureString $password -AsPlainText -Force
$pscredential = New-Object System.Management.Automation.PSCredential($appId, $passwd)

Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenant

$a = @()

$vaultname = "paaswords-for-homework"
$secret = Get-AzKeyVaultSecret -VaultName $vaultname

$VMsnames = (Get-AzKeyVaultSecret -VaultName $vaultname | where {$_.Name -like "homework-win-*"}).Name

foreach($nameVM in $VMsnames){
Write-Output $nameVM
$a += (Get-AzKeyVaultSecret -VaultName $vaultname -Name $nameVM).SecretValueText
}


$VMUser = (Get-AzKeyVaultSecret -VaultName $vaultname -Name VMUser).SecretValueText
$VMPassword = (Get-AzKeyVaultSecret -VaultName $vaultname -Name VMPassword).SecretValueText

$vmpassword = ConvertTo-SecureString $VMPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($VMUser, $vmpassword)

#endregion

#region Check and Start WinRM service

$ServiceName = 'WinRM'
$arrService = Get-Service -Name $ServiceName

if ($arrService.Status -ne 'Running'){
$ServiceStarted = $false}
Else{$ServiceStarted = $true}

while ($ServiceStarted -ne $true){
Start-Service $ServiceName
write-host $arrService.status
write-host 'Service started'
Start-Sleep -seconds 5
$arrService = Get-Service -Name $ServiceName
if ($arrService.Status -eq 'Running'){
$ServiceStarted = $true}
}
#endregion

#region Add VM's IPs to TrustedHosts
foreach ($ips in $a)

Set-Item WSMan:\localhost\Client\TrustedHosts -Value $a -Force -Concatenate

#endregion

#region Performance counters
$Counters = @(
    "\Processor(_Total)\% Processor Time"
    "\Memory\Available MBytes"
    "\PhysicalDisk(0 C:)\Disk Read Bytes/sec"
    "\PhysicalDisk(0 C:)\Disk Write Bytes/sec"
    "\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Sent/sec"
    "\Network Adapter(Hyper-V Virtual Ethernet Adapter)\Bytes Received/sec"
)
#endregion

#region ScriptBlock

[scriptblock]$ScriptBlockContent = {
foreach ($ips in $a)

    Get-Counter $args[0] -SampleInterval 1 -MaxSamples 3600

}

Invoke-Command -ComputerName {foreach($ips in $a)} -Credential $cred -UseSSL -Port 5986 -ScriptBlock $ScriptBlockContent -ArgumentList $Counters
   
#endregion

#region Remote PS Session, Start Jobs, extract performance counters and export into a txt

foreach ($ips in $a) {

$jobs = Start-Job -ScriptBlock $ScriptBlockContent -ArgumentList ($a)

     }
$jobs | Wait-Job | Receive-Job


$result | Out-File -FilePath $(Split-Path 'MyInvocation.MyCommand.Path\Output.txt') | ft -AutoSize

#endregion