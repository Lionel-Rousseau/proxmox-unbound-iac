terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.107.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}

resource "proxmox_virtual_environment_container" "unbound_01" {
  node_name     = var.proxmox_node
  vm_id         = var.lxc_vmid
  description   = "LXC Unbound DNS resolver - managed by Terraform"
  tags          = ["dns", "unbound", "iac"]
  unprivileged  = true
  started       = true
  start_on_boot = true

  features {
    nesting = true
  }

  operating_system {
    type             = "debian"
    template_file_id = var.debian_template
  }

  cpu {
    cores = var.lxc_cpu_cores
  }

  memory {
    dedicated = var.lxc_memory_mb
    swap      = 0
  }

  disk {
    datastore_id = var.storage
    size         = var.lxc_disk_gb
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  initialization {
    hostname = var.lxc_hostname

    ip_config {
      ipv4 {
        address = var.lxc_ip_cidr
        gateway = var.gateway
      }

      dynamic "ipv6" {
        for_each = var.enable_ipv6_autoconf ? [1] : []
        content {
          address = "auto"
        }
      }
    }

    dns {
      servers = var.bootstrap_dns_servers
    }

    user_account {
      keys = [
        trimspace(file(pathexpand(var.ssh_public_key_path)))
      ]
    }
  }
}
