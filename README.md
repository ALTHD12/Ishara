# ISL Semantic Converter

This application converts English sentences to Indian Sign Language (ISL) Gloss syntax structure, and vice versa. It consists of a FastAPI backend and a React + Vite frontend.

## Prerequisites

Before running the application, ensure you have the following installed:
*   [Python 3.8+](https://www.python.org/downloads/)
*   [Node.js (LTS version recommended)](https://nodejs.org/)

---

## ⚡ Easy Startup (Windows)

For a single-click startup on Windows:

1.  Locate and double-click the `run.bat` file in the project root folder.
2.  The script will:
    *   Verify Node.js and Python are installed.
    *   Set up the frontend (installs packages if missing).
    *   Set up the backend virtual environment, install requirements, and download the SpaCy model (`en_core_web_sm`) if missing.
    *   Clean up any active processes on ports 8000 and 5173 to prevent conflicts.
    *   Launch both the backend and frontend concurrently in the same terminal window.
    *   Automatically open the application in your default browser at `http://localhost:5173`.

*To stop the servers, simply press `Ctrl + C` in the terminal window.*

---

## 🛠️ Manual Startup (Any OS)

If you prefer to run the components manually, follow these steps:

### 1. Run the Backend

1.  Open a terminal and navigate to the `backend` directory:
    ```bash
    cd backend
    ```
2.  Create a virtual environment (first time only):
    ```bash
    python -m venv venv
    ```
3.  Activate the virtual environment:
    *   **Windows**: `venv\Scripts\activate`
    *   **macOS/Linux**: `source venv/bin/activate`
4.  Install the required dependencies:
    ```bash
    pip install -r requirements.txt
    ```
5.  Download the SpaCy English language model:
    ```bash
    python -m spacy download en_core_web_sm
    ```
6.  Start the FastAPI server:
    ```bash
    python -m uvicorn main:app --reload --port 8000
    ```
    *The API will be available at `http://127.0.0.1:8000` with interactive docs at `http://127.0.0.1:8000/docs`.*

### 2. Run the Frontend

1.  Open a new terminal window and navigate to the `frontend` directory:
    ```bash
    cd frontend
    ```
2.  Install dependencies (first time only):
    ```bash
    npm install
    ```
3.  Start the Vite development server:
    ```bash
    npm run dev
    ```
4.  Open your browser and navigate to the URL shown in the terminal (usually `http://localhost:5173`).
