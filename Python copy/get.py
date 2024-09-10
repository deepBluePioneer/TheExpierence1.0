import requests

api_key = 'W0GxfBZKF0SKfg6WAufz/2tkduLatWI61ikMF1/xF9peGevP'
group_id = '32932520'

url = f'https://groups.roblox.com/v1/groups/32932520/assets?assetType=Decal&sortOrder=Asc&limit=100'

headers = {
    'Content-Type': 'application/json',
    'Authorization': f'Bearer {api_key}'
}

models = []

while url:
    response = requests.get(url, headers=headers)
    response_json = response.json()

    if response.status_code == 200:
        data = response_json['data']
        models.extend(data)

        next_page_cursor = response_json['nextPageCursor']
        if next_page_cursor:
            url = f'https://groups.roblox.com/v1/groups/{group_id}/assets?assetType=Decal&sortOrder=Asc&limit=100&cursor={next_page_cursor}'
        else:
            url = None
    else:
        print("Error:", response_json)
        break
print("Total Decals:", len(models))

for model in models:
    model_id = model['id']
    print(f"Decal ID: {model_id}")

