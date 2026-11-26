terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 1.6.0"
}

provider "yandex" {
  cloud_id = "b1guapctjkvac9h6i72h"
  zone     = "ru-central1-a"
}

# --- 1. Создание двух каталогов (Public и Private) ---
resource "yandex_resourcemanager_folder" "public_folder" {
  name        = "iam-public-folder"
  description = "Каталог для общих ресурсов (доступен обеим группам)"
}

resource "yandex_resourcemanager_folder" "private_folder" {
  name        = "iam-private-folder"
  description = "Каталог для закрытых ресурсов (только для private-group)"
}

# --- 2. Создание двух "пользователей" (Сервисных аккаунтов) ---
# Размещаем их в основном рабочем каталоге
resource "yandex_iam_service_account" "user_public" {
  folder_id   = "b1gi63p5vpc29cv73nqa"
  name        = "user-public-group"
  description = "Пользователь из public-group"
}

resource "yandex_iam_service_account" "user_private" {
  folder_id   = "b1gi63p5vpc29cv73nqa"
  name        = "user-private-group"
  description = "Пользователь из private-group"
}

# --- 3. Назначение прав доступа (IAM) на каталоги ---

# Доступ к PUBLIC каталогу (имеют ОБА пользователя)
resource "yandex_resourcemanager_folder_iam_member" "public_viewer_both" {
  for_each = {
    pub  = yandex_iam_service_account.user_public.id
    priv = yandex_iam_service_account.user_private.id
  }
  folder_id = yandex_resourcemanager_folder.public_folder.id
  role      = "storage.viewer"
  member    = "serviceAccount:${each.value}"
}

resource "yandex_resourcemanager_folder_iam_member" "public_uploader_both" {
  for_each = {
    pub  = yandex_iam_service_account.user_public.id
    priv = yandex_iam_service_account.user_private.id
  }
  folder_id = yandex_resourcemanager_folder.public_folder.id
  role      = "storage.uploader"
  member    = "serviceAccount:${each.value}"
}

# Доступ к PRIVATE каталогу (имеет ТОЛЬКО user_private)
resource "yandex_resourcemanager_folder_iam_member" "private_viewer_only" {
  folder_id = yandex_resourcemanager_folder.private_folder.id
  role      = "storage.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.user_private.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "private_uploader_only" {
  folder_id = yandex_resourcemanager_folder.private_folder.id
  role      = "storage.uploader"
  member    = "serviceAccount:${yandex_iam_service_account.user_private.id}"
}

# --- 4. Создание статических ключей для S3 и самих бакетов ---
# Временный сервисный аккаунт-администратор для создания бакетов в новых каталогах
resource "yandex_iam_service_account" "storage_admin" {
  folder_id = "b1gi63p5vpc29cv73nqa"
  name      = "temp-storage-creator"
}

resource "yandex_resourcemanager_folder_iam_member" "admin_public" {
  folder_id = yandex_resourcemanager_folder.public_folder.id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.storage_admin.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "admin_private" {
  folder_id = yandex_resourcemanager_folder.private_folder.id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.storage_admin.id}"
}

resource "yandex_iam_service_account_static_access_key" "admin_keys" {
  service_account_id = yandex_iam_service_account.storage_admin.id
}

# Бакет в Public каталоге
resource "yandex_storage_bucket" "public_bucket" {
  bucket     = "otus-iam-public-bucket-2026"
  folder_id  = yandex_resourcemanager_folder.public_folder.id
  access_key = yandex_iam_service_account_static_access_key.admin_keys.access_key
  secret_key = yandex_iam_service_account_static_access_key.admin_keys.secret_key
  depends_on = [yandex_resourcemanager_folder_iam_member.admin_public]
}

# Бакет в Private каталоге
resource "yandex_storage_bucket" "private_bucket" {
  bucket     = "otus-iam-private-bucket-2026"
  folder_id  = yandex_resourcemanager_folder.private_folder.id
  access_key = yandex_iam_service_account_static_access_key.admin_keys.access_key
  secret_key = yandex_iam_service_account_static_access_key.admin_keys.secret_key
  depends_on = [yandex_resourcemanager_folder_iam_member.admin_private]
}

# Вывод идентификаторов созданных ресурсов
output "public_folder_id"  { value = yandex_resourcemanager_folder.public_folder.id }
output "private_folder_id" { value = yandex_resourcemanager_folder.private_folder.id }
output "user_public_id"    { value = yandex_iam_service_account.user_public.id }
output "user_private_id"   { value = yandex_iam_service_account.user_private.id }
