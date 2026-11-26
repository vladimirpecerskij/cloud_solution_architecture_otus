# Домашнее задание №6: Работа с Serverless решениями

**Цель работы:** Познакомиться с бессерверными вычислениями в облаке Yandex Cloud (`API Gateway`, `Cloud Functions`, `Managed Service for YDB` в режиме Serverless) и построить цепочку обработки событий.

---

## Архитектура и используемые ресурсы

```text
Клиент (HTTP GET) ──▶ API Gateway (hw6-weather-gw)
                           │
                           ▼
                Function 1: hw6-weather-context
                   ├──▶ Yandex Database (hw6-weather-db, таблица weather_stats)
                   └──▶ Function 2: hw6-weather-forecast (HTTPS)
                              └──▶ Open-Meteo API
```

| Компонент | Имя / Идентификатор | Назначение |
| :--- | :--- | :--- |
| **API Gateway** | `hw6-weather-gw` (`d5dtkps8t2nbfe093ohs`) | Единая точка входа по HTTPS (`/weather`), маршрутизация в Function 1 по спецификации OpenAPI 3.0 |
| **Function 1** | `hw6-weather-context` (`d4ebpenli0omn9fq6oqt`) | Приём контекста пользователя и координат, запись статистики в YDB, вызов Function 2 по HTTPS |
| **Function 2** | `hw6-weather-forecast` (`d4em4d91nqkm2e0df4m3`) | Запрос прогноза погоды по координатам и датам из открытого API Open-Meteo |
| **Managed DB** | `hw6-weather-db` (`etn380kfn9arke6mu442`) | Бессерверная YDB для хранения истории запросов (`weather_stats`) |
| **Сервисный аккаунт** | `hw6-serverless-sa` (`ajevfnpdh8vsrli7emn9`) | Права `serverless.functions.invoker` и `ydb.editor` |

---

## 1. Реализация компонентов

### Function 2 (`hw6-weather-forecast`)
Принимает параметры `lat`, `lon`, `start_date`, `end_date` и обращается к внешнему API прогноза погоды:
* Исходный код: [`func2/index.py`](func2/index.py)
* Зависимости: [`func2/requirements.txt`](func2/requirements.txt)

### Function 1 (`hw6-weather-context`)
Создаёт при необходимости таблицу `weather_stats` в YDB, сохраняет `id`, `user_name`, `lat`, `lon`, `requested_at`, затем вызывает `Function 2` и возвращает объединённый JSON-ответ:
* Исходный код: [`func1/index.py`](func1/index.py)
* Зависимости: [`func1/requirements.txt`](func1/requirements.txt)

### API Gateway (`hw6-weather-gw`)
Описан в формате OpenAPI 3.0 с расширением `x-yc-apigateway-integration` для вызова `hw6-weather-context`:
* Спецификация: [`api-gw.yaml`](api-gw.yaml)

> 📸 *[Скриншот: созданные функции в разделе Cloud Functions]*
> <!-- ![Cloud Functions](screenshots/01_functions.png) -->

> 📸 *[Скриншот: созданный шлюз hw6-weather-gw в разделе API Gateway]*
> <!-- ![API Gateway](screenshots/02_api_gateway.png) -->

---

## 2. Проверка работы цепочки

Запрос к публичному эндпоинту API Gateway:
```bash
curl -s "https://d5dtkps8t2nbfe093ohs.fovt0b64.apigw.yandexcloud.net/weather?user=vladimir&lat=45.0355&lon=38.9753&start_date=2026-11-27&end_date=2026-11-29" | jq .
```

**Результат выполнения:**
```json
{
  "source": "Function 2 (weather-forecast)",
  "location": {
    "lat": "45.0355",
    "lon": "38.9753"
  },
  "period": {
    "start_date": "2026-11-27",
    "end_date": "2026-11-29"
  },
  "forecast": {
    "time": ["2026-11-27", "2026-11-28", "2026-11-29"],
    "temperature_2m_max": [7.4, 5.0, 0.6],
    "temperature_2m_min": [3.5, 0.6, -2.8],
    "precipitation_sum": [1.7, 5.5, 6.7]
  },
  "processed_by": "Function 1 (weather-context)",
  "saved_user": "vladimir"
}
```

> 📸 *[Скриншот: ответ API Gateway и сохранённая запись в таблице `weather_stats` в YDB]*
> <!-- ![Result and YDB](screenshots/03_result_ydb.png) -->

---

## 3. Очистка облачных ресурсов

После тестирования и снятия скриншотов все созданные ресурсы (`hw6-weather-gw`, `hw6-weather-context`, `hw6-weather-forecast`, `hw6-weather-db`, `hw6-serverless-sa`) были удалены с помощью `yc` CLI.
