variable "location" {
  type    = string
  default = "east us"
}
variable "vnet_address_space" {
  type    = string
  default = "10.0.0.0/16"
}
variable "environment_name" {
  type    = string
  default = "dev"
}
variable "env_seq" {
  type = string
  default = "1"
}
terraform {
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
}
locals {
  env_tag = join("_",[var.environment_name,var.env_seq])
  resource_prefix = join("",["HUB",var.environment_name])
  backend_address_pool_name      = "kfsell-plaform-backend"
  frontend_port_name             = "http"
  frontend_ip_configuration_name = "http-ip"
  http_setting_name              = "kfsell-platform-http-settings"
  listener_name                  = "kfsell-platform-listener"
  request_routing_rule_name      = "kfsell-platform-rule"

}
resource "azurerm_resource_group" "HUBResourceGroup" {
  location = var.location
  name     = join("",[local.resource_prefix,"RSG",var.env_seq])
  tags = {
    environment = local.env_tag
    SpokeType   = "HUB"
    CICDStage   = var.environment_name
  }
}
resource "azurerm_virtual_network" "hubvnet" {
  name                = join("",[local.resource_prefix,"VNT",var.env_seq])
  location            = var.location
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  address_space       = [var.vnet_address_space]
  depends_on          = [azurerm_resource_group.HUBResourceGroup]
  tags = {
    environment = local.env_tag
    SpokeType   = "HUB"
    CICDStage   = var.environment_name
  }
}
resource "azurerm_network_security_group" "HUBNSG" {
  location            = var.location
  name                = join("",[local.resource_prefix,"NSG",var.env_seq])
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  depends_on          = [azurerm_resource_group.HUBResourceGroup]
  tags = {
    environment = local.env_tag
    SpokeType   = "HUB"
    CICDStage   = var.environment_name
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
    name = "AllowHttpsInbound"
    priority = 120
    protocol = "TCP"
    source_address_prefix = "Internet"
    destination_address_prefix = "*"
    source_port_range = "*"
    destination_port_range = "443"
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
resource "azurerm_subnet" "HBSUBNET" {
  name                 = "hubsubnet1"
  resource_group_name  = azurerm_resource_group.HUBResourceGroup.name
  virtual_network_name = azurerm_virtual_network.hubvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,8 ,0 )]
  depends_on = [azurerm_resource_group.HUBResourceGroup,
    azurerm_virtual_network.hubvnet,
    azurerm_network_security_group.HUBNSG
  ]
}
resource "azurerm_subnet" "HBFWLSUBNET" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.HUBResourceGroup.name
  virtual_network_name = azurerm_virtual_network.hubvnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space,9,5)]
  depends_on = [azurerm_resource_group.HUBResourceGroup,
    azurerm_virtual_network.hubvnet,
    azurerm_network_security_group.HUBNSG
  ]
}
resource "azurerm_subnet" "HBAGSubnet" {
  name = "app_gateway_subnet"
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  virtual_network_name = azurerm_virtual_network.hubvnet.name
  lifecycle {
    ignore_changes = ["address_prefixes"]
  }
  address_prefixes = [cidrsubnet(var.vnet_address_space,10,8 )]
}
resource "azurerm_subnet_network_security_group_association" "AAG-NSG" {
  network_security_group_id = azurerm_network_security_group.HUBNSG.id
  subnet_id = azurerm_subnet.HBAGSubnet.id
}
resource "azurerm_public_ip" "HBFWPIP" {
  allocation_method = "Static"
  location = azurerm_resource_group.HUBResourceGroup.location
  name = join("",[local.resource_prefix,"FPIP",var.env_seq])
  tags = {
    environment = local.env_tag
    SpokeType   = "HUB"
    CICDStage   = var.environment_name
  }
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  sku = "Standard"
}
resource "azurerm_public_ip" "HBAGPIP" {
  allocation_method = "Static"
  location = azurerm_resource_group.HUBResourceGroup.location
  name = join("",[local.resource_prefix,"APIP",var.env_seq])
  tags = {
    environment = local.env_tag
    SpokeType   = "HUB"
    CICDStage   = var.environment_name
  }
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  sku = "Standard"
}
resource "azurerm_log_analytics_workspace" "OMS" {
  location = azurerm_resource_group.HUBResourceGroup.location
  name = join("",[local.resource_prefix,"OMS",var.env_seq])
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  tags = {
    SpokeType   = "HUB"
    CICDStage   = var.environment_name
  }
  sku = "PerGB2018"
  retention_in_days = 30
}
resource "azurerm_firewall" "HBFRWL" {
  location = azurerm_resource_group.HUBResourceGroup.location
  name = join("",[local.resource_prefix,"AFW",var.env_seq])
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  sku_tier = "Standard"
  ip_configuration {
    name = "config1"
    public_ip_address_id = azurerm_public_ip.HBFWPIP.id
    subnet_id = azurerm_subnet.HBFWLSUBNET.id
  }
  tags = {
    environment = local.env_tag
    SpokeType   = "HUB"
    CICDStage   = var.environment_name
  }
  depends_on = [azurerm_public_ip.HBFWPIP,azurerm_subnet.HBFWLSUBNET]
}
resource "azurerm_firewall_network_rule_collection" "FWLRULE" {
  action = "Allow"
  azure_firewall_name = azurerm_firewall.HBFRWL.name
  name = "RULE1"
  priority = 100
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  rule {
    destination_addresses = ["*"]
    destination_ports = ["*"]
    name = "AllowVPN"
    protocols = ["TCP"]
    source_addresses = ["4.15.185.50/32", "213.86.156.212/32", "213.86.156.213/32", "63.236.5.205/32", "63.236.5.199/32", "8.243.153.34/32", "129.126.166.19/32", "129.126.166.20/32", "81.128.198.211/32", "203.111.163.174/32", "20.192.64.175/32", "20.190.42.250/32", "116.247.86.164/32", "179.191.97.66/32", "20.62.240.39/32", "52.168.0.151/32", "13.92.239.46/32"]
  }
}
resource "azurerm_application_gateway" "network" {
  name                = join("",[local.resource_prefix,"AAG",var.env_seq])
  resource_group_name = azurerm_resource_group.HUBResourceGroup.name
  location            = azurerm_resource_group.HUBResourceGroup.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
  }
  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }
  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.HBAGSubnet.id
  }
  frontend_port {
    name = local.frontend_port_name
    port = 80
  }
  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.HBAGPIP.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
  depends_on = [azurerm_subnet.HBAGSubnet]

}
 resource "azurerm_monitor_diagnostic_setting" "appgateway-oms" {
   name = "dignostic settings"
   target_resource_id = azurerm_application_gateway.network.id
   log_analytics_workspace_id = azurerm_log_analytics_workspace.OMS.id
   log {
     category = "ApplicationGatewayAccessLog"
     enabled = true
     retention_policy {
       enabled = true
       days = 30
     }
   }
   metric {
     category = "AllMetrics"
     retention_policy {
       enabled = true
       days = 30
     }
   }
   log {
     category = "ApplicationGatewayPerformanceLog"
     enabled = true
     retention_policy {
       enabled = true
       days = 30
     }
   }
   metric {
     category = "AllMetrics"
     retention_policy {
       enabled = true
       days = 30
     }
   }
   log {
     category = "ApplicationGatewayFirewallLog"
     enabled = true
     retention_policy {
       enabled = true
       days = 30
     }
   }
   metric {
     category = "AllMetrics"
     retention_policy {
       enabled = true
       days = 30
     }
   }
 }
output "HUB-VNET-ID" {
  value = azurerm_virtual_network.hubvnet.id
}