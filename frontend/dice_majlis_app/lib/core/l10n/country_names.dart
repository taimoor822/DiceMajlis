import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Country names in the app's language (from the country_picker package).
///
/// The package's own delegate loads asynchronously, which leaves the very
/// first frame blank; its names are plain Dart data, so this one is ready at
/// once.
class CountryNamesDelegate extends LocalizationsDelegate<CountryLocalizations> {
  const CountryNamesDelegate();

  @override
  bool isSupported(Locale locale) =>
      CountryLocalizations.delegate.isSupported(locale);

  @override
  Future<CountryLocalizations> load(Locale locale) =>
      SynchronousFuture(CountryLocalizations(locale));

  @override
  bool shouldReload(CountryNamesDelegate old) => false;
}
