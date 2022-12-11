import 'dart:async';

import 'package:embedded_commands/embedded_commands.dart';
import 'package:embedded_updater/commands.dart';
import 'package:embedded_updater/fw_file.dart';

class EmbeddedUpdater<T> {
  final Duration rebootTimeout;
  final Duration timeout;
  final EmbeddedCommands<T> commands;
  final EmbeddedUpdaterFwFile fw;
  final Future<bool> Function(Future<T>) isSent;
  bool _disposed = false;

  int currentBlockLen = 0;
  int currentOffset = 0;
  int nBlockRetries = 0;
  bool doneDownloading = false;

  StreamController<EmbeddedUpdaterProgressUpdate> _progressUpdates = StreamController.broadcast();

  EmbeddedUpdaterState state = EmbeddedUpdaterState.rebootingBootloader;
  double downloadProgress = 0;

  late List<StreamSubscription> _subscriptions = [];

  Completer<bool> _actionCompleter = Completer();

  EmbeddedUpdaterError get commError => EmbeddedUpdaterError(state, 'Failed to send command.');

  Stream<EmbeddedUpdaterProgressUpdate> get progessUpdates => _progressUpdates.stream;

  EmbeddedUpdater(
    this.commands,
    this.fw, {
    this.rebootTimeout = const Duration(minutes: 1),
    this.timeout = const Duration(seconds: 10),
    Future<bool> Function(Future<T>)? isSent,
  }) : isSent = isSent ?? _defaultIsSent {
    void complete() {
      if (!_actionCompleter.isCompleted) {
        _actionCompleter.complete(true);
      }
    }

    _subscriptions.add(
      commands.getHandler(EmbeddedUpdaterCommands.status).listen((event) {
        if (event.text == 'BOOTLOADER READY') {
          state = EmbeddedUpdaterState.initiatingUpdate;
          complete();
        }
      }),
    );
    _subscriptions.add(
      commands.getHandler(EmbeddedUpdaterCommands.initiateUpdate).listen((event) {
        state = EmbeddedUpdaterState.waitingForBlock;
        complete();
      }),
    );
    _subscriptions.add(
      commands.getHandler(EmbeddedUpdaterCommands.writeFwBlock).listen((event) async {
        if (event.text == 'OK') {
          if (fw.done) {
            doneDownloading = true;
          } else {
            await fw.nextBlock();
          }
          state = EmbeddedUpdaterState.waitingForBlock;
        } else if (event.text == 'WRITE ERROR') {
          state = EmbeddedUpdaterState.blockError;
        }
        complete();
      }),
    );
    _subscriptions.add(
      commands.getHandler(EmbeddedUpdaterCommands.updateDone).listen((event) {
        if (event.text == 'UPDATE SUCCESSFUL') {
          state = EmbeddedUpdaterState.updateSuccessful;
        } else {
          state = EmbeddedUpdaterState.updateFailed;
        }
        complete();
      }),
    );
  }

  Future<EmbeddedUpdaterError?> update() async {
    while (!_disposed) {
      _progressUpdates.add(EmbeddedUpdaterProgressUpdate(state, downloadProgress));
      switch (state) {
        case EmbeddedUpdaterState.rebootingBootloader:
          _actionCompleter = Completer();
          if (!await isSent(commands.send(EmbeddedUpdaterCommands.rebootIntoBootloader))) {
            return commError;
          }
          if (!await _actionCompleter.future.timeout(rebootTimeout, onTimeout: () => false)) {
            return EmbeddedUpdaterError(state, 'Failed to reboot into bootloader.');
          }
          break;
        case EmbeddedUpdaterState.initiatingUpdate:
          if (!await isSent(commands.send(EmbeddedUpdaterCommands.initiateUpdate))) {
            return commError;
          }
          break;
        case EmbeddedUpdaterState.waitingForBlock:
          _actionCompleter = Completer();
          nBlockRetries = 0;
          if (doneDownloading) {
            if (!await isSent(commands.send(EmbeddedUpdaterCommands.updateDone))) {
              return commError;
            }
          } else {
            EmbeddedUpdaterCommands.writeFwBlock.setExtendedPayload(fw.block);
            if (!await isSent(commands.send(EmbeddedUpdaterCommands.writeFwBlock))) {
              return commError;
            }
            if (!await _actionCompleter.future.timeout(timeout, onTimeout: () => false)) {
              return EmbeddedUpdaterError(state, 'Failed to initiate block write (${fw.blockN}).');
            }
          }
          break;
        case EmbeddedUpdaterState.blockError:
          if (nBlockRetries >= 2) {
            return EmbeddedUpdaterError(state, 'Failed to write block (${fw.blockN}) with $nBlockRetries retries.');
          } else {
            if (!await isSent(commands.send(EmbeddedUpdaterCommands.writeFwBlock))) {
              return commError;
            }
            if (!await _actionCompleter.future.timeout(timeout, onTimeout: () => false)) {
              return EmbeddedUpdaterError(
                state,
                'Failed to initiate block write (${fw.blockN}), already retried $nBlockRetries times.',
              );
            }
            nBlockRetries++;
          }
          break;
        case EmbeddedUpdaterState.updateSuccessful:
          return null;
        case EmbeddedUpdaterState.updateFailed:
          return EmbeddedUpdaterError(state, 'Unknown error.');
      }
    }
  }

  static Future<bool> _defaultIsSent(Future command) async {
    return await command == true;
  }

  void dispose() {
    _disposed = true;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
  }
}

enum EmbeddedUpdaterState {
  rebootingBootloader,
  initiatingUpdate,
  waitingForBlock,
  blockError,
  updateSuccessful,
  updateFailed,
}

class EmbeddedUpdaterError {
  final EmbeddedUpdaterState state;
  final String description;

  const EmbeddedUpdaterError(this.state, this.description);
}

class EmbeddedUpdaterProgressUpdate {
  final EmbeddedUpdaterState state;
  final double downloadProgress;

  const EmbeddedUpdaterProgressUpdate(this.state, [this.downloadProgress = 0]);
}
