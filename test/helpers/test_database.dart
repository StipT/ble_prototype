import 'package:ble_prototype/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Counts transactions opened against the database.
class TransactionCounter extends QueryInterceptor {
  /// Transactions started so far.
  int count = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    count++;
    return super.beginTransaction(parent);
  }
}

/// Fresh in-memory database; pass [counter] to observe transactions.
AppDatabase testDatabase({TransactionCounter? counter}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  QueryExecutor executor = NativeDatabase.memory();
  if (counter != null) executor = executor.interceptWith(counter);
  // Synchronous stream teardown keeps widget tests from leaving drift's
  // zero-delay cleanup timers pending.
  return AppDatabase(
    DatabaseConnection(executor, closeStreamsSynchronously: true),
  );
}
