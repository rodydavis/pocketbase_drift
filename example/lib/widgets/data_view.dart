import 'package:flutter/material.dart';

typedef DataViewRowBuilder<T> = List<DataCell> Function(
  int index,
  T item,
);
typedef DataViewSort<T> = List<T> Function(
  List<T> items,
  int columnIndex,
  bool ascending,
);
typedef DataViewMatch<T> = bool Function(
  String,
  T,
);
typedef DataViewActions<T> = List<Widget> Function(
  List<T> items,
);

class DataView<T> extends StatefulWidget {
  const DataView({
    Key? key,
    required this.items,
    required this.rowBuilder,
    required this.onSort,
    required this.actions,
    required this.match,
    required this.columns,
    required this.onTap,
    this.maxSelect,
    this.searchController,
  }) : super(key: key);

  final List<T> items;
  final DataViewRowBuilder<T> rowBuilder;
  final DataViewSort<T> onSort;
  final DataViewMatch<T> match;
  final DataViewActions<T> actions;
  final List<DataColumn> columns;
  final ValueChanged<T> onTap;
  final int? maxSelect;
  final TextEditingController? searchController;

  @override
  State<DataView<T>> createState() => _DataViewState<T>();
}

class _DataViewState<T> extends State<DataView<T>> {
  late final controller = widget.searchController ?? TextEditingController();
  var tableKey = UniqueKey();
  late DataViewProvider<T> source = DataViewProvider<T>(
    items: widget.items,
    onTap: widget.onTap,
    match: widget.match,
    rowBuilder: widget.rowBuilder,
    onSort: widget.onSort,
    columns: widget.columns,
    maxSelect: widget.maxSelect,
    search: controller,
  );

  @override
  void didUpdateWidget(covariant DataView<T> oldWidget) {
    if (oldWidget.items != widget.items) {
      source = DataViewProvider<T>(
        items: widget.items,
        onTap: widget.onTap,
        match: widget.match,
        rowBuilder: widget.rowBuilder,
        onSort: widget.onSort,
        columns: widget.columns,
        maxSelect: widget.maxSelect,
        search: controller,
      );
      if (mounted) {
        setState(() {
          tableKey = UniqueKey();
        });
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: AnimatedBuilder(
        animation: source,
        builder: (context, child) {
          return PaginatedDataTable(
            header: TextField(
              controller: source.search,
              decoration: InputDecoration(
                hintText: 'Search',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: source.clearSearch,
                ),
              ),
            ),
            actions: widget.actions(source.selected),
            key: tableKey,
            source: source,
            columns: source.columns,
            sortAscending: source.sortAscending,
            sortColumnIndex: source.columnIndex,
            rowsPerPage: source.rowsPerPage,
            onRowsPerPageChanged: (value) => source.rowsPerPage =
                value ?? PaginatedDataTable.defaultRowsPerPage,
          );
        },
      ),
    );
  }
}

class DataViewProvider<T> extends DataTableSource {
  var selected = <T>[];
  final DataViewRowBuilder<T> rowBuilder;
  final DataViewSort<T> onSort;
  final DataViewMatch<T> match;
  final ValueChanged<T> onTap;
  final List<DataColumn> _columns;
  final int? maxSelect;
  final TextEditingController search;

  int _rowsPerPage = PaginatedDataTable.defaultRowsPerPage;
  int get rowsPerPage => _rowsPerPage;
  set rowsPerPage(int value) {
    _rowsPerPage = value;
    notifyListeners();
  }

  void resetSort() {
    columnIndex = 0;
    sortAscending = true;
    sort();
  }

  List<T> _items;
  List<T> get items => _items;
  set items(List<T> value) {
    _items = value;
    sort();
  }

  void sort() {
    _items = onSort(items, columnIndex, sortAscending);
    notifyListeners();
  }

  void clearSearch() {
    search.clear();
    notifyListeners();
  }

  int columnIndex = 0;
  bool sortAscending = true;

  DataViewProvider({
    required this.maxSelect,
    required List<T> items,
    required this.onTap,
    required this.match,
    required this.onSort,
    required this.rowBuilder,
    required List<DataColumn> columns,
    required this.search,
  })  : _columns = columns,
        _items = items {
    search.addListener(notifyListeners);
  }

  @override
  DataRow? getRow(int index) {
    if (index >= filtered.length) return null;
    final item = filtered[index];
    final cells = rowBuilder(index, item);
    return DataRow.byIndex(
      index: index,
      cells: cells,
      selected: selected.contains(item),
      onLongPress: () => onTap(item),
      onSelectChanged: (value) {
        if (value == null) return;
        if (value) {
          if (!selected.contains(item)) {
            if (maxSelect != null) {
              if (selected.length >= maxSelect!) {
                return;
              }
            }
            selected.add(item);
          }
        } else {
          if (selected.contains(item)) {
            selected.remove(item);
          }
        }
        notifyListeners();
      },
    );
  }

  List<T> get filtered => items //
      .where((e) => match(search.text.trim(), e))
      .toList();

  List<DataColumn> get columns => _columns
      .map((e) => DataColumn(
            label: e.label,
            tooltip: e.tooltip,
            numeric: e.numeric,
            onSort: (index, ascending) {
              columnIndex = index;
              sortAscending = ascending;
              sort();
            },
          ))
      .toList();

  List<T> get selectedItems => items //
      .where((e) => selected.contains(e))
      .toList();

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => filtered.length;

  @override
  int get selectedRowCount => selected.length;
}
