import asyncio
import json
import logging
import uuid
from typing import Dict, List, Optional, Set
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("CyberTacticsBackend")

app = FastAPI(title="Cyber Tactics Backend")

# Enable CORS for local testing and cross-origin access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Constants
GRID_SIZE = 6

UNIT_STATS = {
    "base": {"max_hp": 100, "damage": 0, "move_range": 0, "attack_min_range": 0, "attack_max_range": 0, "cost": 0},
    "infantry": {"max_hp": 40, "damage": 15, "move_range": 2, "attack_min_range": 1, "attack_max_range": 1, "cost": 3},
    "tank": {"max_hp": 60, "damage": 25, "move_range": 3, "attack_min_range": 1, "attack_max_range": 1, "cost": 6},
    "artillery": {"max_hp": 30, "damage": 30, "move_range": 1, "attack_min_range": 2, "attack_max_range": 3, "cost": 5},
}

class Unit(BaseModel):
    id: str
    type: str  # "base" | "infantry" | "tank" | "artillery"
    owner: str  # "P1" | "P2"
    x: int
    y: int
    hp: int
    max_hp: int
    can_move: bool
    can_attack: bool

class GameState:
    def __init__(self, room_id: str):
        self.room_id = room_id
        self.status = "waiting"  # "waiting" | "active" | "game_over"
        self.winner: Optional[str] = None  # "P1" | "P2"
        self.active_turn = "P1"
        self.p1_credits = 10
        self.p2_credits = 10
        self.units: Dict[str, Unit] = {}
        self.action_logs: List[str] = []
        self.reset_board()

    def reset_board(self):
        self.status = "waiting"
        self.winner = None
        self.active_turn = "P1"
        self.p1_credits = 10
        self.p2_credits = 10
        self.units = {
            "base_p1": Unit(
                id="base_p1",
                type="base",
                owner="P1",
                x=0,
                y=2,
                hp=UNIT_STATS["base"]["max_hp"],
                max_hp=UNIT_STATS["base"]["max_hp"],
                can_move=False,
                can_attack=False,
            ),
            "base_p2": Unit(
                id="base_p2",
                type="base",
                owner="P2",
                x=5,
                y=3,
                hp=UNIT_STATS["base"]["max_hp"],
                max_hp=UNIT_STATS["base"]["max_hp"],
                can_move=False,
                can_attack=False,
            ),
        }
        self.action_logs = ["Room initialized. Waiting for players..."]

    def log_action(self, msg: str):
        self.action_logs.append(msg)
        if len(self.action_logs) > 30:
            self.action_logs.pop(0)

    def to_dict(self) -> dict:
        return {
            "type": "game_state",
            "room_id": self.room_id,
            "status": self.status,
            "winner": self.winner,
            "active_turn": self.active_turn,
            "p1_credits": self.p1_credits,
            "p2_credits": self.p2_credits,
            "units": [u.model_dump() for u in self.units.values()],
            "action_logs": self.action_logs,
        }

    # BFS pathfinder to calculate valid cells a unit can move to.
    def get_valid_moves(self, unit_id: str) -> List[Dict[str, int]]:
        if unit_id not in self.units:
            return []
        unit = self.units[unit_id]
        if not unit.can_move or unit.type == "base":
            return []

        move_range = UNIT_STATS[unit.type]["move_range"]
        start_pos = (unit.x, unit.y)
        
        # Grid representation of obstacle positions (all unit coordinates except starting coordinates)
        obstacles: Set[tuple] = set()
        for u in self.units.values():
            if u.id != unit_id:
                obstacles.add((u.x, u.y))

        # BFS queue elements: ((x, y), path_distance)
        queue = [(start_pos, 0)]
        visited = {start_pos}
        valid_destinations = []

        while queue:
            curr_pos, dist = queue.pop(0)
            curr_x, curr_y = curr_pos

            # If within movement distance and not the starting square, it's a valid move
            if dist > 0:
                # Can only land on empty cells
                if curr_pos not in obstacles:
                    valid_destinations.append({"x": curr_x, "y": curr_y})

            if dist >= move_range:
                continue

            # Check neighbors
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = curr_x + dx, curr_y + dy
                if 0 <= nx < GRID_SIZE and 0 <= ny < GRID_SIZE:
                    neighbor = (nx, ny)
                    if neighbor not in visited:
                        # Find if there is a unit in the neighbor cell
                        neighbor_unit = next((u for u in self.units.values() if u.x == nx and u.y == ny), None)
                        
                        # Friendly unit: can pass through. Enemy unit: blocked.
                        if neighbor_unit is None or neighbor_unit.owner == unit.owner:
                            visited.add(neighbor)
                            queue.append((neighbor, dist + 1))
                            
        return valid_destinations

    def get_valid_attacks(self, unit_id: str) -> List[str]:
        if unit_id not in self.units:
            return []
        unit = self.units[unit_id]
        if not unit.can_attack or unit.type == "base":
            return []

        stats = UNIT_STATS[unit.type]
        min_range = stats["attack_min_range"]
        max_range = stats["attack_max_range"]

        valid_targets = []
        for target in self.units.values():
            if target.owner != unit.owner:
                dist = abs(unit.x - target.x) + abs(unit.y - target.y)
                if min_range <= dist <= max_range:
                    valid_targets.append(target.id)

        return valid_targets

