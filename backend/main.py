import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes import nlp, websocket
import threading
import subprocess
import time

import os

# --- PERMANENT ADB TUNNEL FIX ---
def keep_adb_alive():
    """ Runs in the background and continuously ensures the USB tunnel stays open """
    adb_path = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe")
    while True:
        try:
            subprocess.run([adb_path, "reverse", "tcp:8765", "tcp:8765"], 
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"ADB Tunnel Error: {e}")
        time.sleep(3) # Check every 3 seconds

threading.Thread(target=keep_adb_alive, daemon=True).start()
# --------------------------------

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(nlp.router)
app.include_router(websocket.router)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8765)
