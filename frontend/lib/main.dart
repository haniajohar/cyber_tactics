import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const CyberTacticsApp());
}

class CyberTacticsApp extends StatelessWidget {
  const CyberTacticsApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyber Tactics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF), // Neon Cyan (Player 1)
          secondary: Color(0xFFFF007F), // Neon Magenta (Player 2)
          surface: Color(0xFF111520),
          background: Color(0xFF080A0F),
          error: Color(0xFFFF1744),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'monospace', color: Color(0xFFC0C5D0)),
          bodyMedium: TextStyle(fontFamily: 'monospace', color: Color(0xFF9095A2)),
          titleLarge: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 2.0),
        ),
      ),
      home: const GameScreen(),
    );
  }
}

// Unit Model
class Unit {
  final String id;
  final String type; // "base" | "infantry" | "tank" | "artillery"
  final String owner; // "P1" | "P2"
  final int x;
  final int y;
  final int hp;
  final int maxHp;
  final bool canMove;
  final bool canAttack;

  Unit({
    required this.id,
    required this.type,
    required this.owner,
    required this.x,
    required this.y,
    required this.hp,
    required this.maxHp,
    required this.canMove,
    required this.canAttack,
  });

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'] as String,
      type: json['type'] as String,
      owner: json['owner'] as String,
      x: json['x'] as int,
      y: json['y'] as int,
      hp: json['hp'] as int,
      maxHp: json['max_hp'] as int,
      canMove: json['can_move'] as bool,
      canAttack: json['can_attack'] as bool,
    );
  }
}

