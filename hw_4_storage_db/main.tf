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

# --- 1. Сеть для стенда ---
resource "yandex_vpc_network" "net" {
  name = "hw4-storage-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "hw4-storage-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.20.1.0/24"]
}

# --- 2. Сервисный аккаунт и ключи для S3 ---
resource "yandex_iam_service_account" "s3_sa" {
  name = "hw4-storage-sa"
}

resource "yandex_resourcemanager_folder_iam_member" "s3_admin" {
  folder_id = "b1gi63p5vpc29cv73nqa"
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.s3_sa.id}"
}

resource "yandex_iam_service_account_static_access_key" "s3_keys" {
  service_account_id = yandex_iam_service_account.s3_sa.id
}

# --- 3. S3 Bucket (Object Storage) ---
resource "yandex_storage_bucket" "bucket" {
  bucket     = "otus-csa-hw4-storage-2026"
  access_key = yandex_iam_service_account_static_access_key.s3_keys.access_key
  secret_key = yandex_iam_service_account_static_access_key.s3_keys.secret_key
  depends_on = [yandex_resourcemanager_folder_iam_member.s3_admin]
}

# --- 4. Два дополнительных блочных диска: HDD и SSD ---
resource "yandex_compute_disk" "disk_hdd" {
  name = "hw4-disk-hdd"
  type = "network-hdd"
  zone = "ru-central1-a"
  size = 10
}

resource "yandex_compute_disk" "disk_ssd" {
  name = "hw4-disk-ssd"
  type = "network-ssd"
  zone = "ru-central1-a"
  size = 10
}

# --- 5. ВМ для нагрузочного тестирования дисков (HDD, SSD, Network S3FS) ---
resource "yandex_compute_instance" "bench_vm" {
  name        = "hw4-bench-vm"
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

  secondary_disk {
    disk_id     = yandex_compute_disk.disk_hdd.id
    device_name = "disk-hdd"
  }

  secondary_disk {
    disk_id     = yandex_compute_disk.disk_ssd.id
    device_name = "disk-ssd"
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}

# --- 6. Управляемая СУБД (Managed PostgreSQL) ---
resource "yandex_mdb_postgresql_cluster" "pg" {
  name        = "hw4-pg-cluster"
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.net.id

  config {
    version = 15
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-hdd"
      disk_size          = 10
    }
  }

  host {
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.subnet.id
  }
}

resource "yandex_mdb_postgresql_user" "user" {
  cluster_id = yandex_mdb_postgresql_cluster.pg.id
  name       = "otus_user"
  password   = "OtusPass2026!"
}

resource "yandex_mdb_postgresql_database" "db" {
  cluster_id = yandex_mdb_postgresql_cluster.pg.id
  name       = "otus_db"
  owner      = "otus_user"
  depends_on = [yandex_mdb_postgresql_user.user]
}

output "vm_public_ip" { value = yandex_compute_instance.bench_vm.network_interface[0].nat_ip_address }
output "pg_cluster_id" { value = yandex_mdb_postgresql_cluster.pg.id }
output "s3_access_key" { value = yandex_iam_service_account_static_access_key.s3_keys.access_key }
output "s3_secret_key" {
  value     = yandex_iam_service_account_static_access_key.s3_keys.secret_key
  sensitive = true
}