class ConnectionManager:
    def __init__(self):
        # Format: { room_id: { "sockets": Set[WebSocket], "players": { "P1": WebSocket, "P2": WebSocket }, "state": GameState } }
        self.rooms: Dict[str, dict] = {}

    async def connect(self, websocket: WebSocket, room_id: str):
        await websocket.accept()
        if room_id not in self.rooms:
            self.rooms[room_id] = {
                "sockets": set(),
                "players": {"P1": None, "P2": None},
                "state": GameState(room_id),
            }
        
        room = self.rooms[room_id]
        room["sockets"].add(websocket)
        
        # Assign players dynamically
        assigned_role = "spectator"
        if room["players"]["P1"] is None:
            room["players"]["P1"] = websocket
            assigned_role = "P1"
            room["state"].log_action(f"Player 1 (Blue) connected to Room {room_id}")
        elif room["players"]["P2"] is None:
            room["players"]["P2"] = websocket
            assigned_role = "P2"
            room["state"].status = "active"
            room["state"].log_action(f"Player 2 (Magenta) connected. Match is ACTIVE!")
        else:
            room["state"].log_action("A spectator joined the room.")

        # Send initial assignment payload to the newly connected socket
        await websocket.send_json({
            "type": "role_assignment",
            "role": assigned_role,
            "room_id": room_id
        })

        # Broadcast the new state to all clients in the room
        await self.broadcast_state(room_id)

    async def disconnect(self, websocket: WebSocket, room_id: str):
        if room_id in self.rooms:
            room = self.rooms[room_id]
            if websocket in room["sockets"]:
                room["sockets"].remove(websocket)
            
            # Clear player assignment if their socket closed
            disconnected_role = None
            if room["players"]["P1"] == websocket:
                room["players"]["P1"] = None
                disconnected_role = "P1"
            elif room["players"]["P2"] == websocket:
                room["players"]["P2"] = None
                disconnected_role = "P2"

            if disconnected_role:
                room["state"].log_action(f"Player {disconnected_role} disconnected.")
                # Pause game status if a player disconnects
                if room["state"].status == "active":
                    room["state"].status = "waiting"

            # Clean up the room completely if no sockets are left
            if not room["sockets"]:
                del self.rooms[room_id]
                logger.info(f"Room {room_id} has been cleaned up.")
            else:
                await self.broadcast_state(room_id)

    async def send_error(self, websocket: WebSocket, msg: str):
        try:
            await websocket.send_json({
                "type": "error",
                "message": msg
            })
        except Exception as e:
            logger.error(f"Error sending payload to client: {e}")

    async def broadcast_state(self, room_id: str):
        if room_id not in self.rooms:
            return
        room = self.rooms[room_id]
        state_dict = room["state"].to_dict()
        
        # Gather all sockets to broadcast
        closed_sockets = set()
        for socket in room["sockets"]:
            try:
                await socket.send_json(state_dict)
            except Exception:
                closed_sockets.add(socket)
        
        # Clean up dead sockets
        for dead_socket in closed_sockets:
            await self.disconnect(dead_socket, room_id)

manager = ConnectionManager()

