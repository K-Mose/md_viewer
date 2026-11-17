import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';

/// 파일을 읽을 때 사용된 문자 인코딩.
enum TextEncoding { utf8, cp949, utf8Lossy }

class DecodedText {
  const DecodedText(this.text, this.encoding);

  final String text;
  final TextEncoding encoding;
}

/// 설정에서 고르는 읽기 인코딩. 자동이 아니면 그 인코딩으로만 읽는다.
enum EncodingPreference { auto, utf8, cp949 }

/// 바이트를 문자열로 바꾼다.
///
/// [preference]가 자동이면 UTF-8 → CP949(EUC-KR) → 깨진 글자 허용 UTF-8 순으로 시도한다.
/// UTF-8이나 CP949로 지정했는데 그 인코딩으로 읽을 수 없으면 깨진 글자를 허용해서 보여준다.
///
/// 인코딩 실패는 "파일이 없다"는 뜻이 아니므로 절대 예외를 던지지 않는다.
DecodedText decodeText(
  Uint8List bytes, {
  EncodingPreference preference = EncodingPreference.auto,
}) {
  var data = bytes;
  // UTF-8 BOM(EF BB BF) 제거
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    data = Uint8List.sublistView(data, 3);
  }

  switch (preference) {
    case EncodingPreference.auto:
      return _decodeAuto(data);
    case EncodingPreference.utf8:
      try {
        return DecodedText(utf8.decode(data), TextEncoding.utf8);
      } on FormatException {
        return _decodeLossy(data);
      }
    case EncodingPreference.cp949:
      try {
        return DecodedText(cp949.decode(data), TextEncoding.cp949);
      } catch (_) {
        return _decodeLossy(data);
      }
  }
}

DecodedText _decodeLossy(Uint8List data) =>
    DecodedText(utf8.decode(data, allowMalformed: true), TextEncoding.utf8Lossy);

DecodedText _decodeAuto(Uint8List data) {
  try {
    return DecodedText(utf8.decode(data), TextEncoding.utf8);
  } on FormatException {
    // UTF-8이 아니면 한글 윈도우 기본 인코딩(CP949, EUC-KR 상위집합)으로 시도
  }

  try {
    return DecodedText(cp949.decode(data), TextEncoding.cp949);
  } catch (_) {
    // CP949로도 안 되면 읽을 수 있는 부분만 보여준다.
  }

  return _decodeLossy(data);
}
