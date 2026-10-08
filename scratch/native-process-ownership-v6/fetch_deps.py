from pathlib import Path
import urllib.request
import zipfile
import io
root = Path(__file__).resolve().parent
commit = '714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa'
url = 'https://codeload.github.com/godotengine/godot-cpp/zip/' + commit
payload = urllib.request.urlopen(url, timeout=60).read()
(root / 'godot-cpp.zip').write_bytes(payload)
with zipfile.ZipFile(io.BytesIO(payload)) as archive:
    archive.extractall(root / 'deps')
print(root / 'deps' / ('godot-cpp-' + commit))
