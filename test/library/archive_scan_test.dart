import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/archive_scan.dart';

/// SNO-ALG-LIT-02: что о найденном архиве сказано и в каком порядке
/// архивы стоят в списке.
///
/// Здесь только правила над готовыми записями — ни диска, ни архива.
/// Сам обход проверяется в `archive_scanner_test.dart` на дереве во
/// временной папке.
void main() {
  FoundArchive archive(
    String path, {
    int size = 1024,
    DateTime? modifiedAt,
    int books = 1,
  }) {
    return FoundArchive(
      path: path,
      size: size,
      modifiedAt: modifiedAt ?? DateTime.utc(2026, 10, 4, 12),
      books: books,
    );
  }

  group('SNO-ALG-LIT-02: найденный архив', () {
    test('SNO-ALG-LIT-02: имя — без папок, с любой чертой', () {
      expect(archive('/storage/Download/Книги.zip').name, 'Книги.zip');
      expect(
        archive(r'C:\Users\Paul\Downloads\Литература.zip').name,
        'Литература.zip',
      );
      expect(archive('Литература.zip').name, 'Литература.zip');
    });

    test('SNO-ALG-LIT-02: записи с одним содержимым равны', () {
      expect(archive('/a/x.zip', books: 3), archive('/a/x.zip', books: 3));
      expect(
        archive('/a/x.zip', books: 3),
        isNot(archive('/a/x.zip', books: 4)),
      );
      expect(
        archive('/a/x.zip', books: 3).hashCode,
        archive('/a/x.zip', books: 3).hashCode,
      );
    });

    test('SNO-ALG-LIT-02: поиск основного приложения ничего не ищет', () async {
      expect(await noArchiveSearch(<String>['/device']).toList(), isEmpty);
    });
  });

  group('SNO-ALG-LIT-02: порядок списка', () {
    test('SNO-ALG-LIT-02: новые сверху', () {
      final FoundArchive fresh = archive(
        '/d/Свежий.zip',
        modifiedAt: DateTime.utc(2026, 10, 4),
      );
      final FoundArchive old = archive(
        '/d/Архив.zip',
        modifiedAt: DateTime.utc(2026, 9, 1),
      );
      final List<FoundArchive> list = <FoundArchive>[old, fresh];
      list.sort(compareFoundArchives);
      expect(list, <FoundArchive>[fresh, old]);
    });

    test('SNO-ALG-LIT-02: при одном времени — по имени, без регистра', () {
      final List<FoundArchive> list = <FoundArchive>[
        archive('/d/б.zip'),
        archive('/d/В.zip'),
        archive('/d/А.zip'),
      ];
      list.sort(compareFoundArchives);
      expect(list.map((FoundArchive item) => item.name).toList(), <String>[
        'А.zip',
        'б.zip',
        'В.zip',
      ]);
    });

    test('SNO-ALG-LIT-02: тёзки из разных папок стоят в одном порядке', () {
      final FoundArchive first = archive('/d/a/Книги.zip');
      final FoundArchive second = archive('/d/b/Книги.zip');
      expect(compareFoundArchives(first, second), lessThan(0));
      expect(compareFoundArchives(second, first), greaterThan(0));
      expect(compareFoundArchives(first, first), 0);
    });
  });

  group('SNO-ALG-LIT-02: папки, с которых обход начинает', () {
    test('SNO-ALG-LIT-02: «Загрузки» раньше всего остального', () {
      expect(archiveRootOrder('Download'), lessThan(archiveRootOrder('DCIM')));
      expect(
        archiveRootOrder('Downloads'),
        lessThan(archiveRootOrder('Documents')),
      );
      expect(
        archiveRootOrder('Documents'),
        lessThan(archiveRootOrder('Pictures')),
      );
    });

    test('SNO-ALG-LIT-02: регистр имени не важен', () {
      expect(archiveRootOrder('DOWNLOAD'), archiveRootOrder('download'));
      expect(archiveRootOrder('Telegram'), archiveRootOrder('telegram'));
    });

    test('SNO-ALG-LIT-02: прочие папки равны между собой', () {
      expect(archiveRootOrder('DCIM'), archiveRootOrder('Музыка'));
      expect(archiveRootOrder('DCIM'), kArchiveFirstFolders.length);
    });
  });

  group('SNO-ALG-LIT-02: где лежит архив', () {
    const List<String> phone = <String>['/storage/emulated/0'];

    test('SNO-ALG-LIT-02: папка названа относительно корня обхода', () {
      expect(
        archivePlace('/storage/emulated/0/Download/Литература.zip', phone),
        'Download',
      );
      expect(
        archivePlace('/storage/emulated/0/Download/Telegram/x.zip', phone),
        'Download/Telegram',
      );
    });

    test('SNO-ALG-LIT-02: архив в самом корне', () {
      expect(
        archivePlace('/storage/emulated/0/Литература.zip', phone),
        'в корне памяти',
      );
      // Черта в конце корня ничего не меняет.
      expect(
        archivePlace('/storage/emulated/0/x.zip', <String>[
          '/storage/emulated/0/',
        ]),
        'в корне памяти',
      );
    });

    test('SNO-ALG-LIT-02: пути Windows — с обратной чертой', () {
      const List<String> pc = <String>[r'C:\Users\Paul'];
      expect(
        archivePlace(r'C:\Users\Paul\Downloads\Литература.zip', pc),
        'Downloads',
      );
      expect(
        archivePlace(r'C:\Users\Paul\Desktop\Учёба\Литература.zip', pc),
        'Desktop/Учёба',
      );
    });

    test('SNO-ALG-LIT-02: из двух корней берётся ближайший', () {
      expect(
        archivePlace('/storage/emulated/0/Download/x.zip', <String>[
          '/storage',
          '/storage/emulated/0',
        ]),
        'Download',
      );
    });

    test('SNO-ALG-LIT-02: похожее начало пути — не тот же корень', () {
      expect(
        archivePlace('/device2/Download/x.zip', <String>['/device']),
        '/device2/Download',
      );
    });

    test('SNO-ALG-LIT-02: вне корней папка названа целиком', () {
      expect(archivePlace('/mnt/usb/Книги/x.zip', phone), '/mnt/usb/Книги');
      expect(archivePlace('/mnt/usb/x.zip', const <String>[]), '/mnt/usb');
    });
  });

  group('SNO-ALG-LIT-02: слова о найденном', () {
    test('SNO-ALG-LIT-02: «книга», «книги», «книг»', () {
      expect(describeBookCount(1), '1 книга');
      expect(describeBookCount(2), '2 книги');
      expect(describeBookCount(4), '4 книги');
      expect(describeBookCount(5), '5 книг');
      expect(describeBookCount(11), '11 книг');
      expect(describeBookCount(12), '12 книг');
      expect(describeBookCount(14), '14 книг');
      expect(describeBookCount(21), '21 книга');
      expect(describeBookCount(34), '34 книги');
      expect(describeBookCount(100), '100 книг');
      expect(describeBookCount(111), '111 книг');
      expect(describeBookCount(122), '122 книги');
    });

    test('SNO-ALG-LIT-02: размер — в привычных единицах', () {
      expect(describeFileSize(0), '0 Б');
      expect(describeFileSize(1023), '1023 Б');
      expect(describeFileSize(1024), '1,0 КБ');
      expect(describeFileSize(1536), '1,5 КБ');
      expect(describeFileSize(5 * 1024 * 1024), '5,0 МБ');
      expect(describeFileSize(340 * 1024 * 1024), '340 МБ');
      expect(describeFileSize(2254857830), '2,1 ГБ');
      expect(describeFileSize(6 * 1024 * 1024 * 1024), '6,0 ГБ');
    });

    test('SNO-ALG-LIT-02: округление не даёт «100,0» и «1024 КБ»', () {
      // 99,96 МБ.
      expect(describeFileSize(104815657), '100 МБ');
      // 1023,6 КБ.
      expect(describeFileSize(1048166), '1,0 МБ');
    });

    test('SNO-ALG-LIT-02: строка списка — книги, размер, место', () {
      expect(
        describeFoundArchive(
          archive(
            '/storage/emulated/0/Download/Литература.zip',
            size: 2254857830,
            books: 34,
          ),
          const <String>['/storage/emulated/0'],
        ),
        '34 книги · 2,1 ГБ · Download',
      );
    });
  });
}
