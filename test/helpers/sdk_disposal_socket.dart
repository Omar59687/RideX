import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A local resource gate; the Supabase client and realtime cleanup stay real.
class DisposalSocket implements WebSocketChannel {
  final entered = Completer<void>();
  final gate = Completer<void>();
  int closeCalls = 0;

  @override
  late final WebSocketSink sink = _DisposalSink(this);
  @override
  Stream<dynamic> get stream => const Stream.empty();
  @override
  Future<void> get ready => Future<void>.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void attach(SupabaseClient client) {
    client.realtime.conn = this;
    client.realtime.connState = SocketStates.open;
  }
}

class _DisposalSink implements WebSocketSink {
  _DisposalSink(this.socket);
  final DisposalSocket socket;

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    socket.closeCalls++;
    if (!socket.entered.isCompleted) socket.entered.complete();
    return socket.gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
