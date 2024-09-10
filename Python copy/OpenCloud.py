


import requests
import json

universe_id = "4774121707"
topic = "Test"
api_key = "t2ez7RLYh06uE+50EzhmpV6qGGJ3JKneho6m+toyWqxplH/u"

url = f"https://apis.roblox.com/messaging-service/v1/universes/{universe_id}/topics/{topic}"
headers = {
    "x-api-key": api_key,
    "Content-Type": "application/json"
}
payload = {
    "message": "Hello World"
}

response = requests.post(url, headers=headers, data=json.dumps(payload))
print(response.status_code)



print(response.url)

