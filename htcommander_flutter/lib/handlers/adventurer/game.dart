import 'dart:convert';
import 'dart:math';

import 'game_data.dart';
import 'game_io.dart';

/// Main text adventure game engine.
///
/// This is a ham-radio-themed text adventure game inspired by the classic
/// Scott Adams adventure system. It is an Easter egg hidden in HTCommander-X.
///
/// Commands: go/move, look, take/get, drop, inventory/i, use, examine/read,
/// open, climb, tie, transmit/cq, score, save, restore, quit, help.
class AdventurerGame {
  final GameIO io = GameIO();
  final Random _rnd = Random();

  late List<Room> _rooms;
  late List<Item> _items;
  int _currentRoom = GameDataStore.startRoom;
  int _turnCounter = 0;
  int _lampLife = GameDataStore.initialLampLife;
  bool _lampLit = false;
  bool _gameOver = false;
  bool _bunkerUnlocked = false;
  bool _ladderPlaced = false;
  bool _crystalRevealed = false;

  /// Whether the game has ended.
  bool get isGameOver => _gameOver;

  /// Current turn count.
  int get turnCounter => _turnCounter;

  /// Initialize the game world.
  void start() {
    _rooms = GameDataStore.buildRooms();
    _items = GameDataStore.buildItems();
    _currentRoom = GameDataStore.startRoom;
    _turnCounter = 0;
    _lampLife = GameDataStore.initialLampLife;
    _lampLit = false;
    _gameOver = false;
    _bunkerUnlocked = false;
    _ladderPlaced = false;
    _crystalRevealed = false;

    io.writeLine('=== ADVENTURER: The Ham Radio Quest ===');
    io.writeLine('');
    io.writeLine(
      'You are a ham radio operator on a mission to find three rare '
      'treasures and store them in the hidden chamber beneath the '
      'emergency bunker.',
    );
    io.writeLine('Type HELP for a list of commands.');
    io.writeLine('');
    _look();
  }

  /// Process a player command and return all output text.
  String processCommand(String input) {
    if (_gameOver) {
      io.writeLine('The game is over. Type QUIT to exit or RESTORE to load.');
      return io.flush();
    }

    _turnCounter++;
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      io.writeLine(GameDataStore.sysMessages[11]); // What?
      return io.flush();
    }

    final parts =
        trimmed.toUpperCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final verb = parts[0];
    final noun = parts.length > 1 ? parts[1] : null;

    // Check if verb is a direction shortcut.
    final dirIndex = _findDirection(verb);
    if (dirIndex >= 0) {
      _doGo(GameDataStore.directions[dirIndex]);
    } else {
      switch (verb) {
        case 'GO':
        case 'MOVE':
        case 'WALK':
          if (noun == null) {
            io.writeLine(GameDataStore.sysMessages[10]); // direction needed
          } else {
            _doGo(noun);
          }
        case 'TAKE':
        case 'GET':
        case 'GRAB':
        case 'PICK':
          if (noun == null) {
            io.writeLine(GameDataStore.sysMessages[11]); // What?
          } else {
            _doTake(noun);
          }
        case 'DROP':
        case 'PUT':
          if (noun == null) {
            io.writeLine(GameDataStore.sysMessages[11]); // What?
          } else {
            _doDrop(noun);
          }
        case 'LOOK':
        case 'L':
          _look();
        case 'INVENTORY':
        case 'I':
          _doInventory();
        case 'SCORE':
          _doScore();
        case 'SAVE':
          // Save returns JSON state that caller can persist.
          io.writeLine('Game state encoded. Copy the save code:');
          io.writeLine(_saveGame());
        case 'RESTORE':
        case 'LOAD':
          if (noun == null && parts.length <= 1) {
            io.writeLine('Provide save data after RESTORE.');
          } else {
            // Everything after RESTORE is the save data.
            final saveData = trimmed.substring(verb.length).trim();
            _restoreGame(saveData);
          }
        case 'QUIT':
        case 'EXIT':
          _gameOver = true;
          io.writeLine('Thanks for playing! 73 de Adventurer.');
        case 'HELP':
        case '?':
          _doHelp();
        case 'USE':
          if (noun == null) {
            io.writeLine(GameDataStore.sysMessages[11]);
          } else {
            _doUse(noun);
          }
        case 'EXAMINE':
        case 'INSPECT':
        case 'X':
          if (noun == null) {
            io.writeLine('Examine what?');
          } else {
            _doExamine(noun);
          }
        case 'OPEN':
          if (noun == null) {
            io.writeLine('Open what?');
          } else {
            _doOpen(noun);
          }
        case 'CLIMB':
          _doClimb(noun);
        case 'READ':
          if (noun == null) {
            io.writeLine('Read what?');
          } else {
            _doRead(noun);
          }
        case 'TIE':
          if (noun == null) {
            io.writeLine('Tie what?');
          } else {
            _doTie(noun);
          }
        case 'TRANSMIT':
        case 'CQ':
          _doTransmit();
        default:
          io.writeLine('"$verb"${GameDataStore.sysMessages[1]}');
      }
    }

