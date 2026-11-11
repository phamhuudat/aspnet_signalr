import 'package:aspnet_signalr/aspnet_signalr.dart';
import 'package:test/test.dart';

void main() {
  test('fixed proxy with bypass rules', () {
    const p = ProxyConfig(
      host: 'proxy.example.com',
      port: 8080,
      bypass: ['localhost', '*.internal.example.com', '.corp.example.com'],
    );
    expect(p.resolve(Uri.parse('https://a.example.com/x')),
        'PROXY proxy.example.com:8080');
    expect(p.resolve(Uri.parse('http://localhost:1')), 'DIRECT');
    expect(p.resolve(Uri.parse('https://x.internal.example.com')), 'DIRECT');
    expect(p.resolve(Uri.parse('https://internal.example.com')), 'DIRECT');
    expect(p.resolve(Uri.parse('https://a.corp.example.com')), 'DIRECT');
    expect(p.shouldBypass('LOCALHOST'), isTrue);
    expect(p.shouldBypass('other.example.com'), isFalse);
    expect(p.toString(), isNot(contains('secret')));
  });

  test('credentials are embedded for dart:io', () {
    const p = ProxyConfig(
      host: 'proxy.example.com',
      port: 3128,
      username: 'user',
      password: 'secret',
    );
    expect(p.resolve(Uri.parse('https://example.com')),
        'PROXY user:secret@proxy.example.com:3128');
    expect(p.toString(), isNot(contains('secret')));
  });

  test('custom and environment', () {
    final custom = ProxyConfig.custom(
      (uri) => uri.host.startsWith('d.') ? 'PROXY p:1' : 'DIRECT',
    );
    expect(custom.resolve(Uri.parse('https://d.example.com')), 'PROXY p:1');
    expect(custom.resolve(Uri.parse('https://a.example.com')), 'DIRECT');
    const env = ProxyConfig.fromEnvironment(environment: {'http_proxy': 'p:1'});
    expect(env.useEnvironment, isTrue);
    expect(env.resolve(Uri.parse('https://example.com')), isNull);
  });
}