// Game Screen (handles connection state, board state, and layout)
class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _serverIpController = TextEditingController(text: 'ws://localhost:8000');
  final TextEditingController _roomController = TextEditingController(text: 'lobby');

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _myRole = 'spectator'; // "P1" | "P2" | "spectator"
  String _currentRoom = '';

  // Game States received from Server
  String _gameStatus = 'waiting'; // "waiting" | "active" | "game_over"
  String? _winner;
  String _activeTurn = 'P1';
  int _p1Credits = 10;
  int _p2Credits = 10;
  Map<String, Unit> _units = {};
  List<String> _actionLogs = [];

  // Local selection states
  String? _selectedUnitId;
  String? _selectedSpawnType; // "infantry" | "tank" | "artillery"
  List<Map<String, int>> _validMoves = [];
  List<String> _validAttacks = [];

  String? _errorMessage;
  Timer? _errorTimer;

  // Pulse animation for UI highlights
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _channel?.sink.close();
    _errorTimer?.cancel();
    _serverIpController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    _errorTimer?.cancel();
    setState(() {
      _errorMessage = msg;
    });
    _errorTimer = Timer(const Duration(seconds: 4), () {
      setState(() {
        _errorMessage = null;
      });
    });
  }

  // Connect to the backend WebSockets
  void _connect() {
    if (_isConnecting || _isConnected) return;
    
    final room = _roomController.text.trim();
    final serverUrl = '${_serverIpController.text.trim()}/ws/game/$room';
    
    if (room.isEmpty) {
      _showError('Room ID cannot be empty');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          _handleServerMessage(data);
        },
        onError: (err) {
          _handleDisconnect();
          _showError('Connection Error: Make sure backend is running');
        },
        onDone: () {
          _handleDisconnect();
        },
      );
    } catch (e) {
      _handleDisconnect();
      _showError('Failed to establish WebSocket link: $e');
    }
  }

  void _handleDisconnect() {
    setState(() {
      _isConnected = false;
      _isConnecting = false;
      _myRole = 'spectator';
      _units.clear();
      _actionLogs.clear();
      _selectedUnitId = null;
      _selectedSpawnType = null;
      _validMoves.clear();
      _validAttacks.clear();
    });
  }

  void _handleServerMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    
    if (type == 'role_assignment') {
      setState(() {
        _myRole = data['role'] as String;
        _currentRoom = data['room_id'] as String;
        _isConnected = true;
        _isConnecting = false;
      });
    } else if (type == 'game_state') {
      setState(() {
        _gameStatus = data['status'] as String;
        _winner = data['winner'] as String?;
        _activeTurn = data['active_turn'] as String;
        _p1Credits = data['p1_credits'] as int;
        _p2Credits = data['p2_credits'] as int;
        
        final rawUnits = data['units'] as List<dynamic>;
        _units.clear();
        for (var u in rawUnits) {
          final unit = Unit.fromJson(u as Map<String, dynamic>);
          _units[unit.id] = unit;
        }

        final rawLogs = data['action_logs'] as List<dynamic>;
        _actionLogs = rawLogs.map((l) => l as String).toList();

        // Clear invalid local selections
        if (_selectedUnitId != null && !_units.containsKey(_selectedUnitId)) {
          _selectedUnitId = null;
          _validMoves.clear();
          _validAttacks.clear();
        } else if (_selectedUnitId != null) {
          // Recalculate options
          _calculateTacticalDomains();
        }
      });
    } else if (type == 'error') {
      _showError(data['message'] as String);
    }
  }

  void _sendAction(Map<String, dynamic> payload) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(payload));
    } else {
      _showError('Not connected to the tactical link');
    }
  }

  // Calculate movements and attacks client-side using the identical backend formula
  void _calculateTacticalDomains() {
    if (_selectedUnitId == null) return;
    final unit = _units[_selectedUnitId!];
    if (unit == null || unit.owner != _myRole || _activeTurn != _myRole || _gameStatus != 'active') {
      setState(() {
        _validMoves.clear();
        _validAttacks.clear();
      });
      return;
    }

    // BFS Pathfinder for moves
    final moves = <Map<String, int>>[];
    if (unit.canMove && unit.type != 'base') {
      final moveRange = _getMoveRange(unit.type);
      final queue = <_PathNode>[_PathNode(unit.x, unit.y, 0)];
      final visited = <String>{'${unit.x},${unit.y}'};

      // Mark coordinates of other units (blockers)
      final obstacles = <String>{};
      for (var u in _units.values) {
        if (u.id != unit.id) {
          obstacles.add('${u.x},${u.y}');
        }
      }

      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);

        if (current.dist > 0) {
          if (!obstacles.contains('${current.x},${current.y}')) {
            moves.add({'x': current.x, 'y': current.y});
          }
        }

        if (current.dist >= moveRange) continue;

        // Orthogonal checking
        final directions = [
          [-1, 0], [1, 0], [0, -1], [0, 1]
        ];

        for (var dir in directions) {
          final nx = current.x + dir[0];
          final ny = current.y + dir[1];

          if (nx >= 0 && nx < 6 && ny >= 0 && ny < 6) {
            final key = '$nx,$ny';
            if (!visited.contains(key)) {
              // Find if there is a unit here
              final occupyingUnit = _units.values.firstWhere(
                (u) => u.x == nx && u.y == ny,
                orElse: () => Unit(id: '', type: 'none', owner: '', x: -1, y: -1, hp: 0, maxHp: 0, canMove: false, canAttack: false),
              );

              // Friendly: pass-through, Enemy: block
              if (occupyingUnit.type == 'none' || occupyingUnit.owner == unit.owner) {
                visited.add(key);
                queue.add(_PathNode(nx, ny, current.dist + 1));
              }
            }
          }
        }
      }
    }

    // Attacks calculation
    final attacks = <String>[];
    if (unit.canAttack && unit.type != 'base') {
      final ranges = _getAttackRange(unit.type);
      final minRange = ranges[0];
      final maxRange = ranges[1];

      for (var target in _units.values) {
        if (target.owner != unit.owner) {
          final dist = (unit.x - target.x).abs() + (unit.y - target.y).abs();
          if (dist >= minRange && dist <= maxRange) {
            attacks.add(target.id);
          }
        }
      }
    }

    setState(() {
      _validMoves = moves;
      _validAttacks = attacks;
    });
  }

  int _getMoveRange(String type) {
    if (type == 'infantry') return 2;
    if (type == 'tank') return 3;
    if (type == 'artillery') return 1;
    return 0;
  }

  List<int> _getAttackRange(String type) {
    if (type == 'infantry') return [1, 1];
    if (type == 'tank') return [1, 1];
    if (type == 'artillery') return [2, 3];
    return [0, 0];
  }

  int _getCost(String type) {
    if (type == 'infantry') return 3;
    if (type == 'tank') return 6;
    if (type == 'artillery') return 5;
    return 0;
  }

  // Handle Board Selection & Actions
  void _onCellTapped(int x, int y) {
    if (!_isConnected || _gameStatus != 'active') return;
    if (_activeTurn != _myRole) {
      _showError("It's not your turn");
      return;
    }

    // Check if spawn mode is active
    if (_selectedSpawnType != null) {
      final cost = _getCost(_selectedSpawnType!);
      final credits = _myRole == 'P1' ? _p1Credits : _p2Credits;

      if (credits < cost) {
        _showError('Insufficient credits');
        setState(() {
          _selectedSpawnType = null;
        });
        return;
      }

      final homeRow = _myRole == 'P1' ? 0 : 5;
      if (x != homeRow) {
        _showError('Must spawn on your home row (Row $homeRow)');
        setState(() {
          _selectedSpawnType = null;
        });
        return;
      }

      final occupied = _units.values.any((u) => u.x == x && u.y == y);
      if (occupied) {
        _showError('Spawn tile is blocked');
        setState(() {
          _selectedSpawnType = null;
        });
        return;
      }

      // Execute spawn
      _sendAction({
        'action': 'spawn',
        'unit_type': _selectedSpawnType,
        'x': x,
        'y': y,
      });

      setState(() {
        _selectedSpawnType = null;
      });
      return;
    }

    // Find if there's a unit on the cell
    final clickedUnit = _units.values.firstWhere(
      (u) => u.x == x && u.y == y,
      orElse: () => Unit(id: '', type: 'none', owner: '', x: -1, y: -1, hp: 0, maxHp: 0, canMove: false, canAttack: false),
    );

    // If unit is clicked
    if (clickedUnit.type != 'none') {
      // If player owns the clicked unit, select it
      if (clickedUnit.owner == _myRole) {
        if (clickedUnit.type == 'base') {
          _showError('Base units cannot move or attack');
          return;
        }
        setState(() {
          _selectedUnitId = clickedUnit.id;
          _calculateTacticalDomains();
        });
      } 
      // If clicking an enemy unit while we have a selected unit
      else if (_selectedUnitId != null) {
        // Check if the clicked enemy unit is in range
        if (_validAttacks.contains(clickedUnit.id)) {
          _sendAction({
            'action': 'attack',
            'attacker_id': _selectedUnitId,
            'target_id': clickedUnit.id,
          });
          setState(() {
            _selectedUnitId = null;
            _validMoves.clear();
            _validAttacks.clear();
          });
        } else {
          _showError('Target is out of weapon range');
        }
      }
    } 
    // If clicking an empty cell while a unit is selected
    else if (_selectedUnitId != null) {
      final isMoveValid = _validMoves.any((m) => m['x'] == x && m['y'] == y);
      if (isMoveValid) {
        _sendAction({
          'action': 'move',
          'unit_id': _selectedUnitId,
          'to_x': x,
          'to_y': y,
        });
        setState(() {
          _selectedUnitId = null;
          _validMoves.clear();
          _validAttacks.clear();
        });
      } else {
        // Deselect
        setState(() {
          _selectedUnitId = null;
          _validMoves.clear();
          _validAttacks.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF080A0F), Color(0xFF0C101A)],
            ),
          ),
          child: Column(
            children: [
              // Neon Header
              _buildHeader(theme),

              if (!_isConnected)
                Expanded(child: _buildLobby(theme))
              else
                Expanded(
                  child: Row(
                    children: [
                      // Sidebar Control Panel (For tablets and desktops)
                      if (size.width > 900)
                        Container(
                          width: 300,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Color(0xFF1E2638), width: 1),
                            ),
                          ),
                          child: _buildControlPanel(theme),
                        ),

                      // Main Board View
                      Expanded(
                        child: Column(
                          children: [
                            // State / Stats HUD
                            _buildHUD(theme),

                            // Grid Board container
                            Expanded(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: _buildGridBoard(),
                                  ),
                                ),
                              ),
                            ),

                            // Mobile Action Panel (For smaller widths)
                            if (size.width <= 900) _buildMobileActionPanel(theme),

                            // Logs Console
                            _buildLogsConsole(theme),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Header Bar with Scanlines
  Widget _buildHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF0C101A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF00F0FF), width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isConnected ? const Color(0xFF00FF66) : const Color(0xFFFF1744),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _isConnected ? const Color(0xFF00FF66).withOpacity(0.5) : const Color(0xFFFF1744).withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'CYBER TACTICS',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF00F0FF),
                  fontSize: 20,
                  shadows: [
                    const Shadow(
                      color: Color(0xFF00F0FF),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'v1.0.0',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF00F0FF).withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (_isConnected)
            Row(
              children: [
                _buildRoleBadge(_myRole),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.power_settings_new, color: Color(0xFFFF1744)),
                  onPressed: () {
                    _channel?.sink.close();
                    _handleDisconnect();
                  },
                  tooltip: 'Disconnect Link',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    Color color = Colors.white;
    String label = 'SPECTATOR';
    if (role == 'P1') {
      color = const Color(0xFF00F0FF);
      label = 'P1: BLUE';
    } else if (role == 'P2') {
      color = const Color(0xFFFF007F);
      label = 'P2: MAGENTA';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Lobby UI connecting to WebSocket
  Widget _buildLobby(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.all(24.0),
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: const Color(0xFF111520),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E2638), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 15,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ESTABLISH NEURAL LINK',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF00F0FF),
                  fontSize: 16,
                  letterSpacing: 3.0,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _serverIpController,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'TACTICAL SERVER LINK',
                  labelStyle: TextStyle(fontFamily: 'monospace', color: Color(0xFF9095A2)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1E2638)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00F0FF)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _roomController,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'ROOM COORDINATES ID',
                  labelStyle: TextStyle(fontFamily: 'monospace', color: Color(0xFF9095A2)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1E2638)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00F0FF)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isConnecting ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F0FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 5,
                ),
                child: _isConnecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      )
                    : const Text(
                        'INITIALIZE LINK',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744).withOpacity(0.15),
                    border: Border.all(color: const Color(0xFFFF1744), width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF1744),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // HUD Bar containing Player Stats and Turn state
  Widget _buildHUD(ThemeData theme) {
    final activeColor = _activeTurn == 'P1' ? const Color(0xFF00F0FF) : const Color(0xFFFF007F);
    
    // Status text formatter
    String statusLabel = '';
    if (_gameStatus == 'waiting') {
      statusLabel = 'WAITING FOR OPPONENT...';
    } else if (_gameStatus == 'active') {
      if (_activeTurn == _myRole) {
        statusLabel = 'YOUR TACTICAL PHASE';
      } else {
        statusLabel = 'OPPONENT PHASE';
      }
    } else if (_gameStatus == 'game_over') {
      statusLabel = 'TACTICAL SEQUENCE OVER: ${_winner == _myRole ? 'VICTORY' : 'DEFEAT'}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: const Color(0xFF0D121F),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Player 1 Stats
              _buildPlayerStatsCard('PLAYER 1', _p1Credits, 'base_p1', const Color(0xFF00F0FF)),

              // Dynamic Status Center indicator
              Expanded(
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Text(
                          statusLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.5,
                            color: _gameStatus == 'game_over'
                                ? (_winner == _myRole ? const Color(0xFF00FF66) : const Color(0xFFFF1744))
                                : activeColor.withOpacity(_pulseAnimation.value),
                            shadows: [
                              Shadow(
                                color: _gameStatus == 'game_over'
                                    ? (_winner == _myRole ? const Color(0xFF00FF66) : const Color(0xFFFF1744))
                                    : activeColor,
                                blurRadius: 8 * _pulseAnimation.value,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Turn: $_activeTurn',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF9095A2),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              // Player 2 Stats
              _buildPlayerStatsCard('PLAYER 2', _p2Credits, 'base_p2', const Color(0xFFFF007F)),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              color: const Color(0xFFFF1744).withOpacity(0.15),
              child: Text(
                'LINK WARNING: $_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF1744), fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildPlayerStatsCard(String name, int credits, String baseId, Color neonColor) {
    final base = _units[baseId];
    final hp = base?.hp ?? 0;
    final maxHp = base?.maxHp ?? 100;
    final hpPercentage = hp / maxHp;

    return Container(
      width: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF131826),
        border: Border.all(color: neonColor.withOpacity(0.4), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontFamily: 'monospace',
              color: neonColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Credits: $credits',
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Colors.white,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Base HP: ',
                style: TextStyle(fontFamily: 'monospace', color: Color(0xFF9095A2), fontSize: 9),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2638),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: hpPercentage.clamp(0.0, 1.0),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: neonColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$hp',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: hp < 30 ? const Color(0xFFFF1744) : Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Large Sidebar Controls (Desktop/Tablet)
  Widget _buildControlPanel(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'COMMAND STATION',
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 14, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF1E2638)),
          const SizedBox(height: 8),
          _buildDeployPanel(theme),
          const Spacer(),
          ElevatedButton(
            onPressed: (_gameStatus == 'active' && _activeTurn == _myRole)
                ? () => _sendAction({'action': 'end_turn'})
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF66),
              foregroundColor: Colors.black,
              disabledBackgroundColor: const Color(0xFF1E2638),
              disabledForegroundColor: const Color(0xFF9095A2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('END TURNS SEQUENCE', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _sendAction({'action': 'reset'}),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFF1744)),
              foregroundColor: const Color(0xFFFF1744),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('RESET GRID TACTICS', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Small Overlay Action Panel (Mobile View)
  Widget _buildMobileActionPanel(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF0C101A),
        border: Border(top: BorderSide(color: Color(0xFF1E2638))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSpawnButton('infantry', 'INFANTRY (3c)', theme),
              _buildSpawnButton('tank', 'TANK (6c)', theme),
              _buildSpawnButton('artillery', 'ARTILLERY (5c)', theme),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: (_gameStatus == 'active' && _activeTurn == _myRole)
                      ? () => _sendAction({'action': 'end_turn'})
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF66),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF1E2638),
                    disabledForegroundColor: const Color(0xFF9095A2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('END TURN', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _sendAction({'action': 'reset'}),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFF1744)),
                  foregroundColor: const Color(0xFFFF1744),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: const Text('RESET', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Spawn deployment builder
  Widget _buildDeployPanel(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'SPAWN REINFORCEMENTS',
          style: TextStyle(fontFamily: 'monospace', color: Color(0xFF9095A2), fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildSpawnButton('infantry', 'INFANTRY (Cost: 3)', theme),
        const SizedBox(height: 8),
        _buildSpawnButton('tank', 'TANK (Cost: 6)', theme),
        const SizedBox(height: 8),
        _buildSpawnButton('artillery', 'ARTILLERY (Cost: 5)', theme),
        if (_selectedSpawnType != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00FF66).withOpacity(0.1),
              border: Border.all(color: const Color(0xFF00FF66)),
            ),
            child: Text(
              'DEPLOY MODE: Click on any empty tile on your home row to materialize ${_selectedSpawnType!.toUpperCase()}',
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF00FF66)),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildSpawnButton(String type, String title, ThemeData theme) {
    final bool isSelected = _selectedSpawnType == type;
    final int cost = _getCost(type);
    final int credits = _myRole == 'P1' ? _p1Credits : _p2Credits;
    final bool canAfford = credits >= cost && _activeTurn == _myRole && _gameStatus == 'active';

    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: canAfford
            ? () {
                setState(() {
                  _selectedSpawnType = isSelected ? null : type;
                  _selectedUnitId = null; // Deselect active unit
                  _validMoves.clear();
                  _validAttacks.clear();
                });
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? const Color(0xFF00FF66) : const Color(0xFF1E2638),
          foregroundColor: isSelected ? Colors.black : Colors.white,
          disabledBackgroundColor: const Color(0xFF111520),
          disabledForegroundColor: Colors.white.withOpacity(0.15),
          side: isSelected
              ? const BorderSide(color: Color(0xFF00FF66), width: 1)
              : BorderSide(color: const Color(0xFF1E2638).withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(
          title,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // The 6x6 Matrix Board Widget
  Widget _buildGridBoard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C101A),
        border: Border.all(color: const Color(0xFF1E2638), width: 2),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          childAspectRatio: 1.0,
        ),
        itemCount: 36,
        itemBuilder: (context, index) {
          final x = index ~/ 6;
          final y = index % 6;

          // Find if there's a unit in this coordinate
          final unit = _units.values.firstWhere(
            (u) => u.x == x && u.y == y,
            orElse: () => Unit(id: '', type: 'none', owner: '', x: -1, y: -1, hp: 0, maxHp: 0, canMove: false, canAttack: false),
          );

          final isSelected = _selectedUnitId != null && _units[_selectedUnitId!]?.x == x && _units[_selectedUnitId!]?.y == y;
          
          final isMoveTarget = _validMoves.any((m) => m['x'] == x && m['y'] == y);
          final isAttackTarget = unit.type != 'none' && _validAttacks.contains(unit.id);
          
          final isSpawnTarget = _selectedSpawnType != null &&
              x == (_myRole == 'P1' ? 0 : 5) &&
              unit.type == 'none';

          return GestureDetector(
            onTap: () => _onCellTapped(x, y),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1E2638).withOpacity(0.4), width: 0.5),
                color: _getCellBackgroundColor(x, y, isSelected, isMoveTarget, isAttackTarget, isSpawnTarget),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Coordinates tag
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Text(
                      '($x,$y)',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white.withOpacity(0.12),
                        fontSize: 8,
                      ),
                    ),
                  ),

                  // Draw Unit Graphic
                  if (unit.type != 'none')
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        final canAct = unit.owner == _myRole && 
                                       _activeTurn == _myRole && 
                                       _gameStatus == 'active' && 
                                       (unit.canMove || unit.canAttack);
                        
                        return CustomPaint(
                          painter: UnitPainter(
                            type: unit.type,
                            owner: unit.owner,
                            hp: unit.hp,
                            maxHp: unit.maxHp,
                            pulse: canAct ? _pulseAnimation.value : 0.0,
                            isSelected: isSelected,
                          ),
                        );
                      },
                    ),

                  // Overlay Glow for tactical choices
                  if (isMoveTarget)
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF00F0FF).withOpacity(_pulseAnimation.value), width: 1.5),
                            color: const Color(0xFF00F0FF).withOpacity(0.08 * _pulseAnimation.value),
                          ),
                        );
                      },
                    ),
                  
                  if (isAttackTarget)
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFFF1744).withOpacity(_pulseAnimation.value), width: 2),
                            color: const Color(0xFFFF1744).withOpacity(0.12 * _pulseAnimation.value),
                          ),
                          child: const Icon(
                            Icons.center_focus_strong,
                            color: Color(0xFFFF1744),
                            size: 18,
                          ),
                        );
                      },
                    ),

                  if (isSpawnTarget)
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF00FF66).withOpacity(_pulseAnimation.value), width: 1.5),
                            color: const Color(0xFF00FF66).withOpacity(0.08 * _pulseAnimation.value),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getCellBackgroundColor(int x, int y, bool selected, bool move, bool attack, bool spawn) {
    if (selected) return const Color(0xFF282110);
    
    // Grid checkered floor pattern
    final isEven = (x + y) % 2 == 0;
    return isEven ? const Color(0xFF0D111A) : const Color(0xFF0A0D15);
  }

  // Scrolling Green/Black CLI Console log widget
  Widget _buildLogsConsole(ThemeData theme) {
    final ScrollController scrollController = ScrollController();
    
    // Proactive autoscroll to bottom when logs change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });

    return Container(
      width: double.infinity,
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF04060A),
        border: Border(
          top: BorderSide(color: Color(0xFF1E2638), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SYSTEM LOG: SECURE CONNECTION ACTIVE',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Color(0xFF00FF66),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _actionLogs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(
                    '> ${_actionLogs[index]}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFC0C5D0),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter to draw modern vector neon units
class UnitPainter extends CustomPainter {
  final String type;
  final String owner;
  final int hp;
  final int maxHp;
  final double pulse;
  final bool isSelected;

  UnitPainter({
    required this.type,
    required this.owner,
    required this.hp,
    required this.maxHp,
    required this.pulse,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = owner == 'P1' ? const Color(0xFF00F0FF) : const Color(0xFFFF007F);
    
    // Glow paint
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3.0);

    // Vector drawing paint
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.35;

    // Draw active selector pulse
    if (pulse > 0.0) {
      final pulsePaint = Paint()
        ..color = color.withOpacity(0.3 * (1.0 - pulse))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius + (15.0 * pulse), pulsePaint);
    }

    // DRAW SHAPES
    if (type == 'base') {
      // Base Tower drawing
      final path = Path()
        ..moveTo(center.dx, center.dy - radius)
        ..lineTo(center.dx - radius * 0.8, center.dy + radius * 0.8)
        ..lineTo(center.dx + radius * 0.8, center.dy + radius * 0.8)
        ..close();
      
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);

      // Radar dish on top
      canvas.drawCircle(Offset(center.dx, center.dy - radius * 0.2), radius * 0.25, paint);
      canvas.drawCircle(Offset(center.dx, center.dy - radius * 0.2), radius * 0.25, glowPaint);
      
      // Base outline ring
      canvas.drawCircle(center, radius + 2, Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0);
    } 
    else if (type == 'infantry') {
      // Double Chevron pointing up
      final double spacer = size.height * 0.15;
      final path = Path()
        ..moveTo(center.dx - radius * 0.7, center.dy + radius * 0.5)
        ..lineTo(center.dx, center.dy - radius * 0.3)
        ..lineTo(center.dx + radius * 0.7, center.dy + radius * 0.5)
        ..moveTo(center.dx - radius * 0.7, center.dy + radius * 0.5 - spacer)
        ..lineTo(center.dx, center.dy - radius * 0.3 - spacer)
        ..lineTo(center.dx + radius * 0.7, center.dy + radius * 0.5 - spacer);

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);
      
      // Core glowing spark
      canvas.drawCircle(Offset(center.dx, center.dy + radius * 0.4), 3, Paint()
        ..color = color
        ..style = PaintingStyle.fill);
    } 
    else if (type == 'tank') {
      // Hexagonal block
      final path = Path()
        ..moveTo(center.dx - radius * 0.8, center.dy - radius * 0.4)
        ..lineTo(center.dx + radius * 0.8, center.dy - radius * 0.4)
        ..lineTo(center.dx + radius, center.dy + radius * 0.5)
        ..lineTo(center.dx - radius, center.dy + radius * 0.5)
        ..close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);

      // Tank Gun barrel (pointing up for P1, down for P2)
      final double barrelDir = owner == 'P1' ? -1 : 1;
      canvas.drawLine(
        center, 
        Offset(center.dx, center.dy + (radius * 0.9 * barrelDir)),
        Paint()
          ..color = color
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke
      );
    } 
    else if (type == 'artillery') {
      // Target Diamond with crossing crosshairs
      final path = Path()
        ..moveTo(center.dx, center.dy - radius * 0.7)
        ..lineTo(center.dx + radius * 0.7, center.dy)
        ..lineTo(center.dx, center.dy + radius * 0.7)
        ..lineTo(center.dx - radius * 0.7, center.dy)
        ..close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);

      // Target lines
      canvas.drawLine(Offset(center.dx - radius * 1.1, center.dy), Offset(center.dx + radius * 1.1, center.dy), paint);
      canvas.drawLine(Offset(center.dx, center.dy - radius * 1.1), Offset(center.dx, center.dy + radius * 1.1), paint);
    }

    // DRAW UNIT HEALTH METRIC
    if (type != 'base') {
      final hpPct = hp / maxHp;
      final healthBarWidth = size.width * 0.7;
      final healthBarHeight = 3.0;
      final startOffset = Offset(size.width * 0.15, size.height * 0.85);

      // Health bar BG (dark grey)
      canvas.drawRect(
        Rect.fromLTWH(startOffset.dx, startOffset.dy, healthBarWidth, healthBarHeight),
        Paint()..color = const Color(0xFF1E2638)
      );

      // Health bar fill
      final healthColor = hpPct < 0.35 ? const Color(0xFFFF1744) : const Color(0xFF00FF66);
      canvas.drawRect(
        Rect.fromLTWH(startOffset.dx, startOffset.dy, healthBarWidth * hpPct.clamp(0.0, 1.0), healthBarHeight),
        Paint()..color = healthColor
      );
    }
  }

  @override
  bool shouldRepaint(covariant UnitPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.owner != owner ||
        oldDelegate.hp != hp ||
        oldDelegate.pulse != pulse ||
        oldDelegate.isSelected != isSelected;
  }
}

// BFS PathNode helper
class _PathNode {
  final int x;
  final int y;
  final int dist;

  _PathNode(this.x, this.y, this.dist);
}