    // Lamp life tick.
    if (_lampLit) {
      _lampLife--;
      if (_lampLife <= 0) {
        _lampLit = false;
        io.writeLine(GameDataStore.sysMessages[19]); // Light has run out!
      } else if (_lampLife < 25 && _lampLife % 5 == 0) {
        io.writeLine(GameDataStore.sysMessages[20]); // growing dim
      }
    }

    return io.flush();
  }

  // ---------------------------------------------------------------------------
  // Direction helpers
  // ---------------------------------------------------------------------------

  int _findDirection(String word) {
    for (int i = 0; i < GameDataStore.directions.length; i++) {
      if (GameDataStore.directions[i] == word ||
          GameDataStore.directionAbbrevs[i] == word) {
        return i;
      }
    }
    return -1;
  }

  // ---------------------------------------------------------------------------
  // Core commands
  // ---------------------------------------------------------------------------

  void _doGo(String direction) {
    // Normalize direction.
    String dir = direction;
    final abbrIdx = GameDataStore.directionAbbrevs.indexOf(dir);
    if (abbrIdx >= 0) {
      dir = GameDataStore.directions[abbrIdx];
    }

    // Special: can't go east from basement unless bunker unlocked.
    if (_currentRoom == 5 && dir == 'EAST' && !_bunkerUnlocked) {
      io.writeLine(
        'The heavy steel door is locked with a rusty padlock.',
      );
      return;
    }

    // Special: can't go to rooftop from antenna farm without ladder.
    if (_currentRoom == 3 && dir == 'UP' && !_ladderPlaced) {
      io.writeLine(
        'The antenna tower is too tall to climb without something to help.',
      );
      return;
    }

    final room = _rooms[_currentRoom];
    final dest = room.exits[dir];
    if (dest != null) {
      _currentRoom = dest;
      io.writeLine(GameDataStore.sysMessages[0]); // OK
      _look();
    } else {
      io.writeLine(GameDataStore.sysMessages[2]); // can't go that direction
    }
  }

  void _doTake(String noun) {
    // Find item in current room matching noun.
    final item = _findItemInRoom(noun);
    if (item == null) {
      io.writeLine("I don't see that here.");
      return;
    }

    // Check padlock special case.
    if (item.word == 'PADLOCK') {
      io.writeLine("It's firmly attached to the door. I can't take it.");
      return;
    }
    if (item.word == 'LADDER') {
      io.writeLine("It's too bulky to carry around.");
      return;
    }

    // Check carry limit.
    final carried =
        _items.where((i) => i.location == GameDataStore.inventory).length;
    if (carried >= GameDataStore.maxCarry) {
      io.writeLine(GameDataStore.sysMessages[8]); // carrying too much
      return;
    }

    item.location = GameDataStore.inventory;
    io.writeLine(GameDataStore.sysMessages[0]); // OK
  }

  void _doDrop(String noun) {
    final item = _findItemInInventory(noun);
    if (item == null) {
      io.writeLine("I'm not carrying that.");
      return;
    }

    item.location = _currentRoom;
    io.writeLine(GameDataStore.sysMessages[0]); // OK

    // Check if dropping a treasure in the treasure room.
    if (_currentRoom == GameDataStore.treasureRoom &&
        item.description.startsWith('*')) {
      io.writeLine(
        'The treasure gleams on the pedestal. It belongs here.',
      );
    }
  }

  void _look() {
    final room = _rooms[_currentRoom];
    final desc = room.longDescription ?? room.description;
    io.writeLine('');
    io.writeLine(desc);

    // List items in room.
    final roomItems = _items
        .where(
          (i) => i.location == _currentRoom && i.description != 'nothing',
        )
        .toList();
    if (roomItems.isNotEmpty) {
      io.writeLine('');
      io.write(GameDataStore.sysMessages[4]); // I can see:
      io.writeLine(roomItems.map((i) => i.description).join(', '));
    }

    // Show exits.
    io.writeLine('');
    if (room.exits.isEmpty) {
      io.writeLine('${GameDataStore.sysMessages[5]}none.');
    } else {
      final exits = room.exits.keys.toList();
      // Add special exits.
      if (_currentRoom == 3 && _ladderPlaced && !room.exits.containsKey('UP')) {
        exits.add('UP');
      }
      io.writeLine('${GameDataStore.sysMessages[5]}${exits.join(', ')}');
    }
  }

  void _doInventory() {
    final carried =
        _items.where((i) => i.location == GameDataStore.inventory).toList();
    if (carried.isEmpty) {
      io.writeLine(
        '${GameDataStore.sysMessages[9]}${GameDataStore.sysMessages[12]}',
      );
    } else {
      io.writeLine(
        '${GameDataStore.sysMessages[9]}${carried.map((i) => i.description).join(', ')}',
      );
    }
  }

  void _doScore() {
    final stored = _items
        .where(
          (i) =>
              i.location == GameDataStore.treasureRoom &&
              i.description.startsWith('*'),
        )
        .length;
    final pct =
        (stored * 100.0 / GameDataStore.totalTreasures).floor();
    io.writeLine(
      GameDataStore.sysMessages[13]
          .replaceFirst('{0}', '$stored')
          .replaceFirst('{1}', '$pct'),
    );

    if (stored == GameDataStore.totalTreasures) {
      io.writeLine('');
      io.writeLine(
        'Congratulations! You have collected all the treasures!',
      );
      io.writeLine(
        'You are a true ham radio adventurer! 73 and good DX!',
      );
      _gameOver = true;
    }
  }

  void _doHelp() {
    io.writeLine('Available commands:');
    io.writeLine(
      '  GO/MOVE <direction>  - Move (NORTH/N, SOUTH/S, EAST/E, WEST/W, UP/U, DOWN/D)',
    );
    io.writeLine('  LOOK/L               - Look around');
    io.writeLine('  TAKE/GET <item>      - Pick up an item');
    io.writeLine('  DROP <item>          - Drop an item');
    io.writeLine('  INVENTORY/I          - List carried items');
    io.writeLine('  USE <item>           - Use an item');
    io.writeLine('  EXAMINE/X <item>     - Examine an item');
    io.writeLine('  READ <item>          - Read an item');
    io.writeLine('  OPEN <item>          - Open something');
    io.writeLine('  CLIMB <item>         - Climb something');
    io.writeLine('  TIE <item>           - Tie something');
    io.writeLine('  TRANSMIT/CQ          - Transmit on the radio');
    io.writeLine('  SCORE                - Check your score');
    io.writeLine('  SAVE                 - Save your game');
    io.writeLine('  RESTORE <data>       - Restore a saved game');
    io.writeLine('  QUIT                 - End the game');
    io.writeLine('');
    io.writeLine(
      'Hint: Treasures are marked with *asterisks*. Drop them in the '
      'hidden chamber to score!',
    );
  }

  // ---------------------------------------------------------------------------
  // Puzzle commands
  // ---------------------------------------------------------------------------

  void _doUse(String noun) {
    final item = _findItemInInventory(noun);
    if (item == null) {
      io.writeLine("I'm not carrying that.");
      return;
    }

    switch (item.word) {
      case 'RADIO':
        if (_currentRoom == 7) {
          // Hilltop — transmit!
          _doTransmit();
        } else {
          io.writeLine(
            'You key up the Baofeng. Static hisses from the speaker. '
            'Maybe try from a higher location?',
          );
        }
      case 'IRON':
        if (_currentRoom == 5 && _hasItem('KEY')) {
          // Solder the morse key in the basement.
          io.writeLine(
            'You carefully solder a loose connection on the Morse key. '
            'It clicks with renewed authority!',
          );
        } else {
          io.writeLine(
            'The soldering iron glows hot. Nothing useful to solder here.',
          );
        }
      case 'FLASHLIGHT':
        _lampLit = !_lampLit;
        io.writeLine(
          _lampLit
              ? 'The flashlight clicks on, casting a bright beam.'
              : 'You switch off the flashlight.',
        );
      case 'METER':
        if (_currentRoom == 3 || _currentRoom == 10) {
          io.writeLine(
            'The SWR meter reads 1.2:1 — excellent match! These antennas '
            'are well-tuned.',
          );
        } else {
          io.writeLine(
            'The SWR meter needle sits at zero. No RF to measure here.',
          );
        }
      case 'BATTERY':
        io.writeLine(
          'The battery pack is fully charged and ready to power a radio.',
        );
      case 'KEY':
        if (_currentRoom == 8) {
          io.writeLine(
            'You tap out CQ CQ CQ on the Morse key using the bunker\'s '
            'military radio. A faint reply comes back: ".. - .-- --- .-. -.- ..."',
          );
        } else {
          io.writeLine('Dit-dah-dit... The Morse key clicks satisfyingly.');
        }
      default:
        io.writeLine("I'm not sure how to use that here.");
    }
  }

  void _doExamine(String noun) {
    // Check inventory first, then room.
    final item = _findItemInInventory(noun) ?? _findItemInRoom(noun);
    if (item == null) {
      io.writeLine("I don't see that.");
      return;
    }

    switch (item.word) {
      case 'RADIO':
        io.writeLine(
          'A well-worn Baofeng UV-5R. The frequency display reads 146.520 MHz. '
          'It has seen many field days.',
        );
      case 'COAX':
        io.writeLine(
          'RG-213 coaxial cable with PL-259 connectors on each end. '
          'About 50 feet long. Low loss at VHF frequencies.',
        );
      case 'METER':
        io.writeLine(
          'A cross-needle SWR/power meter. It can measure forward and '
          'reflected power simultaneously.',
        );
      case 'KEY':
        io.writeLine(
          'A beautiful brass straight key, probably from the 1940s. '
          'The contacts look a bit corroded but it still works.',
        );
      case 'CARD':
        io.writeLine(
          'A QSL card confirming a contact with 3Y0X on Bouvet Island — '
          'one of the rarest DXCC entities! It\'s worth a fortune to '
          'any DXer.',
        );
      case 'BOOK':
        io.writeLine(
          'The ARRL Antenna Handbook, 24th edition. A thick volume full '
          'of antenna designs, theory, and construction details.',
        );
      case 'BATTERY':
        io.writeLine(
          'A 12V lithium iron phosphate battery pack. The label says '
          '"100Ah" — enough to run a field station for days.',
        );
      case 'CRYSTAL':
        io.writeLine(
          'A precision quartz crystal oscillator in a military-grade '
          'hermetic package. Marked "Signal Corps SCR-300 1944". '
          'Extremely rare and valuable!',
        );
      case 'FLASHLIGHT':
        io.writeLine(
          'A sturdy LED flashlight. '
          '${_lampLit ? "It is currently ON." : "It is currently OFF."} '
          'Battery: ${_lampLife > 150 ? "full" : _lampLife > 50 ? "medium" : "low"}.',
        );
      case 'PADLOCK':
        io.writeLine(
          'A rusty padlock securing the heavy steel door. It looks old '
          'and corroded. Maybe it could be opened somehow?',
        );
      case 'IRON':
        io.writeLine(
          'A temperature-controlled soldering station. The tip glows '
          'orange. Perfect for radio repair work.',
        );
      case 'MICROPHONE':
        io.writeLine(
          'A stunning golden microphone with "CQ DX de W1AW" engraved '
          'on the base. This is a legendary piece of ham radio history!',
        );
      case 'WIRE':
        io.writeLine(
          'A 100-foot coil of #14 copper antenna wire. Strong enough '
          'to support itself as a dipole or be used for other purposes.',
        );
      case 'LADDER':
        io.writeLine(
          'A makeshift ladder made from antenna wire, tied to the tower.',
        );
      default:
        io.writeLine('Nothing special about it.');
    }
  }

  void _doOpen(String noun) {
    if (_matchWord(noun, 'PADLOCK') || _matchWord(noun, 'DOOR')) {
      if (_currentRoom != 5) {
        io.writeLine("I don't see that here.");
        return;
      }
      if (_bunkerUnlocked) {
        io.writeLine('The door is already open.');
        return;
      }
      if (_hasItem('IRON')) {
        _bunkerUnlocked = true;
        // Remove padlock from game.
        final padlock = _items.firstWhere((i) => i.word == 'PADLOCK');
        padlock.location = GameDataStore.store;
        io.writeLine(
          'You heat the rusty padlock with the soldering iron. The old '
          'metal expands and the corroded mechanism pops open with a '
          'satisfying click! The steel door swings open.',
        );
      } else {
        io.writeLine(
          'The padlock is rusted shut. I need something hot to expand '
          'the metal...',
        );
      }
    } else {
      io.writeLine("I can't open that.");
    }
  }

  void _doClimb(String? noun) {
    if (_currentRoom == 3) {
      if (_ladderPlaced) {
        _currentRoom = 10;
        io.writeLine('You climb the makeshift ladder up the antenna tower.');
        _look();
      } else {
        io.writeLine(
          'The antenna tower is too tall and smooth to climb without help.',
        );
      }
    } else if (_currentRoom == 10) {
      _currentRoom = 3;
      io.writeLine('You carefully climb back down.');
      _look();
    } else {
      io.writeLine("There's nothing to climb here.");
    }
  }

  void _doRead(String noun) {
    if (_matchWord(noun, 'BOOK')) {
      final item = _findItemInInventory('BOOK') ?? _findItemInRoom('BOOK');
      if (item == null) {
        io.writeLine("I don't see that.");
        return;
      }
      io.writeLine(
        'You flip through the Antenna Handbook. One page is dog-eared: '
        '"For emergency antenna deployment, antenna wire can be tied '
        'to any support structure to create a quick vertical antenna '
        'or climbing aid."',
      );
    } else if (_matchWord(noun, 'CARD')) {
      final item = _findItemInInventory('CARD') ?? _findItemInRoom('CARD');
      if (item == null) {
        io.writeLine("I don't see that.");
        return;
      }
      io.writeLine(
        'The QSL card reads: "Confirming QSO with you on 14.195 MHz, '
        '59 both ways. 73, 3Y0X Bouvet Island DXpedition."',
      );
    } else {
      io.writeLine("There's nothing useful to read on that.");
    }
  }

  void _doTie(String noun) {
    if (_matchWord(noun, 'WIRE')) {
      if (_currentRoom != 3) {
        io.writeLine("There's nothing useful to tie the wire to here.");
        return;
      }
      if (!_hasItem('WIRE')) {
        io.writeLine("I'm not carrying any wire.");
        return;
      }
      if (_ladderPlaced) {
        io.writeLine('A wire ladder is already tied to the tower.');
        return;
      }

      _ladderPlaced = true;
      // Move wire to store and place ladder.
      final wire = _items.firstWhere((i) => i.word == 'WIRE');
      wire.location = GameDataStore.store;
      final ladder = _items.firstWhere((i) => i.word == 'LADDER');
      ladder.location = 3;

      // Add UP exit to antenna farm -> rooftop.
      _rooms[3] = Room(
        description: _rooms[3].description,
        exits: {..._rooms[3].exits, 'UP': 10},
        longDescription:
            '${_rooms[3].longDescription} A makeshift wire ladder '
            'leads UP the antenna tower.',
      );

      io.writeLine(
        'You tie the antenna wire to the tower rungs, creating a '
        'makeshift ladder. You can now climb UP!',
      );
    } else {
      io.writeLine("I can't tie that to anything useful.");
    }
  }

  void _doTransmit() {
    if (!_hasItem('RADIO')) {
      io.writeLine("I don't have a radio to transmit with!");
      return;
    }

    if (_currentRoom == 7) {
      // Hilltop — special event!
      if (!_crystalRevealed) {
        _crystalRevealed = true;
        // Reveal crystal in bunker.
        final crystal = _items.firstWhere((i) => i.word == 'CRYSTAL');
        crystal.location = 8;
        io.writeLine(
          'From the hilltop, you key up: "CQ CQ CQ, this is a test." '
          'Your signal bounces off the distant repeater. A reply comes '
          'back: "Roger, I copy you 5 by 9. Check the bunker — there\'s '
          'something behind the military radios you might have missed!"',
        );
      } else {
        io.writeLine(
          'You transmit CQ from the hilltop. The repeater acknowledges '
          'but no new contacts respond.',
        );
      }
    } else if (_currentRoom == 10) {
      io.writeLine(
        'From the rooftop you transmit with full line-of-sight. Multiple '
        'stations respond! You make several contacts and feel like a true '
        'DXer.',
      );
    } else {
      final responses = [
        'You key up the Baofeng: "CQ CQ CQ." Static. No reply.',
        'You transmit on 146.520. A distant voice crackles back but '
            'fades before you can copy.',
        '"CQ CQ CQ, any station." A brief squelch break, then silence.',
        'You call CQ. Someone keys up and says "QRZ?" but the signal '
            'is too weak to copy.',
      ];
      io.writeLine(responses[_rnd.nextInt(responses.length)]);
    }
  }

  // ---------------------------------------------------------------------------
  // Save / restore
  // ---------------------------------------------------------------------------

  String _saveGame() {
    final state = <String, dynamic>{
      'room': _currentRoom,
      'turns': _turnCounter,
      'lamp': _lampLife,
      'lampLit': _lampLit,
      'bunker': _bunkerUnlocked,
      'ladder': _ladderPlaced,
      'crystal': _crystalRevealed,
      'items': _items.map((i) => i.location).toList(),
    };
    return base64Encode(utf8.encode(jsonEncode(state)));
  }

  void _restoreGame(String data) {
    try {
      final json =
          jsonDecode(utf8.decode(base64Decode(data))) as Map<String, dynamic>;
      _currentRoom = json['room'] as int;
      _turnCounter = json['turns'] as int;
      _lampLife = json['lamp'] as int;
      _lampLit = json['lampLit'] as bool;
      _bunkerUnlocked = json['bunker'] as bool;
      _ladderPlaced = json['ladder'] as bool;
      _crystalRevealed = json['crystal'] as bool;
      final locations = (json['items'] as List<dynamic>).cast<int>();

      // Rebuild rooms and items from scratch, then apply saved locations.
      _rooms = GameDataStore.buildRooms();
      _items = GameDataStore.buildItems();
      for (int i = 0; i < locations.length && i < _items.length; i++) {
        _items[i].location = locations[i];
      }

      // Re-apply ladder room modification if needed.
      if (_ladderPlaced) {
        _rooms[3] = Room(
          description: _rooms[3].description,
          exits: {..._rooms[3].exits, 'UP': 10},
          longDescription:
              '${_rooms[3].longDescription} A makeshift wire ladder '
              'leads UP the antenna tower.',
        );
      }

      _gameOver = false;
      io.writeLine('Game restored.');
      _look();
    } on FormatException {
      io.writeLine('Invalid save data. Could not restore game.');
    } on Object {
      io.writeLine('Failed to restore game. The save data may be corrupted.');
    }
  }

  // ---------------------------------------------------------------------------
  // Item lookup helpers
  // ---------------------------------------------------------------------------

  bool _hasItem(String word) {
    return _items.any(
      (i) => i.word == word && i.location == GameDataStore.inventory,
    );
  }

  Item? _findItemInRoom(String noun) {
    final upper = noun.toUpperCase();
    return _items.cast<Item?>().firstWhere(
          (i) =>
              i != null &&
              i.location == _currentRoom &&
              i.word != null &&
              _matchWord(upper, i.word!),
          orElse: () => null,
        );
  }

  Item? _findItemInInventory(String noun) {
    final upper = noun.toUpperCase();
    return _items.cast<Item?>().firstWhere(
          (i) =>
              i != null &&
              i.location == GameDataStore.inventory &&
              i.word != null &&
              _matchWord(upper, i.word!),
          orElse: () => null,
        );
  }

  bool _matchWord(String input, String word) {
    final upper = input.toUpperCase();
    final target = word.toUpperCase();
    return upper == target || target.startsWith(upper) || upper.startsWith(target);
  }
}
