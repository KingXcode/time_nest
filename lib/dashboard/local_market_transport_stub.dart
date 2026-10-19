Future<Map<String, dynamic>> requestLocalMarket(
  String indexId, {
  bool refresh = false,
}) => Future.error(
  UnsupportedError('Local market transport requires the localhost Web build.'),
);
