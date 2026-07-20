import 'package:intl/intl.dart';

final _currencyFormatter =
    NumberFormat.currency(symbol: 'JOD ', decimalDigits: 2);

String formatMoney(double value) => _currencyFormatter.format(value);
