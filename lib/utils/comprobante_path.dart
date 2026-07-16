/// Paths de comprobantes: local (`comprobantes/…`) vs Supabase Storage (`{uuid}/…`).
bool isCloudComprobantePath(String? path) {
  if (path == null || path.isEmpty) return false;
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/',
    caseSensitive: false,
  ).hasMatch(path);
}

bool isLocalComprobantePath(String? path) {
  if (path == null || path.isEmpty) return false;
  return path.startsWith('comprobantes/');
}