@app.websocket("/ws/game/{room_id}")
async def game_websocket_endpoint(websocket: WebSocket, room_id: str):
    await manager.connect(websocket, room_id)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                event = json.loads(data)
            except json.JSONDecodeError:
                await manager.send_error(websocket, "Invalid JSON payload.")
                continue

            room = manager.rooms.get(room_id)
            if not room:
                await websocket.close()
                break

            state: GameState = room["state"]
            
            # Identify who sent the message
            sender_role = "spectator"
            if room["players"]["P1"] == websocket:
                sender_role = "P1"
            elif room["players"]["P2"] == websocket:
                sender_role = "P2"

            action = event.get("action")
            if not action:
                await manager.send_error(websocket, "Missing 'action' parameter.")
                continue

            # Spectators cannot make turns or input commands
            if sender_role == "spectator" and action != "reset":
                await manager.send_error(websocket, "Spectators cannot perform game actions.")
                continue

            # Core validation: actions can only be executed on one's own turn (except reset)
            if action != "reset" and state.status == "active" and state.active_turn != sender_role:
                await manager.send_error(websocket, "It is not your turn.")
                continue

            # Event actions dispatcher
            if action == "spawn":
                await handle_spawn(websocket, state, sender_role, event, room_id)
            elif action == "move":
                await handle_move(websocket, state, sender_role, event, room_id)
            elif action == "attack":
                await handle_attack(websocket, state, sender_role, event, room_id)
            elif action == "end_turn":
                await handle_end_turn(state, sender_role, room_id)
            elif action == "reset":
                await handle_reset(state, sender_role, room_id)
            else:
                await manager.send_error(websocket, f"Unknown action type: {action}")

    except WebSocketDisconnect:
        await manager.disconnect(websocket, room_id)
    except Exception as e:
        logger.error(f"WebSocket execution error: {e}")
        await manager.disconnect(websocket, room_id)


# Event Handlers

async def handle_spawn(websocket: WebSocket, state: GameState, role: str, event: dict, room_id: str):
    if state.status != "active":
        await manager.send_error(websocket, "Game is not active.")
        return

    unit_type = event.get("unit_type")
    x = event.get("x")
    y = event.get("y")

    if unit_type not in ["infantry", "tank", "artillery"]:
        await manager.send_error(websocket, "Invalid unit type.")
        return
    if x is None or y is None or not (0 <= x < GRID_SIZE and 0 <= y < GRID_SIZE):
        await manager.send_error(websocket, "Coordinates are out of grid limits.")
        return

    # Check credits
    cost = UNIT_STATS[unit_type]["cost"]
    player_credits = state.p1_credits if role == "P1" else state.p2_credits
    if player_credits < cost:
        await manager.send_error(websocket, f"Insufficient credits. Cost: {cost}, Available: {player_credits}")
        return

    # Starting row limits: P1 can spawn on row 0, P2 can spawn on row 5
    spawn_row = 0 if role == "P1" else 5
    if x != spawn_row:
        await manager.send_error(websocket, f"You can only spawn units on your home row (Row {spawn_row}).")
        return

    # Check tile occupancy
    occupied = any(u.x == x and u.y == y for u in state.units.values())
    if occupied:
        await manager.send_error(websocket, "Spawn tile is already occupied.")
        return

    # Spawn unit
    unit_id = f"{unit_type}_{uuid.uuid4().hex[:6]}"
    max_hp = UNIT_STATS[unit_type]["max_hp"]
    new_unit = Unit(
        id=unit_id,
        type=unit_type,
        owner=role,
        x=x,
        y=y,
        hp=max_hp,
        max_hp=max_hp,
        can_move=False,  # Cannot act on the turn they are spawned
        can_attack=False,
    )
    state.units[unit_id] = new_unit

    # Deduct credits
    if role == "P1":
        state.p1_credits -= cost
    else:
        state.p2_credits -= cost

    state.log_action(f"Player {role} spawned {unit_type.capitalize()} at ({x}, {y}).")
    await manager.broadcast_state(room_id)


