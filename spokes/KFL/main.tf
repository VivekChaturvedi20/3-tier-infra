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
  default = "1"
}
locals {
  acrname = join("",["kflintacr",var.env_seq])
}
terraform {
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
}
data "azurerm_virtual_network" "hubvnet" {
  name = join("",["HUBINTCRVNT",var.env_seq])
  resource_group_name = join("",["HUBINTCRRSG",var.env_seq])
}
data "azurerm_subnet" "devOpssubnet" {
  name = "subnet_01"
  resource_group_name = "KFDevOps"
  virtual_network_name = "KFDevOpsVnet"
}
data "azurerm_private_dns_zone" "devopsDNSZone" {
  name = "privatelink.azurecr.io"
}
data "azurerm_key_vault" "devOpsKeyVault" {
  name = "kfDevOpsVault"
  resource_group_name = "KFDevOps"
}
resource "azurerm_resource_group" "kflresourcegroup" {
  location = var.location
  name     = join("",["KFLINTHBRSG",var.env_seq])
  tags = {
    environment = var.environment_name
    SpokeType   = "KFL"
    CICDStage   = "INT"
    Release     = "CR"
  }
}
resource "azurerm_virtual_network" "kflvnet" {
  name                = join("",["KFLINTHBVNT",var.env_seq])
  location            = var.location
  resource_group_name = azurerm_resource_group.kflresourcegroup.name
  address_space       = [var.vnet_address_space]
  depends_on          = [azurerm_resource_group.kflresourcegroup]
  tags = {
    environment = var.environment_name
    SpokeType   = "KFL"
    CICDStage   = "INT"
    Release     = "CR"
  }
}
resource "azurerm_subnet" "kfl_aks_subnet" {
  name                 = "kfl_aks_subnet"
  resource_group_name  = azurerm_resource_group.kflresourcegroup.name
  virtual_network_name = azurerm_virtual_network.kflvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,8 ,0 )]
  depends_on = [azurerm_resource_group.kflresourcegroup,
    azurerm_virtual_network.kflvnet
  ]
}
resource "azurerm_subnet" "kfl_waf_subnet" {
  name                 = "kfl_waf_subnet"
  resource_group_name  = azurerm_resource_group.kflresourcegroup.name
  virtual_network_name = azurerm_virtual_network.kflvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,11 ,8 )]
  depends_on = [azurerm_resource_group.kflresourcegroup,
    azurerm_virtual_network.kflvnet
  ]
}

