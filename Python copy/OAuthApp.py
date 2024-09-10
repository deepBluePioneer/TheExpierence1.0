import requests
from requests_oauthlib import OAuth2Session
import os
import hashlib
import base64
import urllib.parse

# Your client credentials
client_id = '1138882679841777674'
client_secret = 'RBX-_VhpAcIhckyoqjtPl8F-RIXSdf71xHh-k8j1JHb8qK2nCJimUFFa_UPVg-oKz4HU'

# OAuth 2 endpoints
authorization_base_url = 'https://apis.roblox.com/oauth/v1/authorize'
token_url = 'https://apis.roblox.com/oauth/v1/token'

# Redirect URI
redirect_uri = 'https://www.login.dev-stage.space'

# Scopes you are requesting
scope = ["openid", "profile", "universe-messaging-service:publish"]

# Create a PKCE code verifier
code_verifier = base64.urlsafe_b64encode(os.urandom(40)).decode('utf-8')
code_verifier = code_verifier.rstrip('=')

# Create a PKCE code challenge
m = hashlib.sha256()
m.update(code_verifier.encode('utf-8'))
code_challenge = base64.urlsafe_b64encode(m.digest()).decode('utf-8')
code_challenge = code_challenge.rstrip('=')

# Create a session
oauth = OAuth2Session(client_id, redirect_uri=redirect_uri, scope=scope)

# Construct the authorization URL with PKCE parameters
authorization_url, state = oauth.authorization_url(
    authorization_base_url,
    code_challenge=code_challenge,
    code_challenge_method='S256'
)

print(f'Please go to this URL and authorize the app: {authorization_url}')

# Get the authorization verifier code from the callback url
redirect_response = input('Paste the full redirect URL here:')
token = oauth.fetch_token(
    token_url,
    authorization_response=redirect_response,
    client_secret=client_secret,
    code_verifier=code_verifier
)

# Now you can use 'oauth' to make requests as the authenticated user
response = oauth.get('https://apis.roblox.com/v1/users/me')
print(response.content)

# Use the access token to get user info
access_token = token['access_token']
headers = {'Authorization': f'Bearer {access_token}'}
response = requests.get('https://apis.roblox.com/oauth/v1/userinfo', headers=headers)

# Print the user info
if response.status_code == 200:
    userinfo = response.json()
    print(userinfo)
    # Print the user ID
    user_id = userinfo.get('sub')
    if user_id:
        print(f"The User ID is: {user_id}")
    else:
        print("Could not find the User ID in the response.")
else:
    print(f"Failed to get user info: {response.content}")

