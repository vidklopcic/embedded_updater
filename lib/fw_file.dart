import 'dart:io';
import 'dart:typed_data';

abstract class EmbeddedUpdaterFwFile {
  int blockN = 0;

  late EmbeddedUpdaterFwBlockHeader header;

  late Uint8List block;

  bool verifyHash();

  Future nextBlock();

  Future<Uint8List> read(int d);

  bool get done;

  static Future<EmbeddedUpdaterFwFile> fromPath(String path) async {
    final file = await File(path).open();
    return EmbeddedUpdaterFwFileImpl._(file, await file.length());
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
  static const int kHeaderLen = 12;

  final RandomAccessFile _file;
  int size;
  int currentOffset = 0;

  EmbeddedUpdaterFwFileImpl._(this._file, this.size) {
    nextBlock();
  }

  @override
  Future nextBlock() async {
    if (done) return;
    blockN++;
    var blockBuilder = BytesBuilder();
    final headerBytes = await read(kHeaderLen);
    blockBuilder.add(headerBytes);
    final headerData = ByteData.view(headerBytes.buffer);
    header = EmbeddedUpdaterFwBlockHeader(
      headerData.getUint32(0, Endian.little),
      headerData.getUint32(4, Endian.little),
      headerData.getUint32(8, Endian.little),
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
  bool verifyHash() {
    // TODO: implement verifyHash
    throw UnimplementedError();
  }

  @override
  bool get done => currentOffset == size;
}
