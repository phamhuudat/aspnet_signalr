/// Small helpers to read loosely typed JSON produced by the server.
double? readDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

int? readInt(Object? v) => switch (v) {
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

bool readFlag(Object? v) => switch (v) {
      bool b => b,
      num n => n != 0,
      String s => s == '1' || s.toLowerCase() == 'true',
      _ => false,
    };

String? readString(Object? v) => v?.toString();

Map<String, dynamic>? readMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : null;
