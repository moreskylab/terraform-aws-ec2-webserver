I'll create Mermaid.js diagrams representing the equivalent Terraform configurations for AWS, GCP, and Azure. These diagrams will show the infrastructure components and their relationships.


# AWS Infrastructure Diagram

```mermaid
graph TB
    subgraph "AWS Cloud"
        subgraph "VPC (10.0.0.0/16)"
            subgraph "Public Subnet (10.0.1.0/24)"
                EC2[EC2 Instance<br/>t2.micro<br/>Amazon Linux 2]
            end
            
            IGW[Internet Gateway]
            RT[Route Table<br/>0.0.0.0/0 → IGW]
            SG[Security Group<br/>HTTP: 80<br/>SSH: 22]
        end
        
        S3[S3 Bucket<br/>tf-web-server-logs-xxxx<br/>Private Access Only]
        
        subgraph "IAM"
            Role[IAM Role<br/>EC2S3UploaderRole]
            Policy[IAM Policy<br/>S3 Upload Permissions]
            Profile[Instance Profile<br/>EC2S3UploaderProfile]
        end
    end
    
    Internet((Internet))
    User[User]
    
    %% Connections
    Internet --> IGW
    IGW --> RT
    RT --> EC2
    EC2 --> SG
    EC2 --> Profile
    Profile --> Role
    Role --> Policy
    Policy --> S3
    User --> Internet
    
    %% Data Flow
    EC2 -.->|Upload Logs<br/>Daily Cron| S3
    EC2 -.->|Serves Web<br/>Port 80| Internet
    
    %% Styling
    classDef compute fill:#ff9999
    classDef network fill:#99ccff
    classDef storage fill:#99ff99
    classDef security fill:#ffcc99
    
    class EC2 compute
    class IGW,RT,SG network
    class S3 storage
    class Role,Policy,Profile security
```



# GCP Infrastructure Diagram

```mermaid
graph TB
    subgraph "Google Cloud Project"
        subgraph "VPC Network (tf-main-network)"
            subgraph "Public Subnet (10.0.1.0/24)"
                VM[Compute Engine<br/>e2-micro<br/>Ubuntu 20.04 LTS]
            end
            
            FW1[Firewall Rule<br/>allow-http<br/>Port 80]
            FW2[Firewall Rule<br/>allow-ssh<br/>Port 22]
        end
        
        GCS[Cloud Storage Bucket<br/>tf-web-server-logs-xxxx<br/>Private Access Only]
        
        subgraph "IAM"
            SA[Service Account<br/>tf-web-server-sa]
            IAM_BIND[IAM Binding<br/>Storage Object Admin]
        end
    end
    
    Internet((Internet))
    User[User]
    
    %% Connections
    Internet --> VM
    VM --> FW1
    VM --> FW2
    VM --> SA
    SA --> IAM_BIND
    IAM_BIND --> GCS
    User --> Internet
    
    %% Data Flow
    VM -.->|Upload Logs<br/>Daily Cron<br/>gsutil| GCS
    VM -.->|Serves Web<br/>Port 80| Internet
    
    %% Styling
    classDef compute fill:#ff9999
    classDef network fill:#99ccff
    classDef storage fill:#99ff99
    classDef security fill:#ffcc99
    
    class VM compute
    class FW1,FW2 network
    class GCS storage
    class SA,IAM_BIND security
```



# Azure Infrastructure Diagram

```mermaid
graph TB
    subgraph "Azure Subscription"
        subgraph "Resource Group (rg-tf-webserver)"
            subgraph "Virtual Network (10.0.0.0/16)"
                subgraph "Public Subnet (10.0.1.0/24)"
                    VM[Virtual Machine<br/>Standard_B1s<br/>Ubuntu 20.04 LTS]
                    NIC[Network Interface]
                    PIP[Public IP Address<br/>Static]
                end
                
                NSG[Network Security Group<br/>HTTP: 80<br/>SSH: 22]
            end
            
            SA[Storage Account<br/>stweblogs-xxxx<br/>Private Access Only]
            SC[Storage Container<br/>weblogs]
            
            subgraph "Identity"
                MI[Managed Identity<br/>mi-tf-webserver]
                RBAC[RBAC Assignment<br/>Storage Blob Data Contributor]
            end
        end
    end
    
    Internet((Internet))
    User[User]
    
    %% Connections
    Internet --> PIP
    PIP --> NIC
    NIC --> VM
    VM --> NSG
    VM --> MI
    MI --> RBAC
    RBAC --> SA
    SA --> SC
    User --> Internet
    
    %% Data Flow
    VM -.->|Upload Logs<br/>Daily Cron<br/>az storage| SC
    VM -.->|Serves Web<br/>Port 80| Internet
    
    %% Styling
    classDef compute fill:#ff9999
    classDef network fill:#99ccff
    classDef storage fill:#99ff99
    classDef security fill:#ffcc99
    
    class VM,NIC compute
    class PIP,NSG network
    class SA,SC storage
    class MI,RBAC security
```



