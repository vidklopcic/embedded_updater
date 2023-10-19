import 'dart:typed_data';

class BootloaderStatusData {
  int hwModel = 0; // uint16_t
  int hwRevision = 0; // uint16_t
  int version = 0; // uint16_t
  int build = 0; // uint16_t
  late EmbeddedUpdaterState state; // uint8_t

  BootloaderStatusData(ByteData data) {
    int pos = 0;
    if (data.lengthInBytes == 1) {
      state = EmbeddedUpdaterState.values[data.getUint8(pos++)];
    } else if (data.lengthInBytes < 9) {
      state = EmbeddedUpdaterState.values[data.getUint8(pos++)];
      hwRevision = data.getUint16(pos, Endian.little);
      pos += 2;
      version = data.getUint16(pos, Endian.little);
      pos += 2;
      build = data.getUint16(pos, Endian.little);
      pos += 2;
    } else {
      hwModel = data.getUint16(pos, Endian.little);
      pos += 2;
      hwRevision = data.getUint16(pos, Endian.little);
      pos += 2;
      version = data.getUint16(pos, Endian.little);
      pos += 2;
      build = data.getUint16(pos, Endian.little);
      pos += 2;
      state = EmbeddedUpdaterState.values[data.getUint8(pos++)];
    }
  }

  @override
  String toString() {
    return 'BootloaderStatusData(hwRevision: $hwRevision, version: $version, build: $build)';
  }
}

enum EmbeddedUpdaterState {
  rebootingBootloader,
  initiatingUpdate,
  waitingForBlock,
  updateSuccessful,
  updateFailed,
}
