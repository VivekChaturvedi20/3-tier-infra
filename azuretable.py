from azure.cosmosdb.table.tableservice import TableService
from azure.cosmosdb.table.models import Entity

storage_key = "y3yRwsDZoqoz20V6ZlRN3ImBzWXu6BuyUovv13cyfJQKMhtJC2QPa/FxNKTtVDMTwBbbsq9cws2c6U8V7//2oQ=="
storage_name = "cloudlegonewstorage"
print(storage_name)
table_service = TableService(account_name=storage_name, account_key=storage_key)
#table_service.create_table('kfsequence')
ip_seqs = []

tasks = table_service.query_entities('kfsequence', filter="PartitionKey eq 'sequences'")
for task in tasks:
        print(task.ip_seq)
        ip_seqs.append(task.ip_seq)

total_ips = len(ip_seqs)
print("last ip ", ip_seqs[total_ips - 1])
next_ip = ip_seqs[total_ips - 1] + 1
print("next ip ", next_ip)
print("##vso[task.setvariable variable=myOutputVar;isOutput=true]this is the deployment variable value")