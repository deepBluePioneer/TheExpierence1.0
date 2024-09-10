import requests
import json
import hashlib
import base64

api_key = "+dbZhA3jkEGJyqeEiOIAn3mSQASKAqwBK/EVz5WceVb0i5gU"
headers = {
    'x-api-key': api_key,
}

params = (
    ('prefix', ''),
    ('limit', '5'),
)

response = requests.get('https://apis.roblox.com/datastores/v1/universes/4774121707/standard-datastores', headers=headers, params=params)


datastore_name = 'PlayerStats'
entry_key = '3296608955'
user_ids = [3296608955]  # modify this to match actual user IDs if needed
entry_attributes = {}  # modify this to set any attributes if needed

# data you want to set
data = {
    'Forensics': 500000,
    'Steganography': 100,
    'Network Analysis': 100,
    'Digital Lockpicking': 100,
    'Web Application Hacking': 10000000000000000,
    'Reconnaissance and OSINT': 100,
    'Mobile Application Hacking': 100,
    'Secure Coding': 100,
    'Cryptography': 100,
    'Reverse Engineering': 100,
    'Cloud Security': 100,
    'Binary Exploitation': 100,
    'Exploit Development': 100,
    'Social Engineering': 100,
    'Wireless Hacking': 100,
    'IoT Hacking': 100
}

# JSONify the data and get the MD5
data_json = json.dumps(data)
md5 = hashlib.md5(data_json.encode('utf-8')).digest()
base64_md5 = base64.b64encode(md5).decode('utf-8')

headers = {
    'x-api-key': api_key,
    'content-md5': base64_md5,
    'content-type': 'application/json',
    'roblox-entry-userids': json.dumps(user_ids),
    'roblox-entry-attributes': json.dumps(entry_attributes)
}

response = requests.post(
    f'https://apis.roblox.com/datastores/v1/universes/4774121707/standard-datastores/datastore/entries/entry?datastoreName={datastore_name}&entryKey={entry_key}',
    headers=headers,
    data=data_json
)

#print(response.status_code)
#print(response.json())


headers = {
    'x-api-key': api_key,
}

params = {
    'datastoreName': 'PlayerStats',
    'prefix': '',
    'limit': '5',
}

response = requests.get('https://apis.roblox.com/datastores/v1/universes/4774121707/standard-datastores/datastore/entries', headers=headers, params=params)


headers = {
    'x-api-key': api_key,
}

params = {
    'datastoreName': 'PlayerStats',
    'entryKey': '3461999112',
}

response = requests.get('https://apis.roblox.com/datastores/v1/universes/4774121707/standard-datastores/datastore/entries/entry', headers=headers, params=params)

response_data = response.json()

if isinstance(response_data, dict):
    for key, value in response_data.items():
        print(f"{key}: {value}")
elif isinstance(response_data, list):
    for element in response_data:
        print(element)
