String friendlyMessage(Object error) {
  var raw = error.toString().replaceFirst('Exception: ', '').trim();
  raw = raw.replaceFirst('ClientException: ', '').trim();
  raw = raw.replaceFirst('FormatException: ', '').trim();
  final lower = raw.toLowerCase();

  if (raw.isEmpty) {
    return 'Ocurrió un problema, pero no recibimos detalle. Intentá de nuevo.';
  }
  if (lower.contains('failed to fetch') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('socketexception') ||
      lower.contains('timeoutexception') ||
      lower.contains('connection refused') ||
      lower.contains('networkerror') ||
      lower.contains('failed host lookup')) {
    return 'No pudimos conectar con el hogar. Revisá internet o la ruta del servidor en Configuración avanzada.';
  }
  if (lower.contains('401') || lower.contains('403') || lower.contains('not authenticated') || lower.contains('invalid token')) {
    return 'La sesión no está activa. Volvé a entrar con tu nombre y PIN.';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return 'No encontramos esa información. Revisá si el hogar, integrante o registro todavía existe.';
  }
  if (lower.contains('422') || lower.contains('field required') || lower.contains('validation error')) {
    return 'Falta completar algún dato o hay un valor con formato incorrecto.';
  }
  if (lower.contains('500') || lower.contains('internal server error')) {
    return 'El servidor tuvo un problema al guardar o consultar. Intentá de nuevo; si se repite, revisá la consola del backend.';
  }
  if (lower.contains('incorrecto') || lower.contains('invalid credentials')) {
    return 'No encontramos ese hogar o el PIN no coincide.';
  }
  if (lower.contains('already exists') || lower.contains('ya existe') || lower.contains('unique constraint')) {
    return 'Eso ya existe. Probá con otro nombre/código o entrá al hogar creado.';
  }
  if (lower.contains('monto válido') || lower.contains('amount')) {
    return 'Ingresá un monto mayor a cero.';
  }
  if (lower.contains('closed') || lower.contains('cerrado')) {
    return 'Ese mes está cerrado. Reabrilo desde Historial si necesitás corregirlo.';
  }
  if (raw.length > 180) {
    return '${raw.substring(0, 177)}...';
  }
  return raw;
}
