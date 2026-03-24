/// I/O abstraction for the Adventurer text adventure game.
///
/// The game engine writes output through [GameIO] callbacks, and receives
/// input as strings passed to the game's [processCommand] method.
class GameIO {
  /// Buffer of output lines produced by the game engine since the last
  /// call to [flush].
  final List<String> _buffer = [];

  /// Append a message to the output buffer.
  void write(String message) {
    _buffer.add(message);
  }

  /// Append a message followed by a newline.
  void writeLine(String message) {
    _buffer.add('$message\n');
  }

  /// Return all buffered output as a single string and clear the buffer.
  String flush() {
    final output = _buffer.join();
    _buffer.clear();
    return output;
  }

  /// Whether there is pending output in the buffer.
  bool get hasPendingOutput => _buffer.isNotEmpty;
}
