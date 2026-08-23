import 'dart:ffi';

/// Три системных вызова, которыми читается книга по файловому дескриптору.
///
/// Дескриптор приходит с Android от `openFileDescriptor`: настоящего пути
/// к документу у приложения нет, а дескриптор есть — и это обычный
/// дескриптор, с которым работает libc. Тем же приёмом открывают
/// `content://` нативные просмотрщики на PDFium.
///
/// Все три функции ищутся **лениво**: на Windows `DynamicLibrary.process()`
/// недоступен вовсе, а чтение по дескриптору там и не нужно — файл
/// открывается по обычному пути. На Linux (сборка тестов) и на Android
/// это одна и та же libc, поэтому корпус-тест гоняет ровно тот код,
/// который поедет на телефон.

/// Читает с позиции, не двигая позицию дескриптора.
typedef PositionalRead =
    int Function(int fd, Pointer<Uint8> buffer, int count, int offset);

/// Читает подряд, двигая позицию дескриптора.
typedef SequentialRead =
    int Function(int fd, Pointer<Uint8> buffer, int count);

/// `pread` — чтение с указанной позиции.
///
/// Именно он, а не `read`, потому что PDF читается перескоками: позиция
/// дескриптора при этом не двигается, и один дескриптор выдерживает
/// нескольких читателей.
late final PositionalRead positionalRead = _lookup<PositionalRead>(
  // `pread64` берёт 64-битное смещение на любой разрядности. Обычный
  // `pread` на 32-битном Android получил бы 32-битное, и книга за
  // границей в два гигабайта прочиталась бы не с того места.
  primary: () => DynamicLibrary.process()
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
        int Function(int, Pointer<Uint8>, int, int)
      >('pread64')
      .call,
  fallback: () => DynamicLibrary.process()
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr, IntPtr),
        int Function(int, Pointer<Uint8>, int, int)
      >('pread')
      .call,
);

/// `read` — последовательное чтение.
///
/// Нужен единственному сценарию: провайдер отдал не файл, а трубу, по
/// которой не перескочить. Тогда книга потоково переносится в приложение,
/// а перескоки достаются уже нашей копии.
late final SequentialRead sequentialRead = _lookup<SequentialRead>(
  primary: () => DynamicLibrary.process()
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read')
      .call,
  fallback: () => throw UnsupportedError('read не найден в libc'),
);

late final int Function(int fd, int offset, int whence) _seek =
    _lookup<int Function(int, int, int)>(
      primary: () => DynamicLibrary.process()
          .lookupFunction<
            Int64 Function(Int32, Int64, Int32),
            int Function(int, int, int)
          >('lseek64')
          .call,
      fallback: () => DynamicLibrary.process()
          .lookupFunction<
            IntPtr Function(Int32, IntPtr, Int32),
            int Function(int, int, int)
          >('lseek')
          .call,
    );

/// Можно ли по этому дескриптору перескакивать по файлу.
///
/// Провайдер вправе отдать не файл, а трубу: так поступают облачные
/// хранилища, у которых книги на самом деле нет на устройстве. По трубе
/// PDF не читается в принципе — там нельзя вернуться назад, — и такую
/// книгу честнее скопировать, чем притворяться, что она локальная.
bool descriptorIsSeekable(int descriptor) {
  const int seekSet = 0;
  try {
    return _seek(descriptor, 0, seekSet) >= 0;
  } on Object {
    return false;
  }
}

T _lookup<T>({required T Function() primary, required T Function() fallback}) {
  try {
    return primary();
  } on ArgumentError {
    return fallback();
  }
}
