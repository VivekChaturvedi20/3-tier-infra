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
data "azurerm_subnet" "devOpssubnet" {
  name = "subnet_01"
  resource_group_name = "KFDevOps"
  virtual_network_name = "KfDataDevOpsVnet"
}
data "azurerm_virtual_network" "devOpsVnet" {
  name = "KfDataDevOpsVnet"
  resource_group_name = "KFDevOps"
}
data "azurerm_private_dns_zone" "devopsDNSZone" {
  name = "privatelink.azurecr.io"
  resource_group_name = "KFDevOps"
}
data "azurerm_user_assigned_identity" "AKSIDENTITY" {
  name = "aksidentity-data"
  resource_group_name = "KFDevOps"
}
data "azurerm_container_registry" "ACR" {
  name = "DATINTHBACR1"
  resource_group_name = "DATINTHBRSG1"
}
locals {
  resource_prefix = join("",["DATA",var.environment_name])
}
resource "azurerm_resource_group" "datresourcegroup" {
  location = var.location
  name     = join("",[local.resource_prefix,"RSG",var.env_seq])
  tags = {
    environment = var.environment_name
    SpokeType   = "DATA"
  }
}
resource "azurerm_virtual_network" "datvnet" {
  name                = join("",[local.resource_prefix,"VNT",var.env_seq])
  location            = var.location
  resource_group_name = azurerm_resource_group.datresourcegroup.name
  address_space       = [var.vnet_address_space]
  depends_on          = [azurerm_resource_group.datresourcegroup]
  tags = {
    environment = var.environment_name
    SpokeType   = "DATA"
  }
}
resource "azurerm_subnet" "dat_aks_subnet" {
  name                 = "DAT_aks_subnet"
  resource_group_name  = azurerm_resource_group.datresourcegroup.name
  virtual_network_name = azurerm_virtual_network.datvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,8 ,0 )]
  enforce_private_link_endpoint_network_policies = true
  depends_on = [azurerm_resource_group.datresourcegroup,
    azurerm_virtual_network.datvnet
  ]
  service_endpoints = ["Microsoft.Sql","Microsoft.ContainerRegistry"]
}
resource "azurerm_subnet" "dat_waf_subnet" {
  name                 = "DAT_waf_subnet"
  resource_group_name  = azurerm_resource_group.datresourcegroup.name
  virtual_network_name = azurerm_virtual_network.datvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,11 ,8 )]
  enforce_private_link_endpoint_network_policies = true
  depends_on = [azurerm_resource_group.datresourcegroup,
    azurerm_virtual_network.datvnet
  ]

}
resource "azurerm_subnet" "dat_other_subnet" {
  name = "DAT_other_subnet"
  resource_group_name = azurerm_resource_group.datresourcegroup.name
  virtual_network_name = azurerm_virtual_network.datvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,10 ,8 )]
  depends_on = [azurerm_resource_group.datresourcegroup,
    azurerm_virtual_network.datvnet
  ]
  service_endpoints = ["Microsoft.Sql","Microsoft.ContainerRegistry"]
}
resource "azurerm_network_security_group" "NSG" {
  location = azurerm_resource_group.datresourcegroup.location
  name = join("",[local.resource_prefix,"NSG",var.env_seq])
  resource_group_name = azurerm_resource_group.datresourcegroup.name
  tags = {
    environment = var.environment_name
    SpokeType   = "DATA"
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "IN-AGW-REQUIRED"
    priority = 100
    protocol = "TCP"
    source_address_prefix = "*"
    destination_address_prefix = "*"
    source_port_range = "*"
    destination_port_range = "65200-65535"
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowHttpInbound"
    priority = 120
    protocol = "TCP"
    source_address_prefix = "Internet"
    destination_address_prefix = "*"
    destination_port_ranges = ["443","80"]
    source_port_range = "*"
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
    protocol = "TCP"
    destination_address_prefix = "*"
    destination_port_range = "443"
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
  subnet_id = azurerm_subnet.dat_aks_subnet.id
}
resource "azurerm_subnet_network_security_group_association" "OTHNSG" {
  network_security_group_id = azurerm_network_security_group.NSG.id
  subnet_id = azurerm_subnet.dat_other_subnet.id
  depends_on = [azurerm_network_security_group.NSG,azurerm_subnet.dat_other_subnet]
}
resource "azurerm_private_dns_zone_virtual_network_link" "DNS-VNET-LINK" {
  name = join("-",[local.resource_prefix,"DLNK",var.env_seq])
  private_dns_zone_name = data.azurerm_private_dns_zone.devopsDNSZone.name
  resource_group_name = data.azurerm_private_dns_zone.devopsDNSZone.resource_group_name
  virtual_network_id = azurerm_virtual_network.datvnet.id
}
resource "azurerm_private_endpoint" "DATENDPOINT" {
  location = var.location
  name = join("",[local.resource_prefix,"PVT",var.env_seq])
  resource_group_name = azurerm_resource_group.datresourcegroup.name
  subnet_id = azurerm_subnet.dat_aks_subnet.id
  tags = {
    environment = var.environment_name
    SpokeType   = "DATA"
  }
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
resource "azurerm_private_endpoint" "DevOps-ACR-Endpoint" {
  location = var.location
  name = join("-",["DEV",local.resource_prefix,"PVT",var.env_seq])
  resource_group_name = data.azurerm_subnet.devOpssubnet.resource_group_name
  subnet_id = data.azurerm_subnet.devOpssubnet.id
  tags = {
    environment = var.environment_name
    SpokeType   = "DATA"
  }
  private_service_connection {
    is_manual_connection = false
    name = "ACR-DevOps"
    private_connection_resource_id = data.azurerm_container_registry.ACR.id
    subresource_names = ["registry"]
  }
  private_dns_zone_group {
    name = "dns_zone"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.devopsDNSZone.id]
  }
}
resource "azurerm_kubernetes_cluster" "AKSCLUSTER" {
  dns_prefix = join("-",[local.resource_prefix,"AKS",var.env_seq,"dns"])
  location = azurerm_resource_group.datresourcegroup.location
  name = join("",[local.resource_prefix,"AKS",var.env_seq])
  resource_group_name = azurerm_resource_group.datresourcegroup.name
  tags = {
    environment = var.environment_name
    SpokeType   = "DATA"
  }
  default_node_pool {
    name = "default"
    vm_size = "Standard_D2S_v4"
    type = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    availability_zones = [1,2,3]
    enable_node_public_ip = false
    node_count = 2
    max_count = 10
    min_count = 2
    vnet_subnet_id = azurerm_subnet.dat_aks_subnet.id
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
}

resource "azurerm_virtual_network_peering" "DATA_DevOps" {
  name = join("-",[local.resource_prefix,"VNT",var.env_seq,"DevOps"])
  remote_virtual_network_id = data.azurerm_virtual_network.devOpsVnet.id
  resource_group_name = azurerm_resource_group.datresourcegroup.name
  virtual_network_name = azurerm_virtual_network.datvnet.name
  depends_on = [azurerm_virtual_network.datvnet]
}
resource "azurerm_virtual_network_peering" "DevOps_DATA" {
  name = join("-",["DevOps",local.resource_prefix,"VNT",var.env_seq])
  remote_virtual_network_id = azurerm_virtual_network.datvnet.id
  resource_group_name = data.azurerm_virtual_network.devOpsVnet.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.devOpsVnet.name
  depends_on = [azurerm_virtual_network.datvnet]
}
resource "azurerm_application_insights" "APPAINSIGHT" {
  application_type = "web"
  location = azurerm_resource_group.datresourcegroup.location
  name = join("",[local.resource_prefix,"AAI",var.env_seq])
  resource_group_name = azurerm_resource_group.datresourcegroup.name
  disable_ip_masking = false
  tags = {
    environment = var.environment_name
    SpokeType   = "DATA"
  }
}