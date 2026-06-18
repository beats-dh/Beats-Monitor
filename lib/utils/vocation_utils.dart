enum VocationClass {
  sorcerer,
  druid,
  paladin,
  knight,
  monk,
  none,
  unknown,
}

VocationClass vocationClassFor(dynamic vocation) {
  final normalized = _normalizeVocation(vocation);

  switch (normalized) {
    case '1':
    case '5':
    case 'sorcerer':
    case 'master sorcerer':
      return VocationClass.sorcerer;
    case '2':
    case '6':
    case 'druid':
    case 'elder druid':
      return VocationClass.druid;
    case '3':
    case '7':
    case 'paladin':
    case 'royal paladin':
      return VocationClass.paladin;
    case '4':
    case '8':
    case 'knight':
    case 'elite knight':
      return VocationClass.knight;
    case '9':
    case '10':
    case 'monk':
    case 'exalted monk':
      return VocationClass.monk;
    case '0':
    case 'none':
      return VocationClass.none;
  }

  if (normalized.contains('sorcerer')) {
    return VocationClass.sorcerer;
  }
  if (normalized.contains('druid')) {
    return VocationClass.druid;
  }
  if (normalized.contains('paladin')) {
    return VocationClass.paladin;
  }
  if (normalized.contains('knight')) {
    return VocationClass.knight;
  }
  if (normalized.contains('monk')) {
    return VocationClass.monk;
  }

  return VocationClass.unknown;
}

String vocationFilterKeyFor(dynamic vocation) =>
    vocationClassFor(vocation).name;

String _normalizeVocation(dynamic vocation) {
  return (vocation ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
