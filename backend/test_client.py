import asyncio
import json
import websockets
import sys

async def run_test():
    url = "ws://localhost:8000/ws/game/test_room"
    print(f"Connecting to backend websocket at {url}...")
    try:
        async with websockets.connect(url) as websocket:
            print("Connected successfully!")
            
            # Read first message: role assignment
            msg = await websocket.recv()
            role_assignment = json.loads(msg)
            print(f"Role Assignment Received: {role_assignment}")
            if role_assignment.get("type") != "role_assignment":
                print("Error: Expected role assignment.")
                sys.exit(1)
            
            # Read second message: initial game state
            msg = await websocket.recv()
            state = json.loads(msg)
            print(f"Initial State Status: {state.get('status')}")
            print(f"Initial Turn: {state.get('active_turn')}")
            print(f"Initial Units Count: {len(state.get('units', []))}")
            
            # Verify base coordinates
            bases = {u["id"]: u for u in state.get("units", []) if u["type"] == "base"}
            print(f"Base P1: {bases.get('base_p1')}")
            print(f"Base P2: {bases.get('base_p2')}")
            
            # Send end turn event to test message exchange
            # Note: Game status is "waiting" since P2 is not connected, so standard game actions will fail or be ignored.
            # But we can test if reset is accepted.
            print("Sending reset action...")
            await websocket.send(json.dumps({"action": "reset"}))
            
            # Receive updated state
            msg = await websocket.recv()
            reset_state = json.loads(msg)
            print(f"State after reset action: {reset_state.get('type')}")
            
            print("Test execution complete: SUCCESS")
            sys.exit(0)
    except Exception as e:
        print(f"Connection failed or server error: {e}")
        print("Note: The FastAPI server must be running at localhost:8000 for this test to pass.")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(run_test())
