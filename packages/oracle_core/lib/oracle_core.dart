/// Oracle AI core — pure Dart foundation shared by every package.
library;

// Config
export 'src/config/database_config.dart';
export 'src/config/embedding_config.dart';
export 'src/config/env.dart';
export 'src/config/secret_protector.dart';

// Embedding service
export 'src/services/embedding/embedder.dart';
export 'src/services/embedding/embedder_factory.dart';
export 'src/services/embedding/gemini_embedder.dart';
export 'src/services/embedding/http_embedder.dart';
export 'src/services/embedding/local_embedder.dart';

// Database layer
export 'src/database/data_row_type.dart';
export 'src/database/database.dart';
export 'src/database/postgresql/postgresql_database.dart';
export 'src/database/postgresql/postgresql_type_mapper.dart';
export 'src/database/result_database.dart';
export 'src/database/save_point_query.dart';
export 'src/database/sql_statement.dart';
export 'src/database/sql_value.dart';

// Dependency injection (auto_injector + Module facade)
export 'src/di/injector.dart';

// Domain primitives (value objects, result helpers)
export 'src/domain/return_void.dart';
export 'src/domain/value_object/id_vo.dart';
export 'src/domain/value_object/text_vo.dart';
export 'src/domain/value_object/value_object.dart';

// Failures
export 'src/errors/database_failure.dart';
export 'src/errors/system_failure.dart';

// Result pattern, re-exported for the domain/infra layers.
export 'package:result_dart/result_dart.dart';
