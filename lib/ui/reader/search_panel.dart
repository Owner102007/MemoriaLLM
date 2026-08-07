import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/reading/document_search.dart';
import '../../domain/reading/text_search.dart';

/// Панель поиска по книге.
///
/// Результаты показываются по мере того, как поиск идёт по страницам:
/// на книге в тысячу страниц ждать конца, глядя на крутилку, невыносимо,
/// а нужное обычно находится в первой сотне.
class SearchPanel extends StatefulWidget {
  /// Создаёт панель.
  const SearchPanel({
    required this.search,
    required this.onSelect,
    super.key,
  });

  /// Поиск по книге.
  final DocumentSearch search;

  /// Переход к найденному.
  final void Function(int page) onSelect;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  late final TextEditingController _field = TextEditingController(
    text: widget.search.query,
  );
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.search.removeListener(_onChanged);
    _field.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onQueryChanged(String value) {
    // Пауза перед запуском: иначе каждый набранный символ запускает
    // проход по всей книге, и первые буквы съедают процессор впустую.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(widget.search.start(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DocumentSearch search = widget.search;
    return Drawer(
      key: const Key('search-panel'),
      width: 380,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                key: const Key('search-field'),
                controller: _field,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Поиск по книге',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: const Key('search-clear'),
                    icon: const Icon(Icons.close),
                    tooltip: 'Очистить',
                    onPressed: () {
                      _field.clear();
                      search.clear();
                    },
                  ),
                ),
                onChanged: _onQueryChanged,
                onSubmitted: (String value) {
                  _debounce?.cancel();
                  unawaited(search.start(value));
                },
              ),
            ),
            if (search.isRunning)
              LinearProgressIndicator(
                key: const Key('search-progress'),
                value: search.progress,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _status(search),
                key: const Key('search-status'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _results(context, search)),
          ],
        ),
      ),
    );
  }

  String _status(DocumentSearch search) {
    if (search.query.isEmpty) {
      return 'Введите хотя бы два символа.';
    }
    if (!isSearchableQuery(search.query)) {
      return 'Слишком короткий запрос: нужно хотя бы два символа.';
    }
    if (search.isRunning) {
      return 'Просмотрено страниц: ${search.scannedPages}. '
          'Найдено: ${search.hits.length}.';
    }
    if (search.hits.isEmpty) {
      return 'Ничего не найдено.';
    }
    final String suffix = search.reachedLimit
        ? ' Показаны первые — уточните запрос.'
        : '';
    return 'Найдено совпадений: ${search.hits.length}.$suffix';
  }

  Widget _results(BuildContext context, DocumentSearch search) {
    final ThemeData theme = Theme.of(context);
    final List<SearchHit> hits = search.hits;
    if (hits.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      key: const Key('search-results'),
      itemCount: hits.length,
      itemBuilder: (BuildContext context, int index) {
        final SearchHit hit = hits[index];
        return ListTile(
          key: Key('search-hit-$index'),
          dense: true,
          leading: Text(
            '${hit.pageNumber}',
            style: theme.textTheme.bodySmall,
          ),
          title: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: hit.snippet.substring(0, hit.snippetMatchStart),
                ),
                TextSpan(
                  text: hit.matchedText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                TextSpan(text: hit.snippet.substring(hit.snippetMatchEnd)),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          onTap: () => widget.onSelect(hit.pageNumber),
        );
      },
    );
  }
}
