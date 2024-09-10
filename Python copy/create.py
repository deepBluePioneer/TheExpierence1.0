import requests
from requests_toolbelt import MultipartEncoder
import json



api_key = 't2ez7RLYh06uE+50EzhmpV6qGGJ3JKneho6m+toyWqxplH/u'
group_id = '32553643'
file_path = 'Python\Test.fbx'

def create_asset():
    with open(file_path, 'rb') as f:
        file_content = f.read()

    data = {
        'request': ('request', json.dumps({
            "assetType": "Decal",
            "creationContext": {
                "creator": {
                    "groupId": group_id
                }
            },
            "description": "Random description for test upload!",
            "displayName": "TestAsset for upload"
        }), 
                    'application/json'),
        'fileContent': ('test.fbx', file_content, 'model/fbx')
    }

    encoder = MultipartEncoder(fields=data)
    
    headers = {
        'x-api-key': api_key,
        'Content-Type': encoder.content_type
    }

    response = requests.post('https://apis.roblox.com/assets/v1/assets', data=encoder, headers=headers)
    
    if response.status_code == 200:
        print(response.json()['path'])
    else:
        print(response.json())

create_asset()
