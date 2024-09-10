import requests
import json

api_key = 'JeZnfzTQJEuO2Uk0RStVd9fjHAiigLq4sDOFr9ERPVbpO/Yf'
group_id = '32553643'
file_path = 'Python\Images\_test.png'



url = 'https://apis.roblox.com/assets/v1/assets'

headers = {
    'x-api-key': api_key,
}

data = {
    'request': json.dumps({
        "assetType": "Decal",
        "displayName": "Decaltest",
        "description": "This is a description ",
        "creationContext": {
            "creator": {
                "userId": group_id
            },

        }
    })
}

with open(file_path, 'rb') as f:
    file_content = f.read()

files = {'fileContent': ('test.png', file_content, 'image/png')}

response = requests.post(url, headers=headers, data=data, files=files)

response_json = response.json()
#operation_id = response_json.get('path')

print("Response Status Code:", response.status_code)
#print("Operation ID:", operation_id)


def get_operation(operation_path):
    headers = {'x-api-key': api_key}
    response = requests.get('https://apis.roblox.com/assets/v1/' + operation_path, headers=headers)
    if response.status_code == 200:
        print('GOod')
        print(response.url)
        print(response.reason)
    else:
        print("No Good")

#get_operation(operation_id)