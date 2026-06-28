/// Query filter for listing products.
class ProductFilter {
  final String search;
  final int page;
  final int limit;

  const ProductFilter({this.search = '', this.page = 1, this.limit = 50});

  int get offset => (page - 1) * limit;
}
