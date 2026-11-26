import json
import requests

def handler(event, context):
    params = event.get('queryStringParameters') or {}
    lat = params.get('lat', '45.0355')
    lon = params.get('lon', '38.9753')
    start_date = params.get('start_date', '2026-11-27')
    end_date = params.get('end_date', '2026-11-29')

    host = "api." + "open-meteo." + "com"
    url = f"https://{host}/v1/forecast"
    query = {
        "latitude": lat,
        "longitude": lon,
        "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum",
        "timezone": "auto",
        "start_date": start_date,
        "end_date": end_date
    }

    resp = requests.get(url, params=query, timeout=10)
    if resp.status_code != 200:
        return {
            'statusCode': resp.status_code,
            'body': json.dumps({'error': resp.text, 'url': resp.url})
        }

    data = resp.json()

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'source': 'Function 2 (weather-forecast)',
            'location': {'lat': lat, 'lon': lon},
            'period': {'start_date': start_date, 'end_date': end_date},
            'forecast': data.get('daily', data)
        }, ensure_ascii=False)
    }
