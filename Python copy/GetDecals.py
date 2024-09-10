import requests

# Define your API key and user ID
API_KEY = 'JeZnfzTQJEuO2Uk0RStVd9fjHAiigLq4sDOFr9ERPVbpO/Yf'
USER_ID = '32553643'
FILE_PATH = 'Python\Images\_test.png'

# Determine the content type based on the file extension
file_extension = FILE_PATH.split('.')[-1].lower()
content_type_map = {
    'png': 'image/png',
    'jpeg': 'image/jpeg',
    'jpg': 'image/jpeg',
    'bmp': 'image/bmp',
    'tga': 'image/tga'
}
content_type = content_type_map.get(file_extension, 'image/png')

# Convert the image to bytes
with open(FILE_PATH, 'rb') as image_file:
    image_bytes = image_file.read()

# Set up the headers
headers = {
    'x-api-key': API_KEY
}

# Set up the data for the request
data = {
    'request': {
        'assetType': 'Decal',
        'displayName': 'Name',
        'description': 'This is a description',
        'creationContext': {
            'creator': {
                'userId': USER_ID
            }
        }
    }
}

# Set up the files for the request using the byte representation
files = {
    'fileContent': (FILE_PATH.split('/')[-1], image_bytes, content_type)
}

# Make the request
response = requests.post('https://apis.roblox.com/assets/v1/assets', headers=headers, json=data, files=files)

# Print the response
print(response.text)
