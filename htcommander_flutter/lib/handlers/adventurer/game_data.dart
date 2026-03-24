/// All game state data for the Adventurer text adventure.
///
/// This is a ham-radio-themed Scott Adams-style adventure game embedded
/// directly in Dart. Rooms, items, connections, and puzzle logic are all
/// defined here.

/// A room in the game world.
class Room {
  final String description;
  final Map<String, int> exits; // direction name -> room index
  final String? longDescription;

  const Room({
    required this.description,
    required this.exits,
    this.longDescription,
  });
}

/// An item that can exist in the world.
class Item {
  final String description;
  final String? word; // noun the player types to interact
  int location; // room index, -1 = inventory, 0 = nowhere/store
  final int originalLocation;

  Item({
    required this.description,
    this.word,
    required this.location,
  }) : originalLocation = location;

  bool get moved => location != originalLocation;

  void reset() {
    location = originalLocation;
  }
}

/// Static game data: rooms, items, puzzles, and messages.
class GameDataStore {
  // Special location constants (matching the Scott Adams convention).
  static const int store = 0; // item removed from game
  static const int inventory = -1; // player carrying

  // Direction names used in commands.
  static const List<String> directions = [
    'NORTH',
    'SOUTH',
    'EAST',
    'WEST',
    'UP',
    'DOWN',
  ];

  static const List<String> directionAbbrevs = [
    'N',
    'S',
    'E',
    'W',
    'U',
    'D',
  ];

  /// Build the list of rooms for a new game.
  static List<Room> buildRooms() {
    return [
      // Room 0: Store / nowhere (items removed from game go here)
      const Room(
        description: 'The Void',
        exits: {},
        longDescription: 'An empty void. You should not be here.',
      ),

      // Room 1: Starting room — the ham shack
      const Room(
        description: 'Ham Radio Shack',
        exits: {'NORTH': 2, 'EAST': 3, 'SOUTH': 5},
        longDescription:
            'You are in a cluttered ham radio shack. Banks of transceivers '
            'line the walls, their LEDs blinking softly in the dim light. '
            'A workbench covered in soldering tools sits in the corner. '
            'A door leads NORTH to the hallway, EAST to the antenna farm, '
            'and SOUTH to the basement stairs.',
      ),

      // Room 2: Hallway
      const Room(
        description: 'Hallway',
        exits: {'SOUTH': 1, 'NORTH': 4, 'WEST': 6},
        longDescription:
            'A narrow hallway with amateur radio QSL cards pinned to '
            'every surface. The shack is to the SOUTH. A front door '
            'leads NORTH outside. A door WEST opens to a storage closet.',
      ),

      // Room 3: Antenna farm
      const Room(
        description: 'Antenna Farm',
        exits: {'WEST': 1, 'NORTH': 7},
        longDescription:
            'You stand among a forest of antenna masts and guy wires. '
            'A massive Yagi beam antenna towers overhead. Coax cables '
            'snake across the ground. The shack is WEST. A path leads '
            'NORTH to the hilltop.',
      ),

      // Room 4: Front yard
      const Room(
        description: 'Front Yard',
        exits: {'SOUTH': 2, 'EAST': 7},
        longDescription:
            'The front yard of the house. A mailbox stands by the road. '
            'You can see antenna towers rising behind the house to the '
            'EAST. The front door leads SOUTH back inside.',
      ),

      // Room 5: Basement
      const Room(
        description: 'Basement Workshop',
        exits: {'UP': 1, 'EAST': 8},
        longDescription:
            'A damp basement workshop. Shelves hold old vacuum tubes, '
            'capacitors, and homebrew radio kits from decades past. '
            'There is a heavy steel door to the EAST. Stairs lead UP '
            'to the shack.',
      ),

      // Room 6: Storage closet
      const Room(
        description: 'Storage Closet',
        exits: {'EAST': 2},
        longDescription:
            'A small closet crammed with boxes of radio parts, old '
            'QST magazines, and tangled lengths of coax cable. '
            'The hallway is EAST.',
      ),

      // Room 7: Hilltop
      const Room(
        description: 'Hilltop',
        exits: {'SOUTH': 3, 'WEST': 4},
        longDescription:
            'You stand on a windswept hilltop with a panoramic view. '
            'From here you can see distant repeater towers on the horizon. '
            'A faint signal crackles from somewhere nearby. The antenna '
            'farm is to the SOUTH, and the front yard is WEST.',
      ),

      // Room 8: Secret bunker
      const Room(
        description: 'Emergency Communications Bunker',
        exits: {'WEST': 5, 'DOWN': 9},
        longDescription:
            'A cold war-era emergency communications bunker. Military '
            'surplus radio equipment lines the walls. A faded civil '
            'defense poster reads "CONELRAD 640/1240". The basement '
            'is WEST. A hatch in the floor leads DOWN.',
      ),

      // Room 9: Hidden treasure room
      const Room(
        description: 'Hidden Chamber',
        exits: {'UP': 8},
        longDescription:
            'A small hidden chamber deep underground. The walls are '
            'lined with copper mesh forming a perfect Faraday cage. '
            'A pedestal stands in the center of the room. '
            'The hatch leads UP.',
      ),

      // Room 10: Rooftop
      const Room(
        description: 'Rooftop',
        exits: {'DOWN': 3},
        longDescription:
            'You are on the roof, balanced on a narrow catwalk between '
            'antenna masts. The view is spectacular. A VHF repeater '
            'input frequency is painted on the tower: 146.520 MHz. '
            'A ladder leads DOWN to the antenna farm.',
      ),
    ];
  }

