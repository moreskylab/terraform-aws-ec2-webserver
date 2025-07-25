I'll create an equivalent Terraform configuration for Google Cloud Platform (GCP) based on your AWS setup.

````hcl
# Configure the Google Cloud Provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.1"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = "asia-south1"  # Equivalent to ap-south-1
  zone    = "asia-south1-a"
}

# Variable for project ID
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

# Generate a random suffix for global uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Create a VPC network
resource "google_compute_network" "main" {
  name                    = "tf-main-network"
  auto_create_subnetworks = false
}

# Create a public subnet
resource "google_compute_subnetwork" "public" {
  name          = "tf-public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "asia-south1"
  network       = google_compute_network.main.id
}

# Create a firewall rule for HTTP traffic
resource "google_compute_firewall" "allow_http" {
  name    = "tf-allow-http"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
}

# Create a firewall rule for SSH traffic
resource "google_compute_firewall" "allow_ssh" {
  name    = "tf-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]  # In production, restrict this to your IP
  target_tags   = ["web-server"]
}

# Create a Cloud Storage bucket for logs
resource "google_storage_bucket" "logs" {
  name          = "tf-web-server-logs-${random_id.suffix.hex}"
  location      = "ASIA-SOUTH1"
  force_destroy = true

  # Block public access
  public_access_prevention = "enforced"

  labels = {
    name = "tf-web-server-logs"
  }
}

# Create a service account for the VM
resource "google_service_account" "web_server" {
  account_id   = "tf-web-server-sa"
  display_name = "Terraform Web Server Service Account"
  description  = "Service account for web server VM to upload logs to Cloud Storage"
}

# Grant the service account storage object admin permissions
resource "google_project_iam_member" "storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.web_server.email}"

  condition {
    title       = "bucket_access"
    description = "Access to specific bucket only"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.logs.name}/\")"
  }
}

# Create a startup script template
locals {
  startup_script = templatefile("${path.module}/startup-script.sh", {
    bucket_name = google_storage_bucket.logs.name
  })
}

# Create the Compute Engine instance
resource "google_compute_instance" "web" {
  name         = "tf-web-server"
  machine_type = "e2-micro"  # Equivalent to t2.micro
  zone         = "asia-south1-a"
  tags         = ["web-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"  # Ubuntu 20.04 LTS
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.main.name
    subnetwork = google_compute_subnetwork.public.name
    
    # Assign a public IP
    access_config {
      # Ephemeral public IP
    }
  }

  # Attach the service account
  service_account {
    email  = google_service_account.web_server.email
    scopes = ["cloud-platform"]
  }

  # Startup script for web server setup
  metadata_startup_script = local.startup_script

  # SSH key metadata (add your public key here)
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"  # Update this path to your public key
  }

  labels = {
    name = "tf-web-server"
  }
}

# Output the web server's public IP
output "web_server_public_ip" {
  value = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}

# Output the storage bucket name
output "logs_bucket" {
  value = google_storage_bucket.logs.name
}

# Output the service account email
output "service_account_email" {
  value = google_service_account.web_server.email
}
````

Now create the startup script:

````bash
#!/bin/bash

# Update system packages
apt-get update -y
apt-get upgrade -y

# Install Apache web server
apt-get install -y apache2

# Start and enable Apache
systemctl start apache2
systemctl enable apache2

# Create a simple HTML page
cat > /var/www/html/index.html << 'HTML'
<html>
<head><title>Hello from Terraform on GCP</title></head>
<body><h1>Hello from Terraform on GCP</h1></body>
</html>
HTML

# Install Google Cloud SDK (if not already installed)
if ! command -v gcloud &> /dev/null; then
    curl https://sdk.cloud.google.com | bash
    exec -l $SHELL
    gcloud init
fi

# Set up log rotation to Cloud Storage
cat > /etc/cron.daily/apache-log-gcs << 'CRON'
#!/bin/bash
DATE=$(date +%Y-%m-%d)
# Upload Apache access logs to Cloud Storage
gsutil cp /var/log/apache2/access.log gs://${bucket_name}/$DATE/access.log
CRON

chmod +x /etc/cron.daily/apache-log-gcs

# Test the web server
curl -f http://localhost/ || echo "Web server not responding"

# Log completion
echo "Web server setup completed at $(date)" >> /var/log/startup-script.log
````

Create a terraform.tfvars file to specify your project ID:

````hcl
project_id = "your-gcp-project-id"
````

Create a variables.tf file for better organization:

````hcl
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "asia-south1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "asia-south1-a"
}
````

## Key Differences from AWS:

1. **Project**: GCP organizes resources under projects instead of AWS accounts
2. **VPC Network**: GCP equivalent of AWS VPC with manual subnet creation
3. **Firewall Rules**: GCP equivalent of AWS Security Groups with tag-based targeting
4. **Cloud Storage**: GCP equivalent of S3 buckets
5. **Service Account**: GCP equivalent of IAM roles for secure access
6. **Compute Engine**: GCP equivalent of EC2 instances
7. **Machine Types**: `e2-micro` is GCP's equivalent to AWS `t2.micro`
8. **Metadata**: GCP uses metadata for startup scripts and SSH keys

## To deploy this configuration:

1. Make sure you have Google Cloud SDK installed and authenticated:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. Update the project ID in terraform.tfvars
3. Update the SSH public key path in the configuration
4. Run:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

The configuration creates a web server that automatically uploads its logs to Cloud Storage using service account authentication, equivalent to your AWS setup with IAM roles and S3.