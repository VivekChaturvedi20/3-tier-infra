variable "location" {
  type    = string
  default = "east us"
}
variable "vnet_address_space" {
  type    = string
  default = "11.0.0.0/16"
}
variable "environment_name" {
  type    = string
  default = "dev"
}
variable "env_seq" {
  type = string
}

terraform {
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
}
data "azurerm_virtual_network" "hubvnet" {
  name = join("",["HUB",var.environment_name,"VNT",var.env_seq])
  resource_group_name = join("",["HUB",var.environment_name,"RSG",var.env_seq])
}
data "azurerm_subnet" "devOpssubnet" {
  name = "subnet_01"
  resource_group_name = "KFDevOps"
  virtual_network_name = "KFDevOpsVnet"
}
data "azurerm_virtual_network" "devOpsVnet" {
  name = "KFDevOpsVnet"
  resource_group_name = "KFDevOps"
}
data "azurerm_private_dns_zone" "devopsDNSZone" {
  name = "privatelink.azurecr.io"
  resource_group_name = "KFDevOps"
}
data "azurerm_key_vault" "devOpsKeyVault" {
  name = "kfDevOpsVault"
  resource_group_name = "KFDevOps"
}
data "azurerm_user_assigned_identity" "AKSIDENTITY" {
  name = "aksidentity-engg"
  resource_group_name = "KFDevOps"
}
data "azurerm_container_registry" "ACR" {
  name = "KFSINTHBACR1"
  resource_group_name = "KFSINTHBRSG1"
}
data "azurerm_application_gateway" "AAG" {
  name = "HUBINTCRAAG1"
  resource_group_name = "HUBINTCRRSG1"
}
data "azurerm_log_analytics_workspace" "HUB-OMS" {
  name = join("",["HUB",var.environment_name,"OMS",var.env_seq])
  resource_group_name = join("",["HUB",var.environment_name,"RSG",var.env_seq])
}
data "azurerm_client_config" "current" {}
locals {
  resource_prefix = join("",["KFS",var.environment_name])
}
resource "azurerm_resource_group" "kfsresourcegroup" {
  location = var.location
  name     = join("",[local.resource_prefix,"RSG",var.env_seq])
  tags = {
    environment = var.environment_name
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
}
resource "azurerm_virtual_network" "kfsvnet" {
  name                = join("",[local.resource_prefix,"VNT",var.env_seq])
  location            = var.location
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  address_space       = [var.vnet_address_space]
  depends_on          = [azurerm_resource_group.kfsresourcegroup]
  tags = {
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
}
resource "azurerm_subnet" "kfs_aks_subnet" {
  name                 = "kfs_aks_subnet"
  resource_group_name  = azurerm_resource_group.kfsresourcegroup.name
  virtual_network_name = azurerm_virtual_network.kfsvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,8 ,0 )]
  enforce_private_link_endpoint_network_policies = true
  depends_on = [azurerm_resource_group.kfsresourcegroup,
    azurerm_virtual_network.kfsvnet
  ]
  service_endpoints = ["Microsoft.Sql","Microsoft.ContainerRegistry","Microsoft.Storage"]
}
resource "azurerm_subnet" "kfs_waf_subnet" {
  name                 = "kfs_waf_subnet"
  resource_group_name  = azurerm_resource_group.kfsresourcegroup.name
  virtual_network_name = azurerm_virtual_network.kfsvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,11 ,8 )]
  enforce_private_link_endpoint_network_policies = true
  service_endpoints = ["Microsoft.Sql","Microsoft.ContainerRegistry","Microsoft.Storage"]
  depends_on = [azurerm_resource_group.kfsresourcegroup,
    azurerm_virtual_network.kfsvnet
  ]
}
resource "azurerm_subnet" "kfs_other_subnet" {
  name = "kfs_other_subnet"
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  virtual_network_name = azurerm_virtual_network.kfsvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,10 ,8 )]
  enforce_private_link_endpoint_network_policies = true
  depends_on = [azurerm_resource_group.kfsresourcegroup,
    azurerm_virtual_network.kfsvnet
  ]
  service_endpoints = ["Microsoft.Sql","Microsoft.ContainerRegistry","Microsoft.Storage"]
}
resource "azurerm_network_security_group" "NSG" {
  location = azurerm_resource_group.kfsresourcegroup.location
  name = join("",[local.resource_prefix,"NSG",var.env_seq])
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  tags = {
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowHttpsInbound"
    priority = 120
    protocol = "TCP"
    source_address_prefix = "Internet"
    destination_address_prefix = "*"
    source_port_range = "*"
    destination_port_ranges = ["443","80"]
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowGatewayManagerInbound"
    priority = 130
    protocol = "TCP"
    destination_port_range = "443"
    source_port_range = "*"
    source_address_prefix = "GatewayManager"
    destination_address_prefix = "*"
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowAzureLoadBalancerInbound"
    priority = 140
    protocol = "Tcp"
    destination_address_prefix = "*"
    destination_port_ranges = ["443","80"]
    source_port_range = "*"
    source_address_prefix = "AzureLoadBalancer"
  }
  security_rule {
    access = "Allow"
    direction = "Outbound"
    name = "AllowSshRdpOutbound"
    priority = 100
    protocol = "*"
    source_address_prefix = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_ranges = ["22","3389"]
    source_port_range = "*"
  }
  security_rule {
    access = "Allow"
    direction = "Outbound"
    name = "AllowAzureCloudOutbound"
    priority = 110
    protocol = "TCP"
    source_address_prefix = "*"
    destination_address_prefix = "AzureCloud"
    destination_port_range = "443"
    source_port_range = "*"
  }
  security_rule {
    access = "Allow"
    direction = "Outbound"
    name = "AllowBastionCommunication"
    priority = 120
    protocol = "*"
    destination_port_ranges = ["8080","5701"]
    source_port_range = "*"
    source_address_prefix = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    access = "Allow"
    direction = "Outbound"
    name = "AllowGetSessionInformation"
    priority = 130
    protocol = "*"
    destination_address_prefix = "Internet"
    source_address_prefix = "*"
    destination_port_ranges = ["443","80"]
    source_port_range = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "AKSNSG" {
  network_security_group_id = azurerm_network_security_group.NSG.id
  subnet_id = azurerm_subnet.kfs_aks_subnet.id
}
resource "azurerm_subnet_network_security_group_association" "OTHNSG" {
  network_security_group_id = azurerm_network_security_group.NSG.id
  subnet_id = azurerm_subnet.kfs_other_subnet.id
}
resource "azurerm_virtual_network_peering" "KFSHUBPeering" {
  name = join("-",[local.resource_prefix,"VNT",var.env_seq,"HUB"])
  remote_virtual_network_id = data.azurerm_virtual_network.hubvnet.id
  resource_group_name = azurerm_virtual_network.kfsvnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.kfsvnet.name
}
resource "azurerm_virtual_network_peering" "HUBKFSPeering" {
  name = join("-",["HUB",local.resource_prefix,"VNT",var.env_seq])
  remote_virtual_network_id = azurerm_virtual_network.kfsvnet.id
  resource_group_name = data.azurerm_virtual_network.hubvnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.hubvnet.name
}
resource "azurerm_virtual_network_peering" "DevOpsKFSPeering" {
  name = join("-",[local.resource_prefix,"VNT",var.env_seq,"DevOps"])
  remote_virtual_network_id = data.azurerm_virtual_network.devOpsVnet.id
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  virtual_network_name = azurerm_virtual_network.kfsvnet.name
}
resource "azurerm_virtual_network_peering" "KFSDevOpsPeering" {
  name = join("-",["DevOps",local.resource_prefix,"VNT",var.env_seq])
  remote_virtual_network_id = azurerm_virtual_network.kfsvnet.id
  resource_group_name = data.azurerm_virtual_network.devOpsVnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.devOpsVnet.name
}
resource "azurerm_key_vault" "AKV" {
  location = azurerm_resource_group.kfsresourcegroup.location
  name = join("",[local.resource_prefix,"AKV",var.env_seq])
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  sku_name = "standard"
  tenant_id = data.azurerm_client_config.current.tenant_id
  access_policy {
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
    key_permissions = ["Get","List","Delete"]
    secret_permissions = ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
    storage_permissions = ["Get"]
  }
}
resource "random_password" "postgrepassword" {
  length = 64
}
resource "azurerm_postgresql_server" "POSTGRES" {
  location = azurerm_resource_group.kfsresourcegroup.location
  name = lower(join("",[local.resource_prefix,"psql",var.env_seq]))
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  sku_name = "GP_Gen5_4"
  version = "11"
  administrator_login = "psqladmin"
  administrator_login_password = random_password.postgrepassword.result
  backup_retention_days = 7
  auto_grow_enabled = true
  public_network_access_enabled = false
  ssl_enforcement_enabled = true
  ssl_minimal_tls_version_enforced = "TLS1_2"
  lifecycle {
    prevent_destroy = false
  }
  tags = {
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
  threat_detection_policy {
    enabled = true
    email_addresses = ["rajagopalan.o@kornferry.com"]
  }
}
resource "azurerm_key_vault_secret" "store_pgsl_password" {
  key_vault_id = data.azurerm_key_vault.devOpsKeyVault.id
  name = join("-",[local.resource_prefix,"PSQL",var.env_seq,"password"])
  value = azurerm_postgresql_server.POSTGRES.administrator_login_password
}
resource "azurerm_kubernetes_cluster" "AKSCLUSTER" {
  dns_prefix = join("-",["KFSINTCRAKS",var.env_seq,"dns"])
  location = azurerm_resource_group.kfsresourcegroup.location
  name = join("",[local.resource_prefix,"AKS",var.env_seq])
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  tags = {
    environment = var.environment_name
    SpokeType   = "KFS"
  }
  default_node_pool {
    name = "default"
    vm_size = "Standard_D2S_v4"
    type = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    enable_node_public_ip = false
    node_count = 2
    max_count = 10
    min_count = 1
    vnet_subnet_id = azurerm_subnet.kfs_aks_subnet.id
  }
  identity {
    type = "UserAssigned"
    user_assigned_identity_id = data.azurerm_user_assigned_identity.AKSIDENTITY.id
  }
  role_based_access_control {
    enabled = true
  }
  network_profile {
    network_plugin = "azure"
    load_balancer_sku = "Standard"
    network_policy = "azure"
  }
  addon_profile {
    oms_agent {
      enabled = true
      log_analytics_workspace_id = data.azurerm_log_analytics_workspace.HUB-OMS.id
    }
  }
}
resource "azurerm_private_dns_zone_virtual_network_link" "DNS-VNET-LINK" {
  name = join("",[local.resource_prefix,"DLNK",var.env_seq])
  private_dns_zone_name = data.azurerm_private_dns_zone.devopsDNSZone.name
  resource_group_name = data.azurerm_private_dns_zone.devopsDNSZone.resource_group_name
  virtual_network_id = azurerm_virtual_network.kfsvnet.id
}
resource "azurerm_private_endpoint" "ENDPOINT1" {
  location = var.location
  name = "AKS-ACR-ENDPOINT"
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  tags = {
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
  subnet_id = azurerm_subnet.kfs_aks_subnet.id
  private_service_connection {
    is_manual_connection = false
    name = "ACRCONN"
    private_connection_resource_id = data.azurerm_container_registry.ACR.id
    subresource_names = ["registry"]
  }
  private_dns_zone_group {
    name = "dns_zone"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.devopsDNSZone.id]
  }
}
resource "azurerm_private_endpoint" "ENDPOINT2" {
  location = var.location
  name = "PGSQL-AKS-ENDPOINT"
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  subnet_id = azurerm_subnet.kfs_aks_subnet.id
  tags = {
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
  private_service_connection {
    is_manual_connection = false
    name = "PSQLCONN"
    private_connection_resource_id = azurerm_postgresql_server.POSTGRES.id
    subresource_names = ["postgresqlServer"]
  }
  private_dns_zone_group {
    name = "dns_zone"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.devopsDNSZone.id]
  }
}
resource "azurerm_storage_account" "STORAGE-STATIC-WEBSITE" {
  name                     = lower(join("",[local.resource_prefix,"asta",var.env_seq]))
  resource_group_name      = azurerm_resource_group.kfsresourcegroup.name
  location                 = azurerm_resource_group.kfsresourcegroup.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  allow_blob_public_access = true
  tags = {
    environment = var.environment_name
    SpokeType   = "KFS"
  }
  network_rules {
    default_action = "Allow"
    virtual_network_subnet_ids = [azurerm_subnet.kfs_other_subnet.id,azurerm_subnet.kfs_aks_subnet.id,data.azurerm_subnet.devOpssubnet.id]
    ip_rules = ["147.243.0.0/16"]
  }
  lifecycle {
    prevent_destroy = false
  }
  static_website {
    index_document = "index.html"
  }
}
resource "azurerm_cdn_profile" "CDN-PROFILE" {
  location = azurerm_resource_group.kfsresourcegroup.location
  name = lower(join("",[local.resource_prefix,"ael",var.env_seq]))
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  sku = "Standard_Microsoft"
  tags = {
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
}
resource "azurerm_application_insights" "APPAINSIGHT" {
  application_type = "web"
  location = azurerm_resource_group.kfsresourcegroup.location
  name = join("",[local.resource_prefix,"AAI",var.env_seq])
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  disable_ip_masking = false
  tags = {
    SpokeType   = "KFS"
    CICDStage   = var.environment_name
  }
}