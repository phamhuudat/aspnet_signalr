import 'package:aspnet_signalr/aspnet_signalr.dart';
import 'package:aspnet_signalr/src/domain/entities/proxy_config_validation.dart';
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

  group('validation', () {
    String? problem(
            {String? user,
            String? pass,
            String host = 'p.example.com',
            int port = 8080}) =>
        proxyConfigProblem(ProxyConfig(
            host: host, port: port, username: user, password: pass));

    test('valid credentials, including special characters', () {
      expect(problem(), isNull);
      expect(problem(user: 'user', pass: 'secret'), isNull);
      expect(problem(user: 'user', pass: 'p@ss:w0rd!#%&'), isNull);
      expect(problem(user: r'DOMAIN\user', pass: ''), isNull);
      expect(problem(user: 'me@example.com', pass: 'x'), isNull);
    });

    test('values dart:io would corrupt are rejected', () {
      expect(problem(user: 'user', pass: 'a;b'), contains(';'));
      expect(problem(user: 'a:b', pass: 'x'), contains(':'));
      expect(problem(user: 'a;b', pass: 'x'), contains(';'));
      expect(problem(user: '', pass: 'x'), contains('empty'));
      expect(problem(user: ' user', pass: 'x'), contains('whitespace'));
      expect(problem(user: 'user', pass: 'secret '), contains('whitespace'));
      expect(problem(pass: 'x'), contains('username'));
      expect(problem(host: 'a;b'), contains('host'));
      expect(problem(port: 0), contains('port'));
    });

    test('the password is never part of the message', () {
      expect(problem(user: 'user', pass: 'top;secret'), isNot(contains('top')));
    });

    test('custom and environment configs are not validated', () {
      expect(proxyConfigProblem(ProxyConfig.custom((_) => 'DIRECT')), isNull);
      expect(proxyConfigProblem(const ProxyConfig.fromEnvironment()), isNull);
    });
  });
}
