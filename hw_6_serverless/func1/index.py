import os
import json
import uuid
from datetime import datetime, timezone
import requests
import ydb

YDB_ENDPOINT = os.environ['YDB_ENDPOINT']
YDB_DATABASE = os.environ['YDB_DATABASE']
FUNC2_URL = os.environ['FUNC2_URL']

driver = ydb.Driver(
    endpoint=YDB_ENDPOINT,
    database=YDB_DATABASE,
    credentials=ydb.iam.MetadataUrlCredentials()
)
driver.wait(fail_fast=True, timeout=5)
pool = ydb.SessionPool(driver)

def init_table(session):
    session.execute_scheme("""
        CREATE TABLE IF NOT EXISTS weather_stats (
            id Utf8,
            user_name Utf8,
            lat Utf8,
            lon Utf8,
            requested_at Utf8,
            PRIMARY KEY (id)
        );
    """)

def save_stat(session, user_name, lat, lon):
    query = """
        DECLARE $id AS Utf8;
        DECLARE $user_name AS Utf8;
        DECLARE $lat AS Utf8;
        DECLARE $lon AS Utf8;
        DECLARE $requested_at AS Utf8;

        UPSERT INTO weather_stats (id, user_name, lat, lon, requested_at)
        VALUES ($id, $user_name, $lat, $lon, $requested_at);
    """
    prepared = session.prepare(query)
    session.transaction().execute(
        prepared,
        {
            '$id': str(uuid.uuid4()),
            '$user_name': str(user_name),
            '$lat': str(lat),
            '$lon': str(lon),
            '$requested_at': datetime.now(timezone.utc).isoformat()
        },
        commit_tx=True
    )

def handler(event, context):
    params = event.get('queryStringParameters') or {}
    user_name = params.get('user', 'anonymous')
    lat = params.get('lat', '45.0355')
    lon = params.get('lon', '38.9753')
    start_date = params.get('start_date', '2026-11-27')
    end_date = params.get('end_date', '2026-11-29')

    # 1. Сохраняем статистику в YDB
    pool.retry_operation_sync(init_table)
    pool.retry_operation_sync(lambda s: save_stat(s, user_name, lat, lon))

    # 2. Вызываем Function 2 по HTTPS
    resp = requests.get(
        FUNC2_URL,
        params={'lat': lat, 'lon': lon, 'start_date': start_date, 'end_date': end_date},
        timeout=15
    )

    result = resp.json()
    result['processed_by'] = 'Function 1 (weather-context)'
    result['saved_user'] = user_name

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(result, ensure_ascii=False)
    }
