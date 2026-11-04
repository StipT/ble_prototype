import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/session.dart';
import '../../domain/recording_repository.dart';

/// State of [SessionsCubit].
final class SessionsState extends Equatable {
  /// Creates the state.
  const SessionsState({this.sessions = const [], this.loading = true});

  /// Sessions, newest first.
  final List<SessionSummary> sessions;

  /// Whether the first DB snapshot is still pending.
  final bool loading;

  @override
  List<Object?> get props => [sessions, loading];
}

/// Mirrors the sessions table. A `Cubit` is enough here: there are no
/// events to transform, just one DB stream to follow.
class SessionsCubit extends Cubit<SessionsState> {
  /// Starts watching [repository] immediately.
  SessionsCubit(RecordingRepository repository) : super(const SessionsState()) {
    _subscription = repository.watchSessions().listen(
      (sessions) => emit(SessionsState(sessions: sessions, loading: false)),
      onError: addError,
    );
  }

  late final StreamSubscription<List<SessionSummary>> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
