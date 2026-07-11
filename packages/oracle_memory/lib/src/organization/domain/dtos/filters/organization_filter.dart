/// Query filter for listing organizations.
class OrganizationFilter {
  final String search;
  final int page;
  final int limit;

  const OrganizationFilter({this.search = '', this.page = 1, this.limit = 50});

  int get offset => (page - 1) * limit;
}