async def handle_move(websocket: WebSocket, state: GameState, role: str, event: dict, room_id: str):
    if state.status != "active":
        await manager.send_error(websocket, "Game is not active.")
        return

    unit_id = event.get("unit_id")
    to_x = event.get("to_x")
    to_y = event.get("to_y")

    if not unit_id or to_x is None or to_y is None:
        await manager.send_error(websocket, "Missing required move parameters.")
        return

    if unit_id not in state.units:
        await manager.send_error(websocket, "Unit not found.")
        return

    unit = state.units[unit_id]
    if unit.owner != role:
        await manager.send_error(websocket, "You do not own this unit.")
        return

    if not unit.can_move:
        await manager.send_error(websocket, "This unit has already moved or was just spawned.")
        return

    # Check if target destination is within the reachability list
    valid_moves = state.get_valid_moves(unit_id)
    is_valid = any(m["x"] == to_x and m["y"] == to_y for m in valid_moves)
    if not is_valid:
        await manager.send_error(websocket, "Invalid move path or destination is blocked.")
        return

    # Execute move
    old_x, old_y = unit.x, unit.y
    unit.x = to_x
    unit.y = to_y
    unit.can_move = False  # Mark moved

    state.log_action(f"Player {role}: {unit.type.capitalize()} moved ({old_x}, {old_y}) -> ({to_x}, {to_y}).")
    await manager.broadcast_state(room_id)


async def handle_attack(websocket: WebSocket, state: GameState, role: str, event: dict, room_id: str):
    if state.status != "active":
        await manager.send_error(websocket, "Game is not active.")
        return

    attacker_id = event.get("attacker_id")
    target_id = event.get("target_id")

    if not attacker_id or not target_id:
        await manager.send_error(websocket, "Missing combat indicators.")
        return

    if attacker_id not in state.units:
        await manager.send_error(websocket, "Attacking unit not found.")
        return
    if target_id not in state.units:
        await manager.send_error(websocket, "Target combat target not found.")
        return

    attacker = state.units[attacker_id]
    target = state.units[target_id]

    if attacker.owner != role:
        await manager.send_error(websocket, "You do not control the attacking unit.")
        return
    if target.owner == role:
        await manager.send_error(websocket, "Friendly fire is disabled.")
        return
    if not attacker.can_attack:
        await manager.send_error(websocket, "This unit has already attacked this turn.")
        return

    # Check distance constraint
    valid_attacks = state.get_valid_attacks(attacker_id)
    if target_id not in valid_attacks:
        await manager.send_error(websocket, "Target is out of weapon range.")
        return

    # Calculate damage
    damage = UNIT_STATS[attacker.type]["damage"]
    target.hp -= damage
    attacker.can_attack = False

    state.log_action(f"Player {role}: {attacker.type.capitalize()} attacked enemy {target.type.capitalize()} (-{damage} HP).")

    # Check health status
    if target.hp <= 0:
        state.log_action(f"Enemy {target.type.capitalize()} was DESTROYED!")
        del state.units[target_id]

        # Check win condition: base command stations
        if target_id == "base_p1":
            state.status = "game_over"
            state.winner = "P2"
            state.log_action("Base Command Station P1 destroyed! Player 2 (Magenta) wins!")
        elif target_id == "base_p2":
            state.status = "game_over"
            state.winner = "P1"
            state.log_action("Base Command Station P2 destroyed! Player 1 (Blue) wins!")
            
    await manager.broadcast_state(room_id)


async def handle_end_turn(state: GameState, role: str, room_id: str):
    if state.status != "active":
        return

    # Toggle active player turn
    next_turn = "P2" if state.active_turn == "P1" else "P1"
    state.active_turn = next_turn

    # Add credits to the player starting their turn
    if next_turn == "P1":
        state.p1_credits += 3
    else:
        state.p2_credits += 3

    # Reset units' move & attack abilities for the player starting their turn
    for unit in state.units.values():
        if unit.owner == next_turn:
            # bases can never move or attack
            if unit.type != "base":
                unit.can_move = True
                unit.can_attack = True

    state.log_action(f"Turn passed to Player {next_turn}. Credit generated.")
    await manager.broadcast_state(room_id)


async def handle_reset(state: GameState, role: str, room_id: str):
    state.reset_board()
    # If there are two players in the room, start the game instantly
    room = manager.rooms.get(room_id)
    if room and room["players"]["P1"] is not None and room["players"]["P2"] is not None:
        state.status = "active"
        state.log_action("Board reset. Match is active!")
    else:
        state.log_action(f"Board reset by {role}. Waiting for players...")
    await manager.broadcast_state(room_id)