# Multi-Cloud Infrastructure Comparison

```mermaid
graph TB
    subgraph "AWS"
        AWS_EC2[EC2 Instance<br/>t2.micro]
        AWS_S3[S3 Bucket]
        AWS_IAM[IAM Role]
        AWS_VPC[VPC + Subnet]
        AWS_SG[Security Group]
        
        AWS_EC2 --> AWS_IAM
        AWS_IAM --> AWS_S3
        AWS_EC2 --> AWS_VPC
        AWS_EC2 --> AWS_SG
    end
    
    subgraph "GCP"
        GCP_VM[Compute Engine<br/>e2-micro]
        GCP_GCS[Cloud Storage]
        GCP_SA[Service Account]
        GCP_VPC[VPC Network]
        GCP_FW[Firewall Rules]
        
        GCP_VM --> GCP_SA
        GCP_SA --> GCP_GCS
        GCP_VM --> GCP_VPC
        GCP_VM --> GCP_FW
    end
    
    subgraph "Azure"
        AZ_VM[Virtual Machine<br/>Standard_B1s]
        AZ_SA[Storage Account]
        AZ_MI[Managed Identity]
        AZ_VNET[Virtual Network]
        AZ_NSG[Network Security Group]
        
        AZ_VM --> AZ_MI
        AZ_MI --> AZ_SA
        AZ_VM --> AZ_VNET
        AZ_VM --> AZ_NSG
    end
    
    Internet((Internet))
    
    AWS --> Internet
    GCP --> Internet
    Azure --> Internet
    
    %% Equivalence arrows
    AWS_EC2 -.->|Equivalent| GCP_VM
    GCP_VM -.->|Equivalent| AZ_VM
    
    AWS_S3 -.->|Equivalent| GCP_GCS
    GCP_GCS -.->|Equivalent| AZ_SA
    
    AWS_IAM -.->|Equivalent| GCP_SA
    GCP_SA -.->|Equivalent| AZ_MI
    
    %% Styling
    classDef aws fill:#ff9999
    classDef gcp fill:#99ccff
    classDef azure fill:#99ff99
    
    class AWS_EC2,AWS_S3,AWS_IAM,AWS_VPC,AWS_SG aws
    class GCP_VM,GCP_GCS,GCP_SA,GCP_VPC,GCP_FW gcp
    class AZ_VM,AZ_SA,AZ_MI,AZ_VNET,AZ_NSG azure
```



# Data Flow Comparison Across Cloud Providers

```mermaid
sequenceDiagram
    participant U as User
    participant I as Internet
    participant AWS as AWS EC2
    participant S3 as AWS S3
    participant GCP as GCP VM
    participant GCS as Cloud Storage
    participant AZ as Azure VM
    participant BLOB as Azure Blob

    Note over U,BLOB: Web Request Flow
    
    U->>I: HTTP Request
    I->>AWS: Route to EC2
    AWS->>I: Serve Web Page
    I->>U: Return Response
    
    I->>GCP: Route to VM
    GCP->>I: Serve Web Page
    
    I->>AZ: Route to VM
    AZ->>I: Serve Web Page

    Note over U,BLOB: Log Upload Flow (Daily Cron)
    
    AWS->>S3: aws s3 cp logs
    Note right of S3: IAM Role Authentication
    
    GCP->>GCS: gsutil cp logs
    Note right of GCS: Service Account Authentication
    
    AZ->>BLOB: az storage blob upload
    Note right of BLOB: Managed Identity Authentication
```


## Component Mapping Table

Here's a quick reference table showing the equivalent components across cloud providers:

| Function | AWS | GCP | Azure |
|----------|-----|-----|-------|
| **Compute** | EC2 Instance (t2.micro) | Compute Engine (e2-micro) | Virtual Machine (Standard_B1s) |
| **Storage** | S3 Bucket | Cloud Storage Bucket | Storage Account + Container |
| **Network** | VPC + Subnet | VPC Network + Subnet | Virtual Network + Subnet |
| **Security** | Security Group | Firewall Rules | Network Security Group |
| **Identity** | IAM Role + Instance Profile | Service Account | Managed Identity |
| **CLI Tool** | AWS CLI | gcloud/gsutil | Azure CLI |
| **Auth Method** | IAM Role | Service Account | Managed Identity |
| **Region** | ap-south-1 | asia-south1 | East US |

These diagrams show how the same web server architecture with log uploading capabilities can be implemented across different cloud providers using their native services and authentication mechanisms.