Param( 
    [Parameter(Mandatory=$true)]
    [string]$spoke
    #[Parameter(Mandatory=$true)]
    #[string]$environment
)


$partition = "'" + $spoke + "'"
$env = "'" + $environment + "'"

az login --service-principal --username $Env:ARM_CLIENT_ID --password $Env:ARM_CLIENT_SECRET --tenant $Env:ARM_TENANT_ID
az account set --subscription $Env:ARM_SUBSCRIPTION_ID
az account show
$ips = az storage entity query --table-name kfsequence --filter "PartitionKey eq 'ipsequences'" --query items[].seq
$len = $ips.Length
$ipsType = $ips.GetType()
if($ipsType.Name -eq "String"){
    $next_ip_seq = 11
}
else{
    $last_ip_seq = $ips.GetValue($len -2) -replace '"',''
    $next_ip_seq = [int]$last_ip_seq + 1
     
}
$next_ip_address = "$next_ip_seq" + ".0.0.0/16"
Write-Output "next ip address $next_ip_address"
Write-Output "next IP seq is $next_ip_seq"
Write-Host("##vso[task.setvariable variable=nextIP]$next_ip_address")
Write-Host("##vso[task.setvariable variable=nextIPSeq]$next_ip_seq")


<#$envs = az storage entity query --table-name kfsequence  --filter "PartitionKey eq $partition and RowKey eq $env" --query items[].seq 

$envlen = $envs.Length
$envType = $envs.GetType()
if($envType.Name -eq "String"){
    $next_env_seq = 1
}
else{
    $last_env_seq = $envs.GetValue($envlen - 2) -replace '"',''
    Write-Output "last env sequence is $last_env_seq"
    $next_env_seq = [int]$last_env_seq + 1
    Write-Output "next env sequence is $next_env_seq"
}
Write-Output "next env sequence $next_env_seq"
Write-Output "The row key is $spoke"
Write-Host("##vso[task.setvariable variable=nextEnvSeq]$next_env_seq")#>

$rowkeys = az storage entity query --table-name kfsequence --filter "PartitionKey eq 'ipsequences'"  --query items[].RowKey
$rowLen = $rowkeys.Length
$rowsType = $rowkeys.GetType()
if($rowsType.Name -eq "String"){
    $next_row_seq = "001"
}
else{
    $last_row_seq = $rowkeys.GetValue($rowLen - 2) -replace "00","" -replace '\s', '' -replace '"',''
    Write-Host "last row sequence for IP $last_row_seq"
    $next_row_seq = [int]$last_row_seq + 1
    $next_row_seq = "00" + "$next_row_seq"
}
Write-Output "next row  sequence for IP $next_row_seq"
Write-Host("##vso[task.setvariable variable=nextIPRowKey]$next_row_seq")

<#$rowkeys = az storage entity query --table-name kfsequence --filter "PartitionKey eq $partition"  --query items[].RowKey
$rowLen = $rowkeys.Length
$rowsType = $rowkeys.GetType()
if($rowsType.Name -eq "String"){
    $next_row_seq = $env + "1"
}
else{
    $last_row_seq = $rowkeys.GetValue($rowLen - 2) -replace "00","" -replace '\s', '' -replace '"',''
    Write-Host "last row sequence for IP $last_row_seq"
    $next_row_seq = [int]$last_row_seq + 1
    $next_row_seq = "00" + "$next_row_seq"
}
Write-Output "next row  sequence for Env $next_row_seq"

Write-Host("##vso[task.setvariable variable=nextEnvRowKey]$env")
Write-Host("##vso[task.setvariable variable=envPartitionKey]$spoke")#>
