# Домашнее задание №5: Работа с контейнеризацией в облачных средах

**Цель работы:** Познакомиться с инструментами контейнеризации и оркестрации в облачной среде Yandex Cloud (`Container Registry`, `Serverless Containers`, `Container Optimized Image`, `Managed Service for Kubernetes`).

---

## Используемые параметры и ресурсы

| Параметр / Ресурс | Значение |
| :--- | :--- |
| **Облачный провайдер** | Yandex Cloud (`ru-central1-a`) |
| **Container Registry** | `otus-csa-registry` (`crpqvn9b88r454rgffob`) |
| **Сервисный аккаунт** | `hw5-container-sa` (`ajeno7h1bgp9bpmmd3j4`) |
| **Сеть / Подсеть** | `hw5-net` / `hw5-subnet` (`10.30.1.0/24`) |
| **ВМ Container Solution (COI)** | `hw5-coi-vm` (External IP: `51.250.95.7`, Internal IP: `10.30.1.8`) |
| **Кластер Kubernetes** | `hw5-k8s-cluster` (`catros8gj4dsh6haeg2o`) |
| **Рабочий узел K8s** | `cl1cqca1ks6mqcf6b794-usic` (External IP: `89.169.133.161`, Internal IP: `10.30.1.27`) |

---

## 1. Подготовка тестового контейнера и исходного кода

Создано тестовое веб-приложение на базе лёгкого образа `nginx:alpine` с пользовательской HTML-страницей.

**`index.html` (версия 1.0):**
```html
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Cloud Containers HW</title></head>
<body>
  <h1>Version 1.0 - Hello from Yandex Cloud!</h1>
</body>
</html>
```

**`Dockerfile`:**
```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

**Сборка локального образа:**
```bash
docker build -t otus-web:v1 .
```

> 📸 *[Скриншот: исходный код `Dockerfile` и `index.html` / результат сборки `docker images`]*
> <!-- ![Docker Build](screenshots/01_docker_build.png) -->

---

## 2. Создание Container Registry и загрузка образа

1. Создан приватный реестр `otus-csa-registry`.
2. Настроена интеграция локального Docker CLI с `cr.yandex`.
3. Образ протегирован и отправлен в облачный реестр.

```bash
yc container registry create --name otus-csa-registry
yc container registry configure-docker

docker tag otus-web:v1 cr.yandex/crpqvn9b88r454rgffob/otus-web:v1
docker push cr.yandex/crpqvn9b88r454rgffob/otus-web:v1
```

> 📸 *[Скриншот: созданный реестр `otus-csa-registry` и загруженный образ `otus-web:v1` в Yandex Cloud]*
> <!-- ![Container Registry](screenshots/02_registry.png) -->

---

## 3. Запуск контейнера в Serverless окружении (Serverless Containers)

1. Создан сервисный аккаунт `hw5-container-sa` с ролью `container-registry.images.puller`.
2. Создан Serverless-контейнер и развёрнута ревизия с образом `otus-web:v1` (порт `80`).
3. Открыт публичный вызов контейнера и проверена работа веб-страницы по HTTPS-ссылке.

```bash
yc serverless container create --name otus-serverless-app
yc serverless container revision deploy \
  --container-name otus-serverless-app \
  --image cr.yandex/crpqvn9b88r454rgffob/otus-web:v1 \
  --cores 1 --memory 256MB --execution-timeout 15s \
  --service-account-id ajeno7h1bgp9bpmmd3j4 --container-port 80

yc serverless container allow-unauthenticated-invoke otus-serverless-app
```

> 📸 *[Скриншот: запущенный Serverless-контейнер и открытая страница в браузере]*
> <!-- ![Serverless Container](screenshots/03_serverless.png) -->

---

## 4. Запуск контейнера в Container Solution (Container Optimized Image)

Подготовлена спецификация Docker Compose `spec.yaml` и создана ВМ `hw5-coi-vm` на базе образа **Container Optimized Image (COI)** с публичным IP-адресом (`51.250.95.7`).

**`spec.yaml`:**
```yaml
version: '3.7'
services:
  web:
    image: cr.yandex/crpqvn9b88r454rgffob/otus-web:v1
    ports:
      - "80:80"
    restart: always
```

**Создание ВМ:**
```bash
yc compute instance create-with-container \
  --name hw5-coi-vm \
  --zone ru-central1-a \
  --public-ip \
  --service-account-id ajeno7h1bgp9bpmmd3j4 \
  --docker-compose-file spec.yaml
```

> 📸 *[Скриншот: запущенная ВМ `hw5-coi-vm` в Compute Cloud и открытая веб-страница по IP `51.250.95.7`]*
> <!-- ![Container Solution COI](screenshots/04_coi_vm.png) -->

---

## 5. Развёртывание кластера Kubernetes и публикация через LoadBalancer

1. Создана изолированная сеть `hw5-net` и подсеть `hw5-subnet` (`10.30.1.0/24`).
2. Развёрнут кластер **Managed Service for Kubernetes** (`hw5-k8s-cluster`) и группа узлов (`cl1cqca1ks6mqcf6b794-usic`).
3. Применён манифест `k8s-app.yaml`, разворачивающий `Deployment` (2 реплики) и `Service` типа `LoadBalancer` для доступа к приложению извне.

**`k8s-app.yaml`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otus-web-deploy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: otus-web
  template:
    metadata:
      labels:
        app: otus-web
    spec:
      containers:
      - name: web
        image: cr.yandex/crpqvn9b88r454rgffob/otus-web:v1
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: otus-web-lb
spec:
  type: LoadBalancer
  selector:
    app: otus-web
  ports:
  - port: 80
    targetPort: 80
```

> 📸 *[Скриншот: кластер `hw5-k8s-cluster` и группа узлов в Yandex Cloud]*
> <!-- ![Kubernetes Cluster](screenshots/05_k8s_cluster.png) -->
> 📸 *[Скриншот: запущенные Pod'ы (`kubectl get pods`) и внешний IP балансировщика (`kubectl get svc`)]*
> <!-- ![Kubernetes Pods and LB](screenshots/06_k8s_pods_lb.png) -->

---

## 6. Обновление приложения в кластере (Rolling Update)

1. Внесены изменения в `index.html` (`Version 2.0 (Updated!)`).
2. Собран и загружен в Container Registry новый образ `otus-web:v2`.
3. Выполнено плавное обновление `Deployment` в кластере без остановки сервиса:

```bash
docker build -t otus-web:v2 .
docker tag otus-web:v2 cr.yandex/crpqvn9b88r454rgffob/otus-web:v2
docker push cr.yandex/crpqvn9b88r454rgffob/otus-web:v2

kubectl set image deployment/otus-web-deploy web=cr.yandex/crpqvn9b88r454rgffob/otus-web:v2
kubectl rollout status deployment/otus-web-deploy
```

> 📸 *[Скриншот: обновлённая версия `Version 2.0 (Updated!)` в браузере по IP-адресу LoadBalancer]*
> <!-- ![Rolling Update v2](screenshots/07_k8s_v2.png) -->

---

## 7. Очистка облачных ресурсов

По завершении проверки все созданные облачные ресурсы (кластер Kubernetes, рабочие узлы, сетевой балансировщик, ВМ COI, Serverless-контейнер, образы и реестр `otus-csa-registry`, подсеть `hw5-subnet`, сеть `hw5-net` и сервисный аккаунт `hw5-container-sa`) были полностью удалены через `yc` CLI.
