import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/services/image_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  final win = p.Context(style: p.Style.windows);
  final posix = p.Context(style: p.Style.posix);

  ImageSource? resolve(
    String src, {
    String? base,
    p.Context? ctx,
    Set<String> files = const {},
  }) =>
      resolveImageSource(
        src,
        baseDirectory: base,
        context: ctx ?? win,
        exists: files.contains,
      );

  test('상대 경로는 문서 폴더 기준으로 찾는다', () {
    final r = resolve('images/a.png',
        base: r'C:\docs', files: {r'C:\docs\images\a.png'});
    expect(r?.filePath, r'C:\docs\images\a.png');
  });

  test('./ 와 ../ 를 정리한다', () {
    final r = resolve('../img/a.png',
        base: r'C:\docs\sub', files: {r'C:\docs\img\a.png'});
    expect(r?.filePath, r'C:\docs\img\a.png');
  });

  test('퍼센트 인코딩(공백, 한글)을 풀어서 찾는다', () {
    final r = resolve('my%20img/%EC%82%AC%EC%A7%84.png',
        base: r'C:\docs', files: {r'C:\docs\my img\사진.png'});
    expect(r?.filePath, r'C:\docs\my img\사진.png');
  });

  test('?query 가 붙은 경로는 꼬리표를 떼고 찾는다', () {
    final r = resolve('a.png?raw=1',
        base: r'C:\docs', files: {r'C:\docs\a.png'});
    expect(r?.filePath, r'C:\docs\a.png');
  });

  test('절대 경로와 file:// 를 지원한다', () {
    expect(resolve(r'D:\pics\a.png', files: {r'D:\pics\a.png'})?.filePath,
        r'D:\pics\a.png');
    expect(
        resolve('file:///D:/pics/a.png', files: {r'D:\pics\a.png'})?.filePath,
        r'D:\pics\a.png');
  });

  test('POSIX 경로도 동작한다', () {
    final r = resolve('a/b.png',
        base: '/home/u/docs', ctx: posix, files: {'/home/u/docs/a/b.png'});
    expect(r?.filePath, '/home/u/docs/a/b.png');
  });

  test('http(s)는 네트워크 이미지', () {
    expect(resolve('https://x.com/a.png')?.networkUrl, 'https://x.com/a.png');
  });

  test('data URI(base64)는 메모리 이미지', () {
    final r = resolve('data:image/png;base64,AAEC');
    expect(r?.bytes, [0, 1, 2]);
    expect(resolve('data:image/png,abc'), isNull);
  });

  test('.svg 파일과 SVG data URI는 isSvg로 표시된다', () {
    final r = resolve('d/a.SVG', base: r'C:\docs', files: {r'C:\docs\d\a.SVG'});
    expect(r?.isSvg, isTrue);
    expect(resolve('a.png', base: r'C:\docs', files: {r'C:\docs\a.png'})?.isSvg,
        isFalse);
    expect(resolve('https://x.com/a.svg?x=1')?.isSvg, isTrue);
    final d = resolve('data:image/svg+xml,%3Csvg%2F%3E');
    expect(d?.isSvg, isTrue);
    expect(d?.bytes, isNotEmpty);
  });

  test('폴더를 모르거나 파일이 없으면 null', () {
    expect(resolve('a.png'), isNull);
    expect(resolve('a.png', base: r'C:\docs'), isNull);
    expect(resolve('  '), isNull);
  });
}
