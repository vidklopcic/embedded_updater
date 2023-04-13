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

  int nBlockRetries = 0;
  bool doneDownloading = false;

  StreamController<EmbeddedUpdaterProgressUpdate> _progressUpdates = StreamController.broadcast();

  EmbeddedUpdaterState state = EmbeddedUpdaterState.rebootingBootloader;

  double get downloadProgress => doneDownloading ? 1.0 : fw.progress;

  final List<StreamSubscription> _subscriptions = [];

  Completer<bool> _actionCompleter = Completer();

  EmbeddedUpdaterError get commError => EmbeddedUpdaterError(state, 'Failed to send command.');

  EmbeddedUpdaterError? _error;

  Stream<EmbeddedUpdaterProgressUpdate> get progessUpdates => _progressUpdates.stream;

  EmbeddedUpdater(
    this.commands,
    this.fw, {
    this.rebootTimeout = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 10),
    Future<bool> Function(Future<T>)? isSent,
  }) : isSent = isSent ?? _defaultIsSent {
    void complete() {
      if (!_actionCompleter.isCompleted) {
        _actionCompleter.complete(true);
      }
    }

    _subscriptions.add(
      commands.getHandler(EmbeddedUpdaterCommands.bootloaderState).listen((event) {
        EmbeddedUpdaterState newState = EmbeddedUpdaterState.values[event.payload[0]];
        if (state == newState) {
          return;
        }
        if (state == EmbeddedUpdaterState.rebootingBootloader && newState == EmbeddedUpdaterState.initiatingUpdate) {
          state = EmbeddedUpdaterState.initiatingUpdate;
          complete();
        } else if (state == EmbeddedUpdaterState.initiatingUpdate && newState == EmbeddedUpdaterState.waitingForBlock) {
          state = EmbeddedUpdaterState.waitingForBlock;
          complete();
        } else if (state == EmbeddedUpdaterState.rebootingBootloader) {
          print('wrong device state ($state) - rebooting bootloader');
          commands.send(EmbeddedUpdaterCommands.rebootBootloader);
        } else {
          _error = EmbeddedUpdaterError(state, 'Unexpected bootloader state: $newState');
          dispose();
        }
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
          nBlockRetries = 0;
        } else {
          nBlockRetries++;
          print('write fw block error - ${event.text}');
        }
        complete();
      }),
    );

    _subscriptions.add(
      commands.getHandler(EmbeddedUpdaterCommands.updateDone).listen((event) {
        if (event.text == 'UPDATE SUCCESSFUL') {
          state = EmbeddedUpdaterState.updateSuccessful;
        } else {
          print('1 - update failed');
          state = EmbeddedUpdaterState.updateFailed;
        }
        complete();
      }),
    );
  }

  Future<EmbeddedUpdaterError?> update() async {
    if (state != EmbeddedUpdaterState.rebootingBootloader) {
      return EmbeddedUpdaterError(state, 'Update already initiated!');
    }

    final result = await _update();
    if (result != null && state != EmbeddedUpdaterState.updateFailed) {
      print('2 - update failed $result');
      state = EmbeddedUpdaterState.updateFailed;
      _progressUpdates.add(EmbeddedUpdaterProgressUpdate(state, downloadProgress));
      await Future.delayed(const Duration(milliseconds: 1));
    }
    return result;
  }

  Future<EmbeddedUpdaterError?> _update() async {
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
          _actionCompleter = Completer();
          if (!await isSent(commands.send(EmbeddedUpdaterCommands.initiateUpdate))) {
            return commError;
          }
          if (!await _actionCompleter.future.timeout(rebootTimeout, onTimeout: () => false)) {
            return EmbeddedUpdaterError(state, 'Failed to reboot into bootloader.');
          }
          break;
        case EmbeddedUpdaterState.waitingForBlock:
          _actionCompleter = Completer();
          if (doneDownloading) {
            if (!await isSent(commands.send(EmbeddedUpdaterCommands.updateDone))) {
              return commError;
            }
          } else if (nBlockRetries > 3) {
            return EmbeddedUpdaterError(state, 'Failed to write block (${fw.blockN}) with $nBlockRetries retries.');
          } else {
            EmbeddedUpdaterCommands.writeFwBlock.setExtendedPayload(fw.block);
            if (!await isSent(commands.send(EmbeddedUpdaterCommands.writeFwBlock))) {
              return commError;
            }
            if (!await _actionCompleter.future.timeout(timeout, onTimeout: () => false)) {
              return EmbeddedUpdaterError(
                state,
                'Failed to initiate block write (${fw.blockN}), already retried $nBlockRetries times.',
              );
            }
          }
          break;
        case EmbeddedUpdaterState.updateSuccessful:
          await Future.delayed(const Duration(milliseconds: 1)); // deliver remaining stream events
          return null;
        case EmbeddedUpdaterState.updateFailed:
          return EmbeddedUpdaterError(state, 'Unknown error.');
      }
    }
    return _error;
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
