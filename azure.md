I'll create an equivalent Terraform configuration for Azure that provisions a web server with logging capabilities similar to your AWS setup.

````hcl
# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.1"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Generate a random suffix for global uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Create a resource group
resource "azurerm_resource_group" "main" {
  name     = "rg-tf-webserver"
  location = "East US"
}

# Create a virtual network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-tf-main"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Create a public subnet
resource "azurerm_subnet" "public" {
  name                 = "subnet-tf-public"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create a Network Security Group
resource "azurerm_network_security_group" "web" {
  name                = "nsg-tf-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "HTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   * "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # In production, restrict this to your IP
    destination_address_prefix = "*"
  }
}

# Associate Network Security Group to the subnet
resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# Create a storage account for logs
resource "azurerm_storage_account" "logs" {
  name                     = "stweblogs${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Block public access
  public_network_access_enabled = false
  
  tags = {
    Name = "tf-web-server-logs"
  }
}

# Create a storage container for logs
resource "azurerm_storage_container" "logs" {
  name                  = "weblogs"
  storage_account_name  = azurerm_storage_account.logs.name
  container_access_type = "private"
}

# Create a user-assigned managed identity
resource "azurerm_user_assigned_identity" "web" {
  name                = "mi-tf-webserver"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Assign Storage Blob Data Contributor role to the managed identity
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.logs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.web.principal_id
}

# Create a public IP
resource "azurerm_public_ip" "web" {
  name                = "pip-tf-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                = "Standard"
}

# Create a network interface
resource "azurerm_network_interface" "web" {
  name                = "nic-tf-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web.id
  }
}

# Create the virtual machine
resource "azurerm_linux_virtual_machine" "web" {
  name                = "vm-tf-webserver"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_B1s"  # Equivalent to t2.micro
  admin_username      = "azureuser"
  
  # Disable password authentication
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.web.id,
  ]

  # Assign the managed identity
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.web.id]
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")  # Update this path to your public key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Ubuntu 20.04 LTS
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    storage_account_name = azurerm_storage_account.logs.name
    container_name       = azurerm_storage_container.logs.name
  }))

  tags = {
    Name = "tf-web-server"
  }
}

# Output the web server's public IP
output "web_server_public_ip" {
  value = azurerm_public_ip.web.ip_address
}

# Output the storage account name
output "logs_storage_account" {
  value = azurerm_storage_account.logs.name
}

# Output the storage container name
output "logs_container" {
  value = azurerm_storage_container.logs.name
}
````

Now create the cloud-init configuration file:

````yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - apache2
  - azure-cli

write_files:
  - path: /var/www/html/index.html
    content: |
      <html>
      <head><title>Hello from Terraform on Azure</title></head>
      <body><h1>Hello from Terraform on Azure</h1></body>
      </html>
    permissions: '0644'
  
  - path: /etc/cron.daily/apache-log-azure
    content: |
      #!/bin/bash
      DATE=$(date +%Y-%m-%d)
      # Upload Apache access logs to Azure Storage
      az storage blob upload \
        --account-name ${storage_account_name} \
        --container-name ${container_name} \
        --name $DATE/access.log \
        --file /var/log/apache2/access.log \
        --auth-mode login
    permissions: '0755'

runcmd:
  - systemctl start apache2
  - systemctl enable apache2
  - # Login to Azure using managed identity
  - az login --identity
  - # Test the web server
  - curl -f http://localhost/ || echo "Web server not responding"
````

## Key Differences from AWS:

1. **Resource Group**: Azure requires a resource group to contain all resources
2. **Virtual Network**: Azure equivalent of AWS VPC
3. **Network Security Group**: Azure equivalent of AWS Security Groups
4. **Storage Account**: Azure equivalent of S3 bucket for blob storage
5. **Managed Identity**: Azure equivalent of IAM roles for secure access
6. **Linux Virtual Machine**: Azure equivalent of EC2 instance
7. **Cloud-init**: Uses YAML format instead of bash script for initialization

## To deploy this configuration:

1. Make sure you have Azure CLI installed and are logged in
2. Update the SSH public key path in the configuration
3. Run:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

The configuration creates a web server that automatically uploads its logs to Azure Blob Storage using managed identity authentication, similar to your AWS setup.

Similar code found with 1 license type