import 'package:intl/intl.dart';

/// Number and date formatting of the RN wallet screen (`en-IN` grouping,
/// `en-US` dates), independent of the app language like RN.
abstract final class WalletFormat {
  static final _oneDecimal = NumberFormat('#,##,##0.0', 'en_IN');
  static final _twoDecimals = NumberFormat('#,##,##0.00', 'en_IN');
  static final _whole = NumberFormat('#,##,##0', 'en_IN');
  static final _date = DateFormat('MMM dd, yyyy', 'en_US');
  static final _time = DateFormat('h:mm a', 'en_US');

  /// RN `formatAmount`: one decimal, lakh grouping (`1,23,456.0`).
  static String amount(num? value) => _oneDecimal.format(_finite(value));

  /// Transaction rows: two decimals, lakh grouping.
  static String amount2(num? value) => _twoDecimals.format(_finite(value));

  /// Preset chips (`₹1,500`).
  static String whole(num value) => _whole.format(value);

  /// Rupees as the gateway shows them: grouped, paise only when there are
  /// any (`1,180`, `352.82`, `1,180.50`).
  static String rupees(num value) {
    final v = num.parse(_finite(value).toStringAsFixed(2));
    return v == v.truncate() ? _whole.format(v) : _twoDecimals.format(v);
  }

  /// RN `toFixed(2)` (no grouping): the add-money GST card.
  static String fixed2(num value) => _finite(value).toStringAsFixed(2);

  /// JS `String(n)`: `12` for whole numbers, else the shortest decimal form.
  static String js(num value) {
    if (!value.isFinite) return '0';
    return value == value.truncate() ? '${value.truncate()}' : '$value';
  }

  /// [js] after rounding to paise: no float noise (`14.700000000000001`).
  static String money(num value) =>
      value.isFinite ? js(num.parse(value.toStringAsFixed(2))) : '0';

  /// `{date, time}` of a transaction in device time, e.g. `Oct 05, 2026` and
  /// `3:04 PM`.
  static ({String date, String time}) dateTime(DateTime at) {
    final local = at.toLocal();
    return (date: _date.format(local), time: _time.format(local));
  }

  static num _finite(num? value) =>
      value == null || !value.isFinite ? 0 : value;
}
