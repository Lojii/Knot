import 'dart:typed_data';

/// Detected file type from magic bytes.
class FileType {
  final String mime;
  final String ext;
  const FileType(this.mime, this.ext);

  @override
  String toString() => '$mime (.$ext)';
}

/// Detect file type by inspecting the first bytes (magic number / file signature).
/// Returns null if no known signature matches.
FileType? detectFileType(Uint8List bytes) {
  if (bytes.length < 2) return null;

  // ── Images ──────────────────────────────────────────────────────────────

  if (_match(bytes, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    // APNG: PNG header + acTL chunk somewhere in header
    if (_containsStr(bytes, 'acTL', limit: 1024)) {
      return const FileType('image/apng', 'apng');
    }
    return const FileType('image/png', 'png');
  }
  if (_match(bytes, [0xFF, 0xD8, 0xFF])) return const FileType('image/jpeg', 'jpg');
  if (_match(bytes, [0x47, 0x49, 0x46, 0x38])) return const FileType('image/gif', 'gif');
  if (_matchStr(bytes, 'RIFF') && bytes.length >= 12 && _matchStr(bytes, 'WEBP', offset: 8)) {
    return const FileType('image/webp', 'webp');
  }

  // JPEG 2000
  if (_match(bytes, [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A])) {
    // Check sub-types at offset 20
    if (bytes.length >= 24) {
      if (_matchStr(bytes, 'jpx ', offset: 20)) return const FileType('image/jpx', 'jpx');
      if (_matchStr(bytes, 'jpm ', offset: 20)) return const FileType('image/jpm', 'jpm');
    }
    return const FileType('image/jp2', 'jp2');
  }
  // JPEG XL
  if (_match(bytes, [0xFF, 0x0A])) return const FileType('image/jxl', 'jxl');
  if (_match(bytes, [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A])) {
    return const FileType('image/jxl', 'jxl');
  }
  // JPEG XS
  if (_match(bytes, [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x53, 0x20, 0x0D, 0x0A, 0x87, 0x0A])) {
    return const FileType('image/jxs', 'jxs');
  }
  // JPEG XR
  if (_match(bytes, [0x49, 0x49, 0xBC, 0x01])) return const FileType('image/jxr', 'jxr');

  // HEIF / HEIC / AVIF (ISO Base Media ftyp-based)
  if (bytes.length >= 12 && _matchStr(bytes, 'ftyp', offset: 4)) {
    final brand = _readStr(bytes, 8, 4);
    if (brand != null) {
      // AVIF
      if (brand == 'avif' || brand == 'avis') return const FileType('image/avif', 'avif');
      // HEIC
      if (brand == 'heic' || brand == 'heix') return const FileType('image/heic', 'heic');
      if (brand == 'hevc' || brand == 'hevx') return const FileType('image/heic-sequence', 'heics');
      // HEIF
      if (brand == 'mif1' || brand == 'heim' || brand == 'heis' || brand == 'avic') {
        return const FileType('image/heif', 'heif');
      }
      if (brand == 'msf1' || brand == 'hevm' || brand == 'hevs' || brand == 'avcs') {
        return const FileType('image/heif-sequence', 'heifs');
      }
      // M4V
      if (brand == 'M4V ' || brand == 'M4VH' || brand == 'M4VP') {
        return const FileType('video/x-m4v', 'm4v');
      }
      // QuickTime
      if (brand == 'qt  ' || brand == 'moov') return const FileType('video/quicktime', 'mov');
      // 3GPP
      if (brand.startsWith('3gp') || brand.startsWith('3gs') ||
          brand.startsWith('3ge') || brand.startsWith('3gg')) {
        return const FileType('video/3gpp', '3gp');
      }
      // 3GPP2
      if (brand.startsWith('3g2') || brand == 'KDDI') {
        return const FileType('video/3gpp2', '3g2');
      }
      // M4A audio
      if (brand == 'M4A ') return const FileType('audio/mp4', 'm4a');
      // MP4 audio sub-types
      if (brand == 'F4A ' || brand == 'F4B ' || brand == 'M4B ' ||
          brand == 'M4P ' || brand == 'NDAS') {
        return const FileType('audio/mp4', 'm4a');
      }
      // Motion JPEG 2000
      if (brand == 'mjp2' || brand == 'mj2s') return const FileType('video/mj2', 'mj2');
      // Generic MP4 (fallback for any ftyp)
      return const FileType('video/mp4', 'mp4');
    }
  }

  if (_match(bytes, [0x00, 0x00, 0x01, 0x00])) return const FileType('image/x-icon', 'ico');
  if (_match(bytes, [0x00, 0x00, 0x02, 0x00])) return const FileType('image/x-icon', 'cur');
  if (_match(bytes, [0x42, 0x4D])) return const FileType('image/bmp', 'bmp');

  // TIFF (check CR2 sub-type first)
  if (_match(bytes, [0x49, 0x49, 0x2A, 0x00]) || _match(bytes, [0x4D, 0x4D, 0x00, 0x2A])) {
    if (bytes.length >= 11 && _match(bytes, [0x43, 0x52], offset: 8)) {
      return const FileType('image/x-canon-cr2', 'cr2');
    }
    return const FileType('image/tiff', 'tif');
  }

  // Photoshop PSD
  if (_matchStr(bytes, '8BPS')) return const FileType('image/vnd.adobe.photoshop', 'psd');
  // AutoCAD DWG
  if (_matchStr(bytes, 'AC10')) return const FileType('image/vnd.dwg', 'dwg');
  // OpenEXR
  if (_match(bytes, [0x76, 0x2F, 0x31, 0x01])) return const FileType('image/x-exr', 'exr');
  // BPG
  if (_match(bytes, [0x42, 0x50, 0x47, 0xFB])) return const FileType('image/bpg', 'bpg');
  // GIMP XCF
  if (_matchStr(bytes, 'gimp xcf')) return const FileType('image/x-xcf', 'xcf');
  // Radiance HDR
  if (_matchStr(bytes, '#?RADIANCE')) return const FileType('image/vnd.radiance', 'hdr');
  // XPM
  if (_matchStr(bytes, '/* XPM */')) return const FileType('image/x-xpixmap', 'xpm');
  // Apple ICNS
  if (_matchStr(bytes, 'icns')) return const FileType('image/x-icns', 'icns');
  // GIMP pattern
  if (bytes.length >= 24 && _matchStr(bytes, 'GPAT', offset: 20)) {
    return const FileType('image/x-gimp-pat', 'pat');
  }
  // GIMP brush
  if (bytes.length >= 24 && _matchStr(bytes, 'GIMP', offset: 20)) {
    return const FileType('image/x-gimp-gbr', 'gbr');
  }
  // FITS
  if (_matchStr(bytes, 'SIMPLE')) return const FileType('image/fits', 'fits');

  // SVG: text-based, detected by content
  if (_matchStr(bytes, '<svg') || _matchStr(bytes, '<?xml') && _containsStr(bytes, '<svg', limit: 512)) {
    return const FileType('image/svg+xml', 'svg');
  }

  // ── Fonts ───────────────────────────────────────────────────────────────

  if (_match(bytes, [0x77, 0x4F, 0x46, 0x46])) return const FileType('font/woff', 'woff');
  if (_match(bytes, [0x77, 0x4F, 0x46, 0x32])) return const FileType('font/woff2', 'woff2');
  if (_matchStr(bytes, 'OTTO')) return const FileType('font/otf', 'otf');
  if (_matchStr(bytes, 'true')) return const FileType('font/ttf', 'ttf');
  // EOT: check at offset 34
  if (bytes.length >= 36 && _match(bytes, [0x4C, 0x50], offset: 34)) {
    return const FileType('application/vnd.ms-fontobject', 'eot');
  }

  // ── Video ───────────────────────────────────────────────────────────────

  // EBML-based: WebM vs Matroska (MKV)
  if (_match(bytes, [0x1A, 0x45, 0xDF, 0xA3])) {
    if (_containsStr(bytes, 'webm', limit: 4096)) {
      return const FileType('video/webm', 'webm');
    }
    if (_containsStr(bytes, 'matroska', limit: 4096)) {
      return const FileType('video/x-matroska', 'mkv');
    }
    return const FileType('video/webm', 'webm'); // fallback for EBML
  }
  // FLV
  if (_match(bytes, [0x46, 0x4C, 0x56, 0x01])) return const FileType('video/x-flv', 'flv');
  // AVI
  if (_matchStr(bytes, 'RIFF') && bytes.length >= 12 && _matchStr(bytes, 'AVI ', offset: 8)) {
    return const FileType('video/x-msvideo', 'avi');
  }
  // ASF / WMV
  if (_match(bytes, [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9])) {
    return const FileType('video/x-ms-asf', 'asf');
  }
  // MPEG
  if (_match(bytes, [0x00, 0x00, 0x01]) && bytes.length >= 4 &&
      bytes[3] >= 0xB0 && bytes[3] <= 0xBF) {
    return const FileType('video/mpeg', 'mpg');
  }
  // QuickTime (alternate signatures: moov / mdat atoms)
  if (bytes.length >= 8 && _matchStr(bytes, 'moov', offset: 4)) {
    return const FileType('video/quicktime', 'mov');
  }
  if (bytes.length >= 8 && _matchStr(bytes, 'mdat', offset: 4)) {
    return const FileType('video/quicktime', 'mov');
  }
  // RealMedia RMVB
  if (_match(bytes, [0x2E, 0x52, 0x4D, 0x46])) return const FileType('application/vnd.rn-realmedia', 'rmvb');

  // ── Audio ───────────────────────────────────────────────────────────────

  if (_matchStr(bytes, 'ID3')) return const FileType('audio/mpeg', 'mp3');
  if (_match(bytes, [0xFF, 0xFB]) || _match(bytes, [0xFF, 0xF3]) ||
      _match(bytes, [0xFF, 0xF2]) || _match(bytes, [0xFF, 0xFA]) ||
      _match(bytes, [0xFF, 0xE2])) {
    return const FileType('audio/mpeg', 'mp3');
  }
  if (_matchStr(bytes, 'OggS')) return const FileType('audio/ogg', 'ogg');
  if (_matchStr(bytes, 'fLaC')) return const FileType('audio/flac', 'flac');
  if (_matchStr(bytes, 'RIFF') && bytes.length >= 12 && _matchStr(bytes, 'WAVE', offset: 8)) {
    return const FileType('audio/wav', 'wav');
  }
  // AIFF
  if (_matchStr(bytes, 'FORM') && bytes.length >= 12 && _matchStr(bytes, 'AIFF', offset: 8)) {
    return const FileType('audio/aiff', 'aiff');
  }
  // QCP
  if (_matchStr(bytes, 'RIFF') && bytes.length >= 12 && _matchStr(bytes, 'QLCM', offset: 8)) {
    return const FileType('audio/qcelp', 'qcp');
  }
  // AAC (ADTS)
  if (_match(bytes, [0xFF, 0xF1]) || _match(bytes, [0xFF, 0xF9])) {
    return const FileType('audio/aac', 'aac');
  }
  // MIDI
  if (_matchStr(bytes, 'MThd')) return const FileType('audio/midi', 'mid');
  // AMR
  if (_matchStr(bytes, '#!AMR')) return const FileType('audio/amr', 'amr');
  // Musepack
  if (_matchStr(bytes, 'MPCK')) return const FileType('audio/musepack', 'mpc');
  // Monkey's Audio (APE)
  if (_matchStr(bytes, 'MAC ')) return const FileType('audio/ape', 'ape');
  // AU / SND
  if (_matchStr(bytes, '.snd')) return const FileType('audio/basic', 'au');
  // Creative Voice File
  if (_matchStr(bytes, 'Creative Voice File')) return const FileType('audio/x-voc', 'voc');
  // M3U playlist
  if (_matchStr(bytes, '#EXTM3U')) return const FileType('audio/x-mpegurl', 'm3u');

  // ── Documents ───────────────────────────────────────────────────────────

  if (_match(bytes, [0x25, 0x50, 0x44, 0x46])) return const FileType('application/pdf', 'pdf');
  // RTF
  if (_matchStr(bytes, '{\\rtf')) return const FileType('application/rtf', 'rtf');
  // PostScript
  if (_matchStr(bytes, '%!PS')) return const FileType('application/postscript', 'ps');

  // MS Compound Document (OLE2): doc / xls / ppt
  if (_match(bytes, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
    // Sub-type detection at offset 512 for legacy Office formats
    if (bytes.length >= 516) {
      if (_match(bytes, [0xEC, 0xA5], offset: 512)) return const FileType('application/msword', 'doc');
      if (_match(bytes, [0x09, 0x08], offset: 512) || _match(bytes, [0xFD, 0xFF], offset: 512)) {
        return const FileType('application/vnd.ms-excel', 'xls');
      }
      if (_match(bytes, [0xA0, 0x46], offset: 512) || _match(bytes, [0x00, 0x6E], offset: 512)) {
        return const FileType('application/vnd.ms-powerpoint', 'ppt');
      }
    }
    return const FileType('application/x-cfb', 'cfb'); // generic OLE2
  }

  // ZIP-based formats (PK signature) - check sub-types before generic zip
  if (_match(bytes, [0x50, 0x4B, 0x03, 0x04])) {
    // EPUB
    if (_matchStr(bytes, 'mimetypeapplication/epub+zip', offset: 30) ||
        (bytes.length >= 58 && _containsStr(bytes, 'application/epub+zip', limit: 100))) {
      return const FileType('application/epub+zip', 'epub');
    }
    // Office Open XML (docx / xlsx / pptx)
    if (bytes.length >= 34) {
      if (_containsStr(bytes, 'word/', limit: 2000)) {
        return const FileType('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx');
      }
      if (_containsStr(bytes, 'xl/', limit: 2000)) {
        return const FileType('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'xlsx');
      }
      if (_containsStr(bytes, 'ppt/', limit: 2000)) {
        return const FileType('application/vnd.openxmlformats-officedocument.presentationml.presentation', 'pptx');
      }
    }
    // OpenDocument formats
    if (bytes.length >= 60 && _matchStr(bytes, 'mimetype', offset: 30)) {
      if (_containsStr(bytes, 'application/vnd.oasis.opendocument.text', limit: 200)) {
        return const FileType('application/vnd.oasis.opendocument.text', 'odt');
      }
      if (_containsStr(bytes, 'application/vnd.oasis.opendocument.spreadsheet', limit: 200)) {
        return const FileType('application/vnd.oasis.opendocument.spreadsheet', 'ods');
      }
      if (_containsStr(bytes, 'application/vnd.oasis.opendocument.presentation', limit: 200)) {
        return const FileType('application/vnd.oasis.opendocument.presentation', 'odp');
      }
    }
    // APK / JAR (Android / Java archive)
    if (_containsStr(bytes, 'AndroidManifest.xml', limit: 20000)) {
      return const FileType('application/vnd.android.package-archive', 'apk');
    }
    // Generic ZIP
    return const FileType('application/zip', 'zip');
  }
  // ZIP empty / spanned
  if (_match(bytes, [0x50, 0x4B, 0x05, 0x06]) || _match(bytes, [0x50, 0x4B, 0x07, 0x08])) {
    return const FileType('application/zip', 'zip');
  }

  // ── Archives / Compressed ───────────────────────────────────────────────

  if (_match(bytes, [0x1F, 0x8B])) return const FileType('application/gzip', 'gz');
  // Bzip2
  if (_matchStr(bytes, 'BZh')) return const FileType('application/x-bzip2', 'bz2');
  // 7-Zip
  if (_match(bytes, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
    return const FileType('application/x-7z-compressed', '7z');
  }
  // XZ
  if (_match(bytes, [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) {
    return const FileType('application/x-xz', 'xz');
  }
  // Zstandard
  if (_match(bytes, [0x28, 0xB5, 0x2F, 0xFD])) return const FileType('application/zstd', 'zst');
  // RAR
  if (_matchStr(bytes, 'Rar!') && bytes.length >= 7 &&
      bytes[4] == 0x1A && bytes[5] == 0x07) {
    return const FileType('application/x-rar-compressed', 'rar');
  }
  // Tar (ustar magic at offset 257)
  if (bytes.length >= 265 && _matchStr(bytes, 'ustar', offset: 257)) {
    return const FileType('application/x-tar', 'tar');
  }
  // Lzip
  if (_matchStr(bytes, 'LZIP')) return const FileType('application/x-lzip', 'lz');
  // Compress (.Z)
  if (_match(bytes, [0x1F, 0xA0]) || _match(bytes, [0x1F, 0x9D])) {
    return const FileType('application/x-compress', 'Z');
  }
  // RPM
  if (_match(bytes, [0xED, 0xAB, 0xEE, 0xDB])) return const FileType('application/x-rpm', 'rpm');
  // Debian package
  if (_matchStr(bytes, '!<arch>') && bytes.length >= 21 &&
      _matchStr(bytes, 'debian-binary', offset: 8)) {
    return const FileType('application/vnd.debian.binary-package', 'deb');
  }
  // AR archive (generic)
  if (_matchStr(bytes, '!<arch>')) return const FileType('application/x-archive', 'ar');
  // CAB
  if (_matchStr(bytes, 'MSCF')) return const FileType('application/vnd.ms-cab-compressed', 'cab');
  // InstallShield CAB
  if (_matchStr(bytes, 'ISc(')) return const FileType('application/x-installshield', 'cab');
  // Xar
  if (_matchStr(bytes, 'xar!')) return const FileType('application/x-xar', 'xar');
  // CPIO
  if (_matchStr(bytes, '070707') || _matchStr(bytes, '070701') || _matchStr(bytes, '070702')) {
    return const FileType('application/x-cpio', 'cpio');
  }
  if (_match(bytes, [0xC7, 0x71])) return const FileType('application/x-cpio', 'cpio');
  // WARC
  if (_matchStr(bytes, 'WARC/')) return const FileType('application/warc', 'warc');
  // Zlib
  if (_match(bytes, [0x78, 0x01]) || _match(bytes, [0x78, 0x9C]) || _match(bytes, [0x78, 0xDA])) {
    return const FileType('application/zlib', 'zlib');
  }
  // CRX (Chrome Extension)
  if (_matchStr(bytes, 'Cr24')) return const FileType('application/x-chrome-extension', 'crx');

  // ── Executables / Binary ────────────────────────────────────────────────

  // Java class file shares 0xCAFEBABE with Mach-O fat binary.
  // Distinguish by checking that bytes 4-5 are 0x00 and bytes 6-7 form a
  // plausible class-file major version (45-70). Fat Mach-O has an arch count
  // at offset 4 which is typically 0x00000002+ in big-endian.
  if (_match(bytes, [0xCA, 0xFE, 0xBA, 0xBE]) && bytes.length >= 8) {
    if (bytes[4] == 0x00 && bytes[5] == 0x00 && bytes[6] == 0x00 && bytes[7] >= 45 && bytes[7] <= 70) {
      return const FileType('application/java-vm', 'class');
    }
    return const FileType('application/x-mach-binary', 'macho');
  }
  // Mach-O (single-arch)
  if (_match(bytes, [0xFE, 0xED, 0xFA, 0xCE]) || _match(bytes, [0xFE, 0xED, 0xFA, 0xCF]) ||
      _match(bytes, [0xCE, 0xFA, 0xED, 0xFE]) || _match(bytes, [0xCF, 0xFA, 0xED, 0xFE])) {
    return const FileType('application/x-mach-binary', 'macho');
  }
  // ELF
  if (_match(bytes, [0x7F, 0x45, 0x4C, 0x46])) {
    // Check ELF type at offset 16
    if (bytes.length >= 18) {
      if (bytes[16] == 0x02 || bytes[17] == 0x02) return const FileType('application/x-executable', 'elf');
      if (bytes[16] == 0x03 || bytes[17] == 0x03) return const FileType('application/x-sharedlib', 'so');
    }
    return const FileType('application/x-executable', 'elf');
  }
  // PE / EXE
  if (_match(bytes, [0x4D, 0x5A])) return const FileType('application/x-msdownload', 'exe');
  // SWF (Flash)
  if ((bytes[0] == 0x43 || bytes[0] == 0x46 || bytes[0] == 0x5A) &&
      bytes[1] == 0x57 && bytes[2] == 0x53) {
    return const FileType('application/x-shockwave-flash', 'swf');
  }

  // ── Database / Structured ───────────────────────────────────────────────

  // SQLite
  if (_matchStr(bytes, 'SQLi')) return const FileType('application/vnd.sqlite3', 'sqlite');
  // DICOM
  if (bytes.length >= 132 && _matchStr(bytes, 'DICM', offset: 128)) {
    return const FileType('application/dicom', 'dcm');
  }
  // Apache Parquet
  if (_matchStr(bytes, 'PAR1')) return const FileType('application/vnd.apache.parquet', 'parquet');
  // BitTorrent
  if (_matchStr(bytes, 'd8:announce')) return const FileType('application/x-bittorrent', 'torrent');

  // ── 3D Models ───────────────────────────────────────────────────────────

  // glTF binary
  if (_matchStr(bytes, 'glTF')) return const FileType('model/gltf-binary', 'glb');

  // ── Web formats ─────────────────────────────────────────────────────────

  if (_match(bytes, [0x00, 0x61, 0x73, 0x6D])) return const FileType('application/wasm', 'wasm');
  // Windows shortcut (LNK)
  if (_match(bytes, [0x4C, 0x00, 0x00, 0x00, 0x01, 0x14, 0x02, 0x00])) {
    return const FileType('application/x-ms-shortcut', 'lnk');
  }
  // NES ROM
  if (_matchStr(bytes, 'NES') && bytes.length >= 4 && bytes[3] == 0x1A) {
    return const FileType('application/x-nes-rom', 'nes');
  }
  // ISO 9660 disc image (at offset 32769)
  if (bytes.length >= 32774 && _matchStr(bytes, 'CD001', offset: 32769)) {
    return const FileType('application/x-iso9660-image', 'iso');
  }
  // CBOR
  if (_match(bytes, [0xD9, 0xD9, 0xF7])) return const FileType('application/cbor', 'cbor');

  // ── Text-based formats ──────────────────────────────────────────────────

  // JSON
  final trimmed = _trimLeadingWhitespace(bytes);
  if (trimmed.isNotEmpty && (trimmed[0] == 0x7B || trimmed[0] == 0x5B)) {
    return const FileType('application/json', 'json');
  }

  // HTML
  if (_matchStr(bytes, '<!DOCTYPE') || _matchStr(bytes, '<html') || _matchStr(bytes, '<!doctype')) {
    return const FileType('text/html', 'html');
  }

  // XML
  if (_matchStr(bytes, '<?xml')) return const FileType('text/xml', 'xml');

  return null;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

bool _match(Uint8List bytes, List<int> signature, {int offset = 0}) {
  if (bytes.length < offset + signature.length) return false;
  for (int i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}

bool _matchStr(Uint8List bytes, String str, {int offset = 0}) {
  if (bytes.length < offset + str.length) return false;
  for (int i = 0; i < str.length; i++) {
    if (bytes[offset + i] != str.codeUnitAt(i)) return false;
  }
  return true;
}

bool _containsStr(Uint8List bytes, String str, {int limit = 0}) {
  final end = limit > 0 ? limit.clamp(0, bytes.length) : bytes.length;
  final target = str.codeUnits;
  for (int i = 0; i <= end - target.length; i++) {
    bool found = true;
    for (int j = 0; j < target.length; j++) {
      if (bytes[i + j] != target[j]) { found = false; break; }
    }
    if (found) return true;
  }
  return false;
}

String? _readStr(Uint8List bytes, int offset, int length) {
  if (bytes.length < offset + length) return null;
  return String.fromCharCodes(bytes, offset, offset + length);
}

Uint8List _trimLeadingWhitespace(Uint8List bytes) {
  int i = 0;
  while (i < bytes.length && (bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D)) {
    i++;
  }
  return i > 0 ? bytes.sublist(i) : bytes;
}
