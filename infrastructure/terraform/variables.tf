variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-aks-regulated-demo"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-regulated-demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.34"
}

variable "system_node_count" {
  description = "Number of system nodes"
  type        = number
  default     = 3
}

variable "system_node_vm_size" {
  description = "VM size for system nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "user_node_count" {
  description = "Number of user workload nodes"
  type        = number
  default     = 3
}

variable "user_node_vm_size" {
  description = "VM size for user workload nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    Project     = "AKS-Regulated-Enterprise"
    ManagedBy   = "Terraform"
  }
}

variable "enable_defender" {
  description = "Enable Microsoft Defender for Containers"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 90
}
