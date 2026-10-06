/// Встроенный сценарий теста нагрузки (SNO-F-CLT-02).
///
/// Составной опросник исследования СНО2026: шкала умственного усилия
/// Пааса (Paas, 1992) после каждого блока; в конце сессии — шесть шкал
/// NASA-TLX в варианте Raw (Hart & Staveland, 1988), семь пунктов
/// опросника видов нагрузки Клепш (Klepsch, Schmitz & Seufert, 2017) и
/// три своих пункта об ориентации в источниках. Формулировки — перевод,
/// сделанный для этого теста; откуда что взято и как считается —
/// заметка «Cognitive load test — состав теста» описательной структуры.
///
/// Сценарий записан данными Dart, а не файлом ассетов: в основное
/// приложение, где теста нет, он так не попадает вовсе. Файл с тем же
/// `id` в папке данных приложения подменяет встроенный
/// (`load_test.dart`).
library;

import 'scenario.dart';

const Map<String, Object?> _agree = <String, Object?>{
  'type': kCltScaleType,
  'min': 1,
  'max': 7,
  'step': 1,
  'labels': <String, Object?>{
    '1': 'совершенно неверно',
    '7': 'совершенно верно',
  },
};

const Map<String, Object?> _little = <String, Object?>{
  '0': 'очень мало',
  '100': 'очень много',
};

const Map<String, Object?> _strong = <String, Object?>{
  '0': 'совсем нет',
  '100': 'очень сильно',
};

/// Сценарий `sno-clt-main`, версия 1.
const Map<String, Object?> kBuiltinCltScenario = <String, Object?>{
  'schema': kCltScenarioSchema,
  'id': 'sno-clt-main',
  'version': 1,
  'lang': 'ru',
  'parts': <Object?>[
    <String, Object?>{
      'id': 'A',
      'when': kCltBlockEnd,
      'password': false,
      'items': <Object?>[
        <String, Object?>{
          'id': 'paas.effort',
          'type': kCltScaleType,
          'min': 1,
          'max': 9,
          'step': 1,
          'text': 'Сколько умственных усилий вы вложили в это задание?',
          'labels': <String, Object?>{
            '1': 'очень-очень мало',
            '5': 'ни мало, ни много',
            '9': 'очень-очень много',
          },
        },
      ],
    },
    <String, Object?>{
      'id': 'B',
      'when': kCltSessionEnd,
      'password': true,
      'sections': <Object?>[
        <String, Object?>{
          'id': 'tlx',
          'title': 'Нагрузка',
          'shuffle': false,
          'scale': <String, Object?>{
            'type': kCltScaleType,
            'min': 0,
            'max': 100,
            'step': 5,
          },
          'items': <Object?>[
            <String, Object?>{
              'id': 'tlx.mental',
              'text':
                  'Сколько умственной работы потребовалось — думать, '
                  'искать, вспоминать, решать?',
              'labels': _little,
            },
            <String, Object?>{
              'id': 'tlx.physical',
              'text':
                  'Сколько физических усилий потребовалось — руки, '
                  'глаза, поза?',
              'labels': _little,
            },
            <String, Object?>{
              'id': 'tlx.temporal',
              'text': 'Насколько вы чувствовали спешку и нехватку времени?',
              'labels': _strong,
            },
            <String, Object?>{
              'id': 'tlx.performance',
              'text': 'Насколько успешно, по-вашему, вы справились?',
              'labels': <String, Object?>{'0': 'отлично', '100': 'провал'},
            },
            <String, Object?>{
              'id': 'tlx.effort',
              'text':
                  'Насколько сильно пришлось стараться, чтобы добиться '
                  'такого результата?',
              'labels': <String, Object?>{
                '0': 'очень мало',
                '100': 'очень сильно',
              },
            },
            <String, Object?>{
              'id': 'tlx.frustration',
              'text':
                  'Насколько вы чувствовали раздражение, напряжение, '
                  'неуверенность?',
              'labels': _strong,
            },
          ],
        },
        <String, Object?>{
          'id': 'types',
          'title': 'О задании',
          'shuffle': true,
          'scale': _agree,
          'items': <Object?>[
            <String, Object?>{
              'id': 'icl.1',
              'text':
                  'В этом задании нужно было одновременно держать в '
                  'голове много всего.',
            },
            <String, Object?>{
              'id': 'icl.2',
              'text': 'Это задание было очень сложным.',
            },
            <String, Object?>{
              'id': 'ecl.1',
              'text':
                  'Во время задания было утомительно находить важную '
                  'информацию.',
            },
            <String, Object?>{
              'id': 'ecl.2',
              'text':
                  'То, как было устроено задание, было очень неудобно '
                  'для усвоения материала.',
            },
            <String, Object?>{
              'id': 'ecl.3',
              'text':
                  'Во время задания было трудно распознать главное и '
                  'связать его между собой.',
            },
            <String, Object?>{
              'id': 'gcl.1',
              'text':
                  'Я старался понять не только отдельные детали, но и '
                  'общую картину.',
            },
            <String, Object?>{
              'id': 'gcl.2',
              'text': 'Работая над заданием, я стремился понять всё правильно.',
            },
          ],
        },
        <String, Object?>{
          'id': 'orient',
          'title': 'О книгах на полке',
          'shuffle': false,
          'scale': _agree,
          'items': <Object?>[
            <String, Object?>{
              'id': 'orient.1',
              'text': 'Я быстро находил нужную книгу на полке.',
            },
            <String, Object?>{
              'id': 'orient.2',
              'text':
                  'К концу работы я помнил, где стоят книги, которые '
                  'уже открывал.',
            },
            <String, Object?>{
              'id': 'orient.3',
              'text': 'Без поиска по названию я бы не нашёл нужные книги.',
              'reverse': true,
            },
          ],
        },
      ],
    },
  ],
};
