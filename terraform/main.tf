variable "username" {
  default = "azureuser"
}

variable "size" {
  default = "Standard_B1s"
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "RG" {
  name     = "RG"
  location = "West Europe"
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "main" {
  name                = "main"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  address_space       = ["10.0.0.0/16"]
}

# Azure Files (EFS)
resource "azurerm_storage_account" "azure_files" {
  name                     = "azurefilesforproject"
  resource_group_name      = azurerm_resource_group.RG.name
  location                 = azurerm_resource_group.RG.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "FileStorage"

  # NFS shares require HTTPS-only to be disabled and public network access restricted
  https_traffic_only_enabled = false

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.private_subnet.id]
  }
}

resource "azurerm_storage_share" "shared_data" {
  name                 = "shared-data"
  storage_account_id  = azurerm_storage_account.azure_files.id
  quota                = 100  # GB
  enabled_protocol     = "NFS"
}

resource "azurerm_storage_share" "storage_share" {
  name               = "storage-share"
  storage_account_id = azurerm_storage_account.azure_files.id
  quota              = 100
  enabled_protocol   = "NFS"
}

# Subnets
resource "azurerm_subnet" "public_subnet" {
    name             = "public_subnet"
    resource_group_name  = azurerm_resource_group.RG.name
    virtual_network_name = azurerm_virtual_network.main.name
    address_prefixes = ["10.0.0.0/25"]

    depends_on = [azurerm_virtual_network.main]
}

resource "azurerm_subnet" "private_subnet" {
    name                 = "private_subnet"
    resource_group_name  = azurerm_resource_group.RG.name
    virtual_network_name = azurerm_virtual_network.main.name
    address_prefixes     = ["10.0.0.128/25"]
    
    service_endpoint {
      service = "Microsoft.Storage"
    } 

    depends_on = [azurerm_virtual_network.main]
}

# Security Groups
resource "azurerm_network_security_group" "nsg_public" {
  name                = "publicSecurityGroup"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  security_rule {
    name                       = "test1"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "test2"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg_private" {
  name                = "privateSecurityGroup"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  security_rule {
    name                       = "sr1"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "10.0.0.0/25"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh-from-public"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.0.0/25"
    destination_address_prefix = "*"
  }
}

# Subnet-level association
resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_private.id
}

# Route Table
resource "azurerm_route_table" "main" {
  name                = "route-table"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  route {
    name           = "route1"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  tags = {
    Name = "rt-lh-dev-westeu"
  }

  depends_on = [azurerm_virtual_network.main]
}

resource "azurerm_subnet_route_table_association" "public" {
  subnet_id      = azurerm_subnet.public_subnet.id
  route_table_id = azurerm_route_table.main.id
}

# Public IP
resource "azurerm_public_ip" "public_vm_ip" {
  name                = "public-vm-ip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "ansible_master_ip" {
  name                = "ansible-master-ip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "ansible_master_nic" {
  name                = "ansible-master-nic"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id         = azurerm_public_ip.ansible_master_ip.id
  }
}

resource "azurerm_network_interface" "public_nic" {
  name                = "public_nic"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_vm_ip.id
  }
}

resource "azurerm_network_interface" "private_nic" {
  name                = "private_nic"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "private_nic_2" {
  name                = "private_nic_2"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# VMs
# First public node
resource "azurerm_linux_virtual_machine" "public_node" {
  name                  = "public-vm"
  resource_group_name = azurerm_resource_group.RG.name
  location              = azurerm_resource_group.RG.location
  size                = "${var.size}"
  admin_username      = "${var.username}"
  network_interface_ids = [
    azurerm_network_interface.public_nic.id,
  ]
  //custom_data = base64encode(templatefile("${path.module}/cloud-init-public.yaml", {
    //  index_js = file("${path.module}/public-app/index.js")
      //private_key = file("~/.ssh/id_rsa")
   // }))

  admin_ssh_key {
    username   = "${var.username}"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# First private node
resource "azurerm_linux_virtual_machine" "private_node" {
  name                  = "private-vm"
  resource_group_name = azurerm_resource_group.RG.name
  location              = azurerm_resource_group.RG.location
  size                = "${var.size}"
  admin_username      = "${var.username}"
  network_interface_ids = [
    azurerm_network_interface.private_nic.id,
  ]
  //custom_data = base64encode(templatefile("${path.module}/cloud-init-private.yaml", {
    //seed_data = file("${path.module}/private-app/index.js")
    //seed_json = file("${path.module}/private-app/seed-data.json")
  //}))

   admin_ssh_key {
    username   = "${var.username}"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# Second private node
resource "azurerm_linux_virtual_machine" "private_node2" {
  name                  = "private-vm2"
  resource_group_name = azurerm_resource_group.RG.name
  location              = azurerm_resource_group.RG.location
  size                = var.size
  admin_username      = var.username
  network_interface_ids = [
    azurerm_network_interface.private_nic_2.id,
  ]

   admin_ssh_key {
    username   = "${var.username}"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# Ansible Master
resource "azurerm_linux_virtual_machine" "ansible_master" {
  name                  = "ansible-master"
  resource_group_name = azurerm_resource_group.RG.name
  location              = azurerm_resource_group.RG.location
  size                = var.size
  admin_username      = var.username
  network_interface_ids = [azurerm_network_interface.ansible_master_nic.id]

  admin_ssh_key {
    username   = var.username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #cloud-config
    packages:
      - python3
      - python3-pip
    runcmd:
      - pip3 install ansible docker
  EOF
  )
}

## Outputs:
output "storage_account_name" {
  value = azurerm_storage_account.azure_files.name
}

output "file_share_name" {
  value = azurerm_storage_share.shared_data.name
}

# Frontend
output "public_vm_ip" {
  value = azurerm_public_ip.public_vm_ip.ip_address
}

# Frontend private IP
output "public_vm_private_ip" {
  value = azurerm_network_interface.public_nic.private_ip_address
}

# Backend1
output "private_vm_1_ip" {
  value = azurerm_network_interface.private_nic.private_ip_address
}

# Backend2
output "private_vm_2_ip" {
  value = azurerm_network_interface.private_nic_2.private_ip_address
}

# Master public IP
output "ansible_master_ip" {
  value = azurerm_public_ip.ansible_master_ip.ip_address
}

# Copy IP addresses to ansible inventory
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
    [frontend]
    public-vm ansible_host=${azurerm_public_ip.public_vm_ip.ip_address} ansible_user=${var.username}

    [backend]
    private-vm-1 ansible_host=${azurerm_network_interface.private_nic.private_ip_address} ansible_user=${var.username}
    private-vm-2 ansible_host=${azurerm_network_interface.private_nic_2.private_ip_address} ansible_user=${var.username}

    [ansible_master]
    ansible-master ansible_host=${azurerm_public_ip.ansible_master_ip.ip_address} ansible_user=${var.username}

    [all:vars]
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
    ansible_python_interpreter=/usr/bin/python3
  EOT
}