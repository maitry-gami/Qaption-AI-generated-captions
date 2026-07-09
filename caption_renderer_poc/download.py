import os
import urllib.request

urls = {
    'Oswald': 'https://raw.githubusercontent.com/google/fonts/main/ofl/oswald/Oswald%5Bwght%5D.ttf',
    'Lato': 'https://raw.githubusercontent.com/google/fonts/main/ofl/lato/Lato-Regular.ttf'
}

for name, url in urls.items():
    print(f"Downloading {name}...")
    try:
        urllib.request.urlretrieve(url, f'assets/fonts/{name}.ttf')
        print(f"Downloaded {name}.ttf")
    except Exception as e:
        print(f"Failed to download {name}: {e}")
