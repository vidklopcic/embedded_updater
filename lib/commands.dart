import 'package:embedded_commands/embedded_commands.dart';

abstract class EmbeddedUpdaterCommands {
  static final Command rebootIntoBootloader = Command.write(group: 0xff, id: 0xff);
  static final Command rebootBootloader = Command.write(group: 0, id: 0xff);
  static final Command initiateUpdate = Command.write(group: 0, id: 0, payload: 'UPDATE'.codeUnits);
  static final Command writeFwBlock = Command.extended(group: 0, id: 1);
  static final Command updateDone = Command.write(group: 0, id: 2);
  static final Command bootloaderState = Command.write(group: 0, id: 0xFD);
}
