# Домашнее задание №1: Разграничение прав на облачные ресурсы (IAM в Yandex Cloud)

## 1. Цель работы
Настроить ролевую модель разграничения доступа (RBAC) к облачным бакетам **Yandex Object Storage** для двух категорий пользователей (`public` и `private`) с помощью **Terraform** и проверить работу политик через **YC CLI**.

## 2. Архитектура решения (`main.tf`)
* **Два изолированных каталога (`yandex_resourcemanager_folder`):**
  * `iam-public-folder` — для общих данных.
  * `iam-private-folder` — для конфиденциальных данных.
* **Два бакета Object Storage (`yandex_storage_bucket`):**
  * `otus-iam-public-bucket-2026` (в каталоге `iam-public-folder`).
  * `otus-iam-private-bucket-2026` (в каталоге `iam-private-folder`).
* **Два субъекта доступа (`yandex_iam_service_account`):**
  * `user-public-group` — пользователь из публичной группы.
  * `user-private-group` — пользователь из закрытой группы.
* **Матрица прав доступа (`storage.viewer` и `storage.uploader`):**
  * На `iam-public-folder`: права назначены **обоим** пользователям (`user-public-group` и `user-private-group`).
  * На `iam-private-folder`: права назначены **только** `user-private-group`.

## 3. Результаты проверки через YC CLI (`s3api put-object`)
1. `user-public-group` → загрузка в `otus-iam-public-bucket-2026`: **Успешно (`ETag` получен)**.
2. `user-public-group` → загрузка в `otus-iam-private-bucket-2026`: **Отказ (`AccessDenied` / HTTP 403)**.
3. `user-private-group` → загрузка в `otus-iam-public-bucket-2026`: **Успешно**.
4. `user-private-group` → загрузка в `otus-iam-private-bucket-2026`: **Успешно**.
