import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

void main() {
  test('BilibiliProvider exposes the provider-neutral id and canHandle', () {
    final provider = BilibiliProvider();

    expect(provider.providerId, 'bilibili');
    expect(
      provider.canHandle(
        Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
      ),
      isTrue,
    );
    expect(provider.canHandle(Uri.parse('https://example.com/')), isFalse);
  });

  test('anonymous constructor is explicit', () {
    final provider = BilibiliProvider.anonymous();
    expect(provider.providerId, 'bilibili');
  });
}
