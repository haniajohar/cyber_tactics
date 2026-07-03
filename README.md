# Cyber Tactics 🌌🕹️
A real-time, 2-player turn-based tactical war game played on a 6x6 grid matrix. Features a fully asynchronous **FastAPI WebSocket backend** for instant state synchronization, and a premium, retro-futuristic **Flutter frontend** with high-fidelity neon vector graphics.
---
## 🚀 Key Features
*   **Real-time Synchronization**: Powered by a custom WebSocket connection manager in FastAPI that handles player assignments (`P1`, `P2`, and `spectators`) and broadcasts state updates instantly.
*   **Tactical Pathfinding**: Integrates a client-side and server-validated **Breadth-First Search (BFS)** algorithm to compute movement paths. Units can pass through friendly units but are blocked by enemies.
*   **Premium Cyberpunk Aesthetics**: Rendered with custom vector paths (`CustomPainter`) and glow effects in Flutter. Features animated tactical domain rings, health bars, and an interactive grid interface.
*   **Hacker Logs Console**: An on-screen scrollable monospace console printing real-time system messages and actions directly from the server.
*   **Balance & Economy**: Features resource credit limits (credits generated per turn), unit deployment costs, distinct weapon ranges (Min/Max limits for Artillery), and base-destruction win conditions.
---
## 🛠️ Tech Stack
*   **Backend**: Python, FastAPI, WebSockets (`websockets` library), Uvicorn, Pydantic
*   **Frontend**: Dart, Flutter SDK, `web_socket_channel`
---
## 📂 Project Structure
```text
cyber-tactics/
├── backend/
│   ├── main.py              # FastAPI server, state engine & WebSocket endpoint
│   ├── requirements.txt     # Python backend dependencies
│   └── test_client.py       # Asynchronous CLI test harness client
├── frontend/
│   ├── pubspec.yaml         # Flutter project configuration
│   └── lib/
│       └── main.dart        # Entrypoint containing UI, graphics & models
└── README.md                # This file
```
---
## ⚡ Setup & Launch Instructions
### Prerequisites
*   [Python 3.8+](https://www.python.org/downloads/)
*   [Flutter SDK](https://docs.flutter.dev/get-started/install)
---
### Step 1: Fire up the Backend Server
Navigate to the `backend/` directory, install packages, and spin up the development server:
```bash
# Navigate to backend
cd backend
# Install python requirements
pip install -r requirements.txt
# Start FastAPI server on localhost:8000
uvicorn main:app --host 0.0.0.0 --port 8000
```
---
### Step 2: Run Connection Verification (Optional)
To verify the socket connection and room initialization routines on the backend, run the automated test harness:
```bash
python test_client.py
```
---
### Step 3: Launch the Flutter Web/App Client
Open a new terminal window, navigate to the `frontend/` directory, fetch packages, and run the app:
```bash
# Navigate to frontend
cd frontend
# Fetch flutter dependencies
flutter pub get
# Run the project (choose Chrome, Edge, or a desktop simulator)
flutter run
```
---
## 🎮 Gameplay Guide
1.  ** neural-link connection**: Open **two separate browser windows** side-by-side. 
2.  **Room coordinates**: Connect both clients to the same room ID (e.g. `lobby`) and server URL (`ws://localhost:8000`).
3.  **Role Assignment**:
    *   The first client to connect will be assigned **`P1: BLUE`**.
    *   The second client will connect as **`P2: MAGENTA`**.
    *   Subsequent clients will connect as **`SPECTATORS`**.
4.  **Active Mode**: As soon as Player 2 connects, the game turns from `WAITING` to `ACTIVE`.
5.  **Turn Loop**:
    *   Each turn, a player gets **+3 Credits** to spend.
    *   Deploy units on your home row (Row 0 for P1, Row 5 for P2) using the side control panel.
    *   Click on your units to view valid movement grids (highlighted in cyan/blue) or target zones (highlighted in red).
    *   Destroy the enemy base command station (**Base P1** at `(0,2)` or **Base P2** at `(5,3)`) to win the match.
### Unit Database & Statistics
|
 Unit Type 
|
 Credit Cost 
|
 Max HP 
|
 Attack Damage 
|
 Move Range 
|
 Attack Range 
|
 Description 
|
|
:---
|
:---:
|
:---:
|
:---:
|
:---:
|
:---:
|
:---
|
|
**
Base Station
**
|
 N/A 
|
 100 
|
 0 
|
 0 
|
 0 
|
 Stationary command center. Losing it loses the match. 
|
|
**
Infantry
**
|
 3 
|
 40 
|
 15 
|
 2 
|
 1 
|
 Versatile, fast deployment unit. 
|
|
**
Tank
**
|
 6 
|
 60 
|
 25 
|
 3 
|
 1 
|
 Armored, highly mobile assault vehicle. 
|
|
**
Artillery
**
|
 5 
|
 30 
|
 30 
|
 1 
|
 2 - 3 
|
 Long-range siege battery. Cannot attack close-range tiles. 
|
---
## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details.
