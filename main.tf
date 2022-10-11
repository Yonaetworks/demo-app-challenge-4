#Terraform Configuration

terraform {
  required_version = ">= 1.2.0"
  required_providers {
    azurerm={
        source = "hashicorp/azurerm"
        version = "3.15.0"
    }
  }
}

#Provider configuration
provider "azurerm" {
    features {}

}

#Create Resource Group

resource "azurerm_resource_group" "rg-aks-demoapp" {
  name     = "rg-aks-demoapp"
  location = "eastus2"
}

#Create VNET

resource "azurerm_virtual_network" "vnet-aks" {
  name                = "vnet-aks"
  location            = azurerm_resource_group.rg-aks-demoapp.location
  resource_group_name = azurerm_resource_group.rg-aks-demoapp.name
  address_space       = ["10.12.128.0/18"]
}

#Create Route Table

resource "azurerm_route_table" "rt-aks" {
  name                          = "rt-aks"
  location                      = azurerm_resource_group.rg-aks-demoapp.location
  resource_group_name           = azurerm_resource_group.rg-aks-demoapp.name
  disable_bgp_route_propagation = false

  route {
    name                   = "DEFAULT-TO-AZ-NET"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "Internet"
  }
 
}

#Create Subnet

resource "azurerm_subnet" "subnet-aks-demoapp-nodes" {
  name                 = "subnet-aks-demoapp-nodes"
  virtual_network_name = azurerm_virtual_network.vnet-aks.name
  resource_group_name  = azurerm_resource_group.rg-aks-demoapp.name
  address_prefixes     = ["10.12.128.0/24"]
}

#Create Subnet to Route Table Association

resource "azurerm_subnet_route_table_association" "aks-rt-subnet-assoc" {
  subnet_id      = azurerm_subnet.subnet-aks-demoapp-nodes.id
  route_table_id = azurerm_route_table.rt-aks.id
}

# Create Azure Container Registry

resource "azurerm_container_registry" "acrdemoapp" {
  name                = "acrdemoappgbh01"
  resource_group_name = azurerm_resource_group.rg-aks-demoapp.name
  location            = azurerm_resource_group.rg-aks-demoapp.location
  sku                 = "Premium"
}

resource "azurerm_container_registry" "acrdemoapp-dev" {
  name                = "acrdemoappgbh01-dev"
  resource_group_name = azurerm_resource_group.rg-aks-demoapp.name
  location            = azurerm_resource_group.rg-aks-demoapp.location
  sku                 = "Premium"
}

#Create AKS Cluster

resource "azurerm_kubernetes_cluster" "aks-cluster-demoapp" {
  name                = "aks-cluster-demoapp"
  location            = azurerm_resource_group.rg-aks-demoapp.location
  resource_group_name = azurerm_resource_group.rg-aks-demoapp.name
  dns_prefix          = "aks-cluster-demoapp"
  node_resource_group = "aks-cluster-demoapp-nodes"
  
  default_node_pool {
    name           = "sidnodes01"
    node_count     = 2
    vm_size        = "Standard_D2as_v4"
    vnet_subnet_id = azurerm_subnet.subnet-aks-demoapp-nodes.id
    os_disk_size_gb = 50
    max_pods = 100
  }

  network_profile {
    network_plugin    = "azure"
    dns_service_ip = "10.12.0.10"
    outbound_type = "loadBalancer"
    service_cidr = "10.12.0.0/18"
    docker_bridge_cidr = "172.17.0.0/16"

  }

  identity {
    type = "SystemAssigned"
  }
}

# Create ACRs and Cluster association

resource "azurerm_role_assignment" "acr-to-aks-cluster" {
  principal_id                     = azurerm_kubernetes_cluster.aks-cluster-demoapp.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acrdemoapp.id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "acr-to-aks-cluster-dev" {
  principal_id                     = azurerm_kubernetes_cluster.aks-cluster-demoapp.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acrdemoapp-dev.id
  skip_service_principal_aad_check = true
}