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

# --- 1. VPC и NAT Gateway для обновлений Backend ---
resource "yandex_vpc_network" "zoning_vpc" {
  name = "hw3-zoning-vpc"
}

resource "yandex_vpc_gateway" "nat_gw" {
  name = "hw3-nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private_rt" {
  name       = "hw3-private-nat-rt"
  network_id = yandex_vpc_network.zoning_vpc.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gw.id
  }
}

# --- 2. Три подсети (Frontend Public, Backend Private, DB Private) ---
resource "yandex_vpc_subnet" "frontend" {
  name           = "subnet-frontend-public"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.zoning_vpc.id
  v4_cidr_blocks = ["10.10.1.0/24"]
}

resource "yandex_vpc_subnet" "backend" {
  name           = "subnet-backend-private"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.zoning_vpc.id
  v4_cidr_blocks = ["10.10.2.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

resource "yandex_vpc_subnet" "db" {
  name           = "subnet-db-private"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.zoning_vpc.id
  v4_cidr_blocks = ["10.10.3.0/24"]
}

# --- 3. Группы безопасности (Микросегментация) ---

# SG Frontend: открыт из интернета на порт 80 (и 22 для управления)
resource "yandex_vpc_security_group" "sg_frontend" {
  name       = "sg-frontend"
  network_id = yandex_vpc_network.zoning_vpc.id

  ingress {
    protocol       = "TCP"
    description    = "Public HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Admin SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG Backend: порт 3000 доступен ТОЛЬКО из подсети Frontend (10.10.1.0/24)
resource "yandex_vpc_security_group" "sg_backend" {
  name       = "sg-backend"
  network_id = yandex_vpc_network.zoning_vpc.id

  ingress {
    protocol       = "TCP"
    description    = "App port 3000 from Frontend only"
    v4_cidr_blocks = ["10.10.1.0/24"]
    port           = 3000
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH jump from Frontend"
    v4_cidr_blocks = ["10.10.1.0/24"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG DB: порт 6000 доступен ТОЛЬКО из подсети Backend (10.10.2.0/24)
resource "yandex_vpc_security_group" "sg_db" {
  name       = "sg-db"
  network_id = yandex_vpc_network.zoning_vpc.id

  ingress {
    protocol       = "TCP"
    description    = "DB port 6000 from Backend only"
    v4_cidr_blocks = ["10.10.2.0/24"]
    port           = 6000
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH jump from Backend"
    v4_cidr_blocks = ["10.10.2.0/24"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 4. Виртуальные машины с HTTP-демонстраторами на портах 80, 3000, 6000 ---

resource "yandex_compute_instance" "vm_frontend" {
  name        = "vm-frontend"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 8
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.frontend.id
    ip_address         = "10.10.1.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg_frontend.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = <<-EOT
      #cloud-config
      runcmd:
        - mkdir -p /var/www/demo
        - echo "Tier 1: FRONTEND (Port 80) OK" > /var/www/demo/index.html
        - nohup python3 -m http.server 80 --directory /var/www/demo >/dev/null 2>&1 &
    EOT
  }
}

resource "yandex_compute_instance" "vm_backend" {
  name        = "vm-backend"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 8
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.backend.id
    ip_address         = "10.10.2.10"
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_backend.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = <<-EOT
      #cloud-config
      runcmd:
        - mkdir -p /var/www/demo
        - echo "Tier 2: BACKEND (Port 3000) OK" > /var/www/demo/index.html
        - nohup python3 -m http.server 3000 --directory /var/www/demo >/dev/null 2>&1 &
    EOT
  }
}

resource "yandex_compute_instance" "vm_db" {
  name        = "vm-db"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 8
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.db.id
    ip_address         = "10.10.3.10"
    nat                = false
    security_group_ids = [yandex_vpc_security_group.sg_db.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = <<-EOT
      #cloud-config
      runcmd:
        - mkdir -p /var/www/demo
        - echo "Tier 3: DATABASE (Port 6000) OK" > /var/www/demo/index.html
        - nohup python3 -m http.server 6000 --directory /var/www/demo >/dev/null 2>&1 &
    EOT
  }
}

output "frontend_public_ip" {
  value = yandex_compute_instance.vm_frontend.network_interface[0].nat_ip_address
}
