variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API endpoint, for example https://proxmox.example.local:8006/api2/json"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token in the form user@realm!tokenid=secret"
}

variable "proxmox_insecure" {
  type        = bool
  default     = false
  description = "Set to true only when using a self-signed Proxmox certificate in a lab."
}

variable "proxmox_node" {
  type        = string
  description = "Target Proxmox node name."
}

variable "lxc_vmid" {
  type        = number
  default     = 150
  description = "Proxmox VMID for the Unbound LXC."
}

variable "lxc_hostname" {
  type        = string
  default     = "lxc-unbound-01"
  description = "Hostname configured inside the LXC."
}

variable "debian_template" {
  type        = string
  description = "LXC template file ID, for example local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "storage" {
  type        = string
  default     = "local-zfs"
  description = "Storage supporting rootdir content."
}

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Proxmox bridge connected to the LAN."
}

variable "vlan_id" {
  type        = number
  default     = 0
  description = "VLAN tag. Use 0 for untagged."
}

variable "lxc_ip_cidr" {
  type        = string
  description = "Static IPv4 address with CIDR, for example 10.10.10.53/24."
}

variable "gateway" {
  type        = string
  description = "Default IPv4 gateway."
}

variable "bootstrap_dns_servers" {
  type        = list(string)
  default     = ["1.1.1.1"]
  description = "Temporary DNS resolvers used during initial provisioning."
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
  description = "SSH public key injected into the root account."
}

variable "lxc_cpu_cores" {
  type        = number
  default     = 2
}

variable "lxc_memory_mb" {
  type        = number
  default     = 1024
}

variable "lxc_disk_gb" {
  type        = number
  default     = 8
}

variable "enable_ipv6_autoconf" {
  type        = bool
  default     = false
}