  /// Build the list of items for a new game.
  static List<Item> buildItems() {
    return [
      // Item 0: placeholder (store)
      Item(description: 'nothing', location: store),

      // Item 1: Handheld radio (HT)
      Item(
        description: 'a Baofeng handheld radio (HT)',
        word: 'RADIO',
        location: 1, // ham shack
      ),

      // Item 2: Coax cable
      Item(
        description: 'a length of RG-213 coax cable',
        word: 'COAX',
        location: 3, // antenna farm
      ),

      // Item 3: SWR meter
      Item(
        description: 'an SWR meter',
        word: 'METER',
        location: 6, // storage closet
      ),

      // Item 4: Morse key
      Item(
        description: 'a vintage brass Morse key',
        word: 'KEY',
        location: 5, // basement
      ),

      // Item 5: QSL card (treasure!)
      Item(
        description: '*a rare DX QSL card from Bouvet Island*',
        word: 'CARD',
        location: 4, // front yard (mailbox)
      ),

      // Item 6: Antenna manual
      Item(
        description: 'an ARRL Antenna Handbook',
        word: 'BOOK',
        location: 2, // hallway
      ),

      // Item 7: Battery pack
      Item(
        description: 'a fully charged battery pack',
        word: 'BATTERY',
        location: 8, // bunker
      ),

      // Item 8: Crystal oscillator (treasure!)
      Item(
        description: '*a rare crystal oscillator marked "WWII Signal Corps"*',
        word: 'CRYSTAL',
        location: 0, // store (hidden, appears via puzzle)
      ),

      // Item 9: Flashlight (light source)
      Item(
        description: 'a flashlight',
        word: 'FLASHLIGHT',
        location: 1, // ham shack
      ),

      // Item 10: Rusty padlock (blocks bunker door)
      Item(
        description: 'a rusty padlock on the steel door',
        word: 'PADLOCK',
        location: 5, // basement (blocks east exit)
      ),

      // Item 11: Soldering iron
      Item(
        description: 'a hot soldering iron',
        word: 'IRON',
        location: 1, // ham shack
      ),

      // Item 12: Golden microphone (treasure!)
      Item(
        description: '*a golden microphone engraved "CQ DX de W1AW"*',
        word: 'MICROPHONE',
        location: 10, // rooftop
      ),

      // Item 13: Rope / antenna wire
      Item(
        description: 'a coil of antenna wire',
        word: 'WIRE',
        location: 7, // hilltop
      ),

      // Item 14: Ladder (appears when wire is used at antenna farm)
      Item(
        description: 'a makeshift ladder leaning against the tower',
        word: 'LADDER',
        location: 0, // store initially
      ),
    ];
  }

  /// System messages used by the game engine.
  static const List<String> sysMessages = [
    'OK', // 0
    ' is a word I don\'t know... sorry!', // 1
    'I can\'t go in that direction.', // 2
    'I\'m in a ', // 3 (room prefix for non-* rooms)
    'I can see: ', // 4
    'Obvious exits: ', // 5
    'Tell me what to do', // 6
    'I don\'t understand.', // 7
    'I\'m carrying too much!', // 8
    'I\'m carrying: ', // 9
    'Give me a direction too!', // 10
    'What?', // 11
    'Nothing', // 12
    'I\'ve stored {0} treasures. On a scale of 0 to 100, that rates {1}.', // 13
    'It\'s beyond my power to do that.', // 14
    'I don\'t understand your command.', // 15
    'I can\'t see. It is too dark!', // 16
    'Dangerous to move in the dark!', // 17
    'I fell down and broke my neck.', // 18
    'Light has run out!', // 19
    'Your light is growing dim.', // 20
  ];

  /// The room index where treasures must be stored to win.
  static const int treasureRoom = 9;

  /// Total number of treasures in the game (items whose description
  /// starts with *).
  static const int totalTreasures = 3;

  /// Maximum items the player can carry.
  static const int maxCarry = 7;

  /// Starting room.
  static const int startRoom = 1;

  /// Light source item index.
  static const int lightSource = 9;

  /// Initial lamp life (turns).
  static const int initialLampLife = 200;

  /// Recognized verbs (beyond directions and built-ins).
  static const List<String> verbs = [
    'GO',
    'TAKE',
    'GET',
    'DROP',
    'LOOK',
    'INVENTORY',
    'I',
    'SCORE',
    'SAVE',
    'RESTORE',
    'QUIT',
    'HELP',
    'USE',
    'EXAMINE',
    'OPEN',
    'CLIMB',
    'READ',
    'TIE',
    'TRANSMIT',
    'CQ',
  ];
}
