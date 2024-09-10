import hashlib
import requests
import json
import base64

class DataStores:

    def __init__(self):
        self._base_url = "https://apis.roblox.com/datastores/v1/universes/{universeId}"
        # API Key is saved in an environment variable signified by 'API_KEY'
        self._apiKey = "QYvLQpEUaUicQCuBpOLHGbMVqLOxLtEZDwZhH7c/8q3ifmIr"
        self._universeId = "4774121707"
        self.ATTR_HDR = 'Roblox-entry-Attributes'
        self.USER_ID_HDR = 'Roblox-entry-UserIds'
        self._objects_url = self._base_url +self._universeId+'/standard-datastores/datastore/entries/entry'
        self._increment_url = self._objects_url + '/increment'
        self._version_url = self._objects_url + '/versions/version'
        self._list_objects_url = self._base_url +self._universeId+'/standard-datastores/datastore/entries'

    def _H(self):
        return { 'x-api-key' : self._apiKey }
    def _get_url(self, path_format: str):
        return f"{self._config['base_url']}/{path_format.format(self._config['universe_id'])}"

        return r, attributes, user_ids

    def get_entry(self, datastore, object_key, scope = None):
            self._objects_url = self._base_url +self._universeId+'/standard-datastores/datastore/entries/entry'
            headers = { 'x-api-key' : self._apiKey }
            params={"datastoreName" : datastore, "entryKey" : object_key}
            if scope:
                params["scope"] = scope
            r = requests.get(self._objects_url, headers=headers, params=params)
            if 'Content-MD5' in r.headers:
                expected_checksum = r.headers['Content-MD5']
                checksum = base64.b64encode(hashlib.md5(r.content).digest())
                #print(f'Expected {expected_checksum},  got {checksum}')

            attributes = None
            if self.ATTR_HDR in r.headers:
                attributes = json.loads(r.headers[self.ATTR_HDR])
            user_ids = []
            if self.USER_ID_HDR in r.headers:
                user_ids = json.loads(r.headers[self.USER_ID_HDR])

            return r

    def list_entries(self, datastore, scope = None, prefix="", limit=100, allScopes = False, exclusive_start_key=None):
        self._objects_url = self._base_url +self._universeId+'/standard-datastores/datastore/entries'
        headers = { 'x-api-key' : self._apiKey }
        r = requests.get(self._objects_url, headers=headers, params={"datastoreName" : datastore, "scope" : scope, "allScopes" : allScopes, "prefix" : prefix, "limit" : 100, "cursor" : exclusive_start_key})
        return r

    def increment_entry(self, datastore, object_key, incrementBy, scope = None, attributes=None, user_ids=None):
        self._objects_url = self._base_url +self._universeId+'/standard-datastores/datastore/entries/entry/increment'
        headers = { 'x-api-key' : self._apiKey, 'Content-Type': 'application/octet-stream' }
        params={"datastoreName" : datastore, "entryKey" : object_key, "incrementBy" : incrementBy}
        if scope:
            params["scope"] = scope

        r = requests.post(self._objects_url, headers=headers, params=params)
        attributes = None
        if self.ATTR_HDR in r.headers:
            attributes = json.loads(r.headers[self.ATTR_HDR])
        user_ids = []
        if self.USER_ID_HDR in r.headers:
            user_ids = json.loads(r.headers[self.USER_ID_HDR])

        return r