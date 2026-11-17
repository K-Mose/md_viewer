import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_decoder.dart';

/// 뷰어 줄 간격.
///
/// 마크다운의 "보통"은 지금까지의 기본 모양(라이브러리 기본값)을 그대로 두려고 null이다.
enum LineSpacing {
  tight(markdownHeight: 1.2, plainHeight: 1.35),
  normal(markdownHeight: null, plainHeight: 1.6),
  wide(markdownHeight: 1.8, plainHeight: 1.9);

  const LineSpacing({required this.markdownHeight, required this.plainHeight});

  /// 마크다운 본문 문단의 줄 높이 배수. null이면 기본값을 쓴다.
  final double? markdownHeight;

  /// .txt 원문 보기의 줄 높이 배수.
  final double plainHeight;
}

/// .txt 파일을 어떻게 보여줄지.
enum TxtViewMode { raw, markdown }

/// 앱 설정. shared_preferences에 저장하고, 바뀌면 [notifyListeners]로 알린다.
///
/// 앱 시작 때 [load]를 한 번 부르고, 이후에는 [instance]를 어디서든 읽는다.
/// [load] 전에도 기본값으로 동작한다 (테스트, 저장소 오류).
class AppSettings extends ChangeNotifier {
  AppSettings();

  static final instance = AppSettings();

  static const minTextScale = 0.8;
  static const maxTextScale = 1.6;

  static const _textScaleKey = 'settings.text_scale';
  static const _lineSpacingKey = 'settings.line_spacing';
  static const _rememberPositionKey = 'settings.remember_position';
  static const _encodingKey = 'settings.encoding';
  static const _txtViewModeKey = 'settings.txt_view_mode';
  static const _autoDraftKey = 'settings.auto_draft';

  double _textScale = 1.0;
  LineSpacing _lineSpacing = LineSpacing.normal;
  bool _rememberPosition = true;
  EncodingPreference _encoding = EncodingPreference.auto;
  TxtViewMode _txtViewMode = TxtViewMode.raw;
  bool _autoDraft = true;

  /// 뷰어 글자 크기 배율 (0.8 ~ 1.6, 0.1 단위)
  double get textScale => _textScale;
  LineSpacing get lineSpacing => _lineSpacing;

  /// 문서별로 읽던 위치를 기억할지
  bool get rememberPosition => _rememberPosition;

  /// 파일을 읽을 때 쓸 문자 인코딩 (자동이면 UTF-8 → CP949 순서로 판별)
  EncodingPreference get encoding => _encoding;
  TxtViewMode get txtViewMode => _txtViewMode;

  /// 에디터에서 입력이 멈추면 자동으로 임시저장할지
  bool get autoDraft => _autoDraft;

  /// 저장된 설정을 읽는다. 없거나 읽을 수 없는 값은 기본값을 쓴다.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _textScale = _roundScale(prefs.getDouble(_textScaleKey) ?? 1.0);
      _lineSpacing = _enumByName(
        LineSpacing.values,
        prefs.getString(_lineSpacingKey),
        LineSpacing.normal,
      );
      _rememberPosition = prefs.getBool(_rememberPositionKey) ?? true;
      _encoding = _enumByName(
        EncodingPreference.values,
        prefs.getString(_encodingKey),
        EncodingPreference.auto,
      );
      _txtViewMode = _enumByName(
        TxtViewMode.values,
        prefs.getString(_txtViewModeKey),
        TxtViewMode.raw,
      );
      _autoDraft = prefs.getBool(_autoDraftKey) ?? true;
    } catch (_) {
      // 설정을 못 읽어도 기본값으로 계속 쓸 수 있다.
    }
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    final scale = _roundScale(value);
    if (scale == _textScale) return;
    _textScale = scale;
    notifyListeners();
    await _write((prefs) => prefs.setDouble(_textScaleKey, scale));
  }

  Future<void> setLineSpacing(LineSpacing value) async {
    if (value == _lineSpacing) return;
    _lineSpacing = value;
    notifyListeners();
    await _write((prefs) => prefs.setString(_lineSpacingKey, value.name));
  }

  Future<void> setRememberPosition(bool value) async {
    if (value == _rememberPosition) return;
    _rememberPosition = value;
    notifyListeners();
    await _write((prefs) => prefs.setBool(_rememberPositionKey, value));
  }

  Future<void> setEncoding(EncodingPreference value) async {
    if (value == _encoding) return;
    _encoding = value;
    notifyListeners();
    await _write((prefs) => prefs.setString(_encodingKey, value.name));
  }

  Future<void> setTxtViewMode(TxtViewMode value) async {
    if (value == _txtViewMode) return;
    _txtViewMode = value;
    notifyListeners();
    await _write((prefs) => prefs.setString(_txtViewModeKey, value.name));
  }

  Future<void> setAutoDraft(bool value) async {
    if (value == _autoDraft) return;
    _autoDraft = value;
    notifyListeners();
    await _write((prefs) => prefs.setBool(_autoDraftKey, value));
  }

  /// 저장에 실패해도 이번 실행 동안은 바뀐 값을 그대로 쓴다.
  Future<void> _write(
    Future<bool> Function(SharedPreferences prefs) action,
  ) async {
    try {
      await action(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  /// 0.1 단위로 맞추고 범위 안으로 넣는다 (0.30000000000000004 같은 값 방지).
  static double _roundScale(double value) {
    final clamped = math.max(minTextScale, math.min(maxTextScale, value));
    return (clamped * 10).round() / 10;
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
