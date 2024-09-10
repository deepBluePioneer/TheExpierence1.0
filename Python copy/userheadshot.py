import requests
import json
from PIL import Image
from io import BytesIO

# User ID variable
user_id = '3956286464'

# URL with variable included
url = f'https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds={user_id}&size=150x150&format=Png&isCircular=false'

# Make a GET request to the URL
response = requests.get(url)

# Check if the request was successful
if response.status_code == 200:
    # Load the JSON response
    response_data = json.loads(response.text)
    image_url = response_data["data"][0]["imageUrl"]
    
    # Make a request to get the image
    image_response = requests.get(image_url)
    if image_response.status_code == 200:
        # Open the image from the response
        image = Image.open(BytesIO(image_response.content))
        image.show() # Display the image
    else:
        print('Failed to retrieve the image.')
else:
    print('Failed to retrieve the JSON data.')
