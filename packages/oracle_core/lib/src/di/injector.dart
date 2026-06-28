import 'package:auto_injector/auto_injector.dart';

export 'package:auto_injector/auto_injector.dart';

/// Global dependency-injection container for Oracle AI.
final AutoInjector injector = AutoInjector();

/// A unit of dependency registration.
///
/// Implement [binds] to register a feature's dependencies in the canonical
/// order: Datasource → Repository → UseCases. List dependencies on other
/// modules in [imports]; they are registered (once) before this module.
///
/// ```dart
/// class MemoryModule extends Module {
///   @override
///   void binds(AutoInjector i) {
///     i
///       ..addLazySingleton<MemoryDatasource>(DatabaseMemoryDatasource.new)
///       ..addLazySingleton<MemoryRepository>(MemoryRepositoryImpl.new)
///       ..addLazySingleton<SaveMemoryUsecase>(SaveMemoryUsecaseImpl.new);
///   }
/// }
/// ```
abstract class Module {
  /// Registers this module's dependencies into [i].
  void binds(AutoInjector i);

  /// Other modules this one depends on (registered before this one).
  List<Module> get imports => const [];
}

/// Registers [modules] (with their [Module.imports], de-duplicated) into
/// [target] (defaults to the global [injector]) and commits it.
void registerModules(List<Module> modules, {AutoInjector? target}) {
  final i = target ?? injector;
  final seen = <Type>{};

  void visit(Module module) {
    if (!seen.add(module.runtimeType)) return;
    for (final imported in module.imports) {
      visit(imported);
    }
    module.binds(i);
  }

  for (final module in modules) {
    visit(module);
  }
  i.commit();
}