resource "azurerm_subnet" "kfl_other_subnet" {
  name = "kfl_other_subnet"
  resource_group_name = azurerm_resource_group.kflresourcegroup.name
  virtual_network_name = azurerm_virtual_network.kflvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,10 ,8 )]
  depends_on = [azurerm_resource_group.kflresourcegroup,
    azurerm_virtual_network.kflvnet
  ]
  service_endpoints = ["Microsoft.ContainerRegistry"]
}
resource "azurerm_network_security_group" "NSG" {
  location = azurerm_resource_group.kflresourcegroup.location
  name = join("",["DATINTHBNSG",var.env_seq])
  resource_group_name = azurerm_resource_group.kflresourcegroup.name
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowHttpsInbound"
    priority = 120
    protocol = "Tcp"
    source_address_prefix = "Internet"
    destination_address_prefix = "*"
    source_port_range = "*"
    destination_port_range = "443"
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowGatewayManagerInbound"
    priority = 130
    protocol = "Tcp"
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
    source_port_range = "*"
    destination_port_range = "443"
    source_address_prefix = "AzureLoadBalancer"
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowBastionHostCommunication"
    priority = 150
    protocol = "*"
    destination_port_ranges = ["8080","5701"]
    source_port_range = "*"
    destination_address_prefix = "VirtualNetwork"
    source_address_prefix = "VirtualNetwork"
  }
  security_rule {
    access = "Allow"
    direction = "Outbound"
    name = "AllowSshRdpOutbound"
    priority = 100
    protocol = "*"
    source_address_prefix = "*"
    source_port_range = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_ranges = ["22","3389"]
  }
  security_rule {
    access = "Allow"
    direction = "Outbound"
    name = "AllowAzureCloudOutbound"
    priority = 110
    protocol = "Tcp"
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
    destination_port_ranges = ["8080","5701"]\
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
    destination_port_range = "80"
    source_port_range = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "AKSNSG" {
  network_security_group_id = azurerm_network_security_group.NSG.id
  subnet_id = azurerm_subnet.kfl_aks_subnet.id
}
resource "azurerm_subnet_network_security_group_association" "OTHNSG" {
  network_security_group_id = azurerm_network_security_group.NSG.id
  subnet_id = azurerm_subnet.kfl_other_subnet.id
}
resource "azurerm_virtual_network_peering" "KFLHUBPeering" {
  name = "KFL_HUB_PEER"
  remote_virtual_network_id = data.azurerm_virtual_network.hubvnet.id
  resource_group_name = azurerm_virtual_network.kflvnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.kflvnet.name
}
resource "azurerm_virtual_network_peering" "HUBKFLPeering" {
  name = "KFL_HUB_PEER"
  remote_virtual_network_id = azurerm_virtual_network.kflvnet.id
  resource_group_name = data.azurerm_virtual_network.hubvnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.hubvnet.name
}
resource "azurerm_container_registry" "kflACR" {
  location = azurerm_resource_group.kflresourcegroup.location
  name = join("",["KFLINTHBACR",var.env_seq])
  resource_group_name = azurerm_resource_group.kflresourcegroup.name
  sku = "Premium"
  admin_enabled = true
  public_network_access_enabled = false
  network_rule_set {
    default_action = "Deny"
    virtual_network {
      action = "Allow"
      subnet_id = azurerm_subnet.kfl_other_subnet.id
    }
  }
  depends_on = [azurerm_subnet.kfl_other_subnet]
}
resource "azurerm_private_endpoint" "KFLENDPOINT" {
  location = var.location
  name = join("",["KFLINTCRPVT",var.env_seq])
  resource_group_name = azurerm_resource_group.kflresourcegroup.name
  subnet_id = data.azurerm_subnet.devOpssubnet.id
  private_service_connection {
    is_manual_connection = false
    name = "ACRCONN"
    private_connection_resource_id = azurerm_container_registry.kflACR.id
    subresource_names = ["registry"]
  }
  private_dns_zone_group {
    name = "dns_zone"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.devopsDNSZone.id]
  }
}
resource "azurerm_route_table" "KFLRTBL" {
  location = azurerm_resource_group.kflresourcegroup.location
  name = join("",["KFLINTCRRTB",var.env_seq])
  resource_group_name = azurerm_resource_group.kflresourcegroup.name
  route {
    address_prefix = "0.0.0.0/0"
    name = "internetRoute"
    next_hop_type = "VnetLocal"
  }
  tags = {
    environment = var.environment_name
    SpokeType   = "KFL"
    CICDStage   = "INT"
    Release     = "CR"
  }
  depends_on = [azurerm_subnet.kfl_aks_subnet,azurerm_subnet.kfl_other_subnet,azurerm_subnet.kfl_waf_subnet]
}
resource "azurerm_log_analytics_workspace" "OMS" {
  location = azurerm_resource_group.kflresourcegroup.location
  name = join("",["KFLINTCROMS",var.env_seq])
  resource_group_name = azurerm_resource_group.kflresourcegroup.name
  sku = "PerGB2018"
  retention_in_days = 30
}
resource "azurerm_key_vault_secret" "store_oms_id" {
  key_vault_id = data.azurerm_key_vault.devOpsKeyVault.id
  name = "kfl-workspace-id"
  value = azurerm_log_analytics_workspace.OMS.workspace_id
}
resource "azurerm_key_vault_secret" "store_oms_key" {
  key_vault_id = data.azurerm_key_vault.devOpsKeyVault.id
  name = "kfl-workspace-primary-key"
  value = azurerm_log_analytics_workspace.OMS.primary_shared_key
}
resource "azurerm_kubernetes_cluster" "AKS" {
  dns_prefix = "KFSINTCRAKS1-dns"
  location = azurerm_resource_group.kfsresourcegroup.location
  name = "KFSINTCRAKS1"
  resource_group_name = azurerm_resource_group.kfsresourcegroup.name
  default_node_pool {
    name = "default"
    vm_size = "Standard_DS2_v2"
    type = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    node_count = 2
    vnet_subnet_id = azurerm_subnet.kfs_aks_subnet.id
    tags = {
      environment = var.environment_name
      SpokeType   = "KFS"
      CICDStage   = "INT"
      Release     = "CR"
    }
  }
  role_based_access_control {
    enabled = true
  }
  identity {
    type = "SystemAssigned"
  }
  addon_profile {
    oms_agent {
      enabled = false
      log_analytics_workspace_id = azurerm_log_analytics_workspace.OMS.workspace_id
    }
  }
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    outbound_type = "loadBalancer"
    load_balancer_sku = "Standard"
  }
}