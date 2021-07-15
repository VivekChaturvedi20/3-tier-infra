az login --service-principal --username $Env:ARM_CLIENT_ID --password $Env:ARM_CLIENT_SECRET --tenant $Env:ARM_TENANT_ID
az storage entity insert --entity PartitionKey='ipsequences' RowKey=$Env:nextIPRowKey seq=$Env:nextIPSeq --if-exists fail --table-name kfsequence
az storage entity insert --entity PartitionKey=$Env:envPartitionKey RowKey=$Env:nextEnvRowKey seq=$Env:nextEnvSeq --if-exists fail --table-name kfsequence
