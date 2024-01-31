import 'dart:io';
import 'dart:typed_data';

abstract class EmbeddedUpdaterFwFile {
  int blockN = 0;

  double get progress;

  late EmbeddedUpdaterFwBlockHeader header;

  late Uint8List block;

  Future<bool> verifyHash();

  Future nextBlock();

  Future<Uint8List> read(int d);

  bool get done;

  static Future<EmbeddedUpdaterFwFile> fromPath(String path) async {
    final file = await File(path).open();
    final fw = EmbeddedUpdaterFwFileImpl._(file, await file.length());
    await fw.verifyHash();
    await fw.nextBlock();
    return fw;
  }
}

class EmbeddedUpdaterFwBlockHeader {
  final int startOffset;
  final int size;
  final int version;
  final int build;

  EmbeddedUpdaterFwBlockHeader(this.startOffset, this.size, this.version, this.build);
}

class EmbeddedUpdaterFwFileImpl extends EmbeddedUpdaterFwFile {
  static const int kEccBytes = 32;
  static const int kSignatureLen = kEccBytes * 2;
  static const int kHeaderLen = 16;

  final RandomAccessFile _file;
  int size;
  int currentOffset = 0;

  EmbeddedUpdaterFwFileImpl._(this._file, this.size);

  @override
  Future nextBlock() async {
    if (done) return;
    blockN++;
    var blockBuilder = BytesBuilder();
    blockBuilder.add(await read(kSignatureLen));
    final headerBytes = await read(kHeaderLen);
    blockBuilder.add(headerBytes);
    final headerData = ByteData.view(headerBytes.buffer);
    header = EmbeddedUpdaterFwBlockHeader(
      headerData.getUint32(0, Endian.little),
      headerData.getUint32(4, Endian.little),
      headerData.getUint16(8, Endian.little),
      headerData.getUint16(10, Endian.little),
    );
    blockBuilder.add(await read(header.size));
    block = blockBuilder.toBytes();
  }

  @override
  Future<Uint8List> read(int d) async {
    currentOffset = (currentOffset + d).clamp(0, size);
    return await _file.read(d);
  }

  @override
  Future<bool> verifyHash() async {
    return true;
  }

  @override
  bool get done => currentOffset + kEccBytes == size;

  @override
  double get progress => currentOffset / size;
}
