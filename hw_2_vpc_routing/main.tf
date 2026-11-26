terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 1.6.0"
}

provider "yandex" {
  cloud_id  = "b1guapctjkvac9h6i72h"
  folder_id = "b1gi63p5vpc29cv73nqa"
  zone      = "ru-central1-a"
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# --- 1. Создаём 3 изолированные VPC ---
resource "yandex_vpc_network" "vpc1" { name = "hw2-vpc-1" }
resource "yandex_vpc_network" "vpc2" { name = "hw2-vpc-2" }
resource "yandex_vpc_network" "vpc3" { name = "hw2-vpc-3" }

# --- 2. Создаём таблицы маршрутизации (Routing Tables) ---
resource "yandex_vpc_route_table" "rt_vpc1" {
  name       = "rt-vpc1"
  network_id = yandex_vpc_network.vpc1.id

  static_route {
    destination_prefix = "10.3.0.0/24"
    next_hop_address   = "10.1.0.254"
  }
}

resource "yandex_vpc_route_table" "rt_vpc2" {
  name       = "rt-vpc2"
  network_id = yandex_vpc_network.vpc2.id

  static_route {
    destination_prefix = "10.3.0.0/24"
    next_hop_address   = "10.2.0.254"
  }
}

resource "yandex_vpc_route_table" "rt_vpc3" {
  name       = "rt-vpc3"
  network_id = yandex_vpc_network.vpc3.id

  static_route {
    destination_prefix = "10.1.0.0/24"
    next_hop_address   = "10.3.0.254"
  }

  static_route {
    destination_prefix = "10.2.0.0/24"
    next_hop_address   = "10.3.0.254"
  }
}

# --- 3. Создаём 3 подсети и привязываем к ним таблицы маршрутизации ---
resource "yandex_vpc_subnet" "sub1" {
  name           = "subnet-vpc1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.vpc1.id
  v4_cidr_blocks = ["10.1.0.0/24"]
  route_table_id = yandex_vpc_route_table.rt_vpc1.id
}

resource "yandex_vpc_subnet" "sub2" {
  name           = "subnet-vpc2"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.vpc2.id
  v4_cidr_blocks = ["10.2.0.0/24"]
  route_table_id = yandex_vpc_route_table.rt_vpc2.id
}

resource "yandex_vpc_subnet" "sub3" {
  name           = "subnet-vpc3"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.vpc3.id
  v4_cidr_blocks = ["10.3.0.0/24"]
  route_table_id = yandex_vpc_route_table.rt_vpc3.id
}

# --- 4. ВМ-маршрутизатор с 3 сетевыми интерфейсами (соединяет все 3 VPC) ---
resource "yandex_compute_instance" "router" {
  name        = "vm-vpc-router"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.sub1.id
    ip_address = "10.1.0.254"
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.sub2.id
    ip_address = "10.2.0.254"
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.sub3.id
    ip_address = "10.3.0.254"
    nat        = true
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = <<-EOT
      #cloud-config
      runcmd:
        - sysctl -w net.ipv4.ip_forward=1
        - iptables -P FORWARD DROP
        - iptables -A FORWARD -s 10.3.0.0/24 -d 10.1.0.0/24 -j ACCEPT
        - iptables -A FORWARD -s 10.1.0.0/24 -d 10.3.0.0/24 -j ACCEPT
        - iptables -A FORWARD -s 10.3.0.0/24 -d 10.2.0.0/24 -j ACCEPT
        - iptables -A FORWARD -s 10.2.0.0/24 -d 10.3.0.0/24 -j ACCEPT
    EOT
  }
}

# --- 5. Тестовые хосты в VPC-1, VPC-2 и VPC-3 ---
resource "yandex_compute_instance" "vm1" {
  name        = "vm-in-vpc1"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.sub1.id
    ip_address = "10.1.0.10"
    nat        = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}

resource "yandex_compute_instance" "vm2" {
  name        = "vm-in-vpc2"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.sub2.id
    ip_address = "10.2.0.10"
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}

resource "yandex_compute_instance" "vm3" {
  name        = "vm-in-vpc3"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.sub3.id
    ip_address = "10.3.0.10"
    nat        = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}

output "vm3_public_ip" {
  value = yandex_compute_instance.vm3.network_interface[0].nat_ip_address
}

output "vm1_public_ip" {
  value = yandex_compute_instance.vm1.network_interface[0].nat_ip_address
}
