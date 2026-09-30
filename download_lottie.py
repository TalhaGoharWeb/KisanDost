import urllib.request
import os

os.makedirs('assets/lottie', exist_ok=True)

url = 'https://raw.githubusercontent.com/xvrh/lottie-flutter/master/example/assets/LottieLogo1.json'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as response:
        content = response.read()
        with open('assets/lottie/empty.json', 'wb') as out_file:
            out_file.write(content)
    print(f"Successfully downloaded empty.json")
except Exception as e:
    print(f"Failed to download: {e}")
