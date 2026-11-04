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

/// 바이트를 문자열로 바꾼다. UTF-8 → CP949(EUC-KR) → 깨진 글자 허용 UTF-8 순으로 시도한다.
///
/// 인코딩 실패는 "파일이 없다"는 뜻이 아니므로 절대 예외를 던지지 않는다.
DecodedText decodeText(Uint8List bytes) {
  var data = bytes;
  // UTF-8 BOM(EF BB BF) 제거
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    data = Uint8List.sublistView(data, 3);
  }

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

  return DecodedText(
    utf8.decode(data, allowMalformed: true),
    TextEncoding.utf8Lossy,
  );
}
