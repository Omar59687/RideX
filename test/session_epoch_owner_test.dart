import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/services/session_epoch_owner.dart';

void main() {
  late StreamController<DriverAuthEvent> events;
  late SessionEpochOwner owner;
  String? identity;

  setUp(() {
    identity = 'account-a';
    events = StreamController<DriverAuthEvent>.broadcast(sync: true);
    owner = SessionEpochOwner(
        currentIdentity: () => identity, events: events.stream);
  });
  tearDown(() async {
    await owner.dispose();
    await events.close();
  });

  test('startup restoration admits once; refresh preserves the epoch', () {
    final initial = owner.lifecycle;
    expect(initial.isActive, isTrue);
    for (final kind in DriverAuthEventKind.values) {
      if (kind == DriverAuthEventKind.signedOut) continue;
      events.add(DriverAuthEvent(kind, identity));
      expect(owner.lifecycle.epoch, initial.epoch);
      expect(owner.lifecycle.isActive, isTrue);
    }
  });

  for (final kind in DriverAuthEventKind.values) {
    test('late $kind cannot restore a revoked owner', () {
      final before = owner.lifecycle.epoch;
      owner.revoke();
      events.add(DriverAuthEvent(kind, identity));
      expect(owner.lifecycle.isActive, isFalse);
      expect(owner.lifecycle.epoch, greaterThan(before));
    });
  }

  test('same-account reauthentication requires a new current ticket', () {
    final old = owner.beginAuthentication();
    owner.revoke();
    expect(owner.completeAuthentication(old, identity), isFalse);
    final fresh = owner.beginAuthentication();
    expect(fresh, greaterThan(old));
    expect(owner.completeAuthentication(fresh, identity), isTrue);
    expect(owner.lifecycle.isActive, isTrue);
  });

  test('A-B-A cannot reuse a previous epoch or ticket', () {
    final first = owner.lifecycle.epoch;
    final oldTicket = owner.beginAuthentication();
    identity = 'account-b';
    final second = owner.beginAuthentication();
    expect(owner.completeAuthentication(second, identity), isTrue);
    identity = 'account-a';
    events.add(DriverAuthEvent(DriverAuthEventKind.signedIn, identity));
    expect(owner.lifecycle.isActive, isFalse);
    expect(owner.completeAuthentication(oldTicket, identity), isFalse);
    final third = owner.beginAuthentication();
    expect(owner.completeAuthentication(third, identity), isTrue);
    expect(third, greaterThan(second));
    expect(second, greaterThan(first));
  });

  test('unobserved SDK identity change is revoked when ownership is read', () {
    identity = 'account-b';
    expect(owner.lifecycle.isActive, isFalse);
    identity = 'account-a';
    expect(owner.lifecycle.isActive, isFalse);
  });

  test('stream error invalidates pending authentication and ignores raw detail',
      () {
    final ticket = owner.beginAuthentication();
    events.addError(StateError('sensitive-canary'));
    expect(owner.completeAuthentication(ticket, identity), isFalse);
    events.add(DriverAuthEvent(DriverAuthEventKind.signedIn, identity));
    expect(owner.lifecycle.isActive, isFalse);
    final fresh = owner.beginAuthentication();
    expect(owner.completeAuthentication(fresh, identity), isTrue);
  });

  test('stream closure revokes authority', () async {
    await events.close();
    expect(owner.lifecycle.isActive, isFalse);
  });

  test('repeated revoke and disposal remain closed and disposal is idempotent',
      () async {
    final ticket = owner.beginAuthentication();
    owner.revoke();
    owner.revoke();
    final disposal = owner.dispose();
    final epoch = owner.lifecycle.epoch;
    expect(owner.lifecycle.isActive, isFalse);
    expect(owner.dispose(), same(disposal));
    owner.revoke();
    expect(owner.lifecycle.epoch, epoch);
    expect(owner.completeAuthentication(ticket, identity), isFalse);
    expect(owner.completeAuthentication(owner.beginAuthentication(), identity),
        isFalse);
    await disposal;
  });

  test('replacement owner never reuses a previous application epoch', () async {
    final epoch = owner.lifecycle.epoch;
    await owner.dispose();
    owner = SessionEpochOwner(
        currentIdentity: () => identity, events: events.stream);
    expect(owner.lifecycle.epoch, greaterThan(epoch));
  });

  test('missing SDK session cannot complete authentication', () {
    final ticket = owner.beginAuthentication();
    identity = null;
    expect(owner.completeAuthentication(ticket, 'account-a'), isFalse);
    expect(owner.lifecycle.isActive, isFalse);
  });

  for (final revoke in [false, true]) {
    test('expiry suspension permits only same-owner refresh revoked=$revoke',
        () async {
      await owner.dispose();
      var valid = true;
      owner = SessionEpochOwner(
          currentIdentity: () => identity,
          events: events.stream,
          hasValidSession: () => valid);
      final before = owner.lifecycle.epoch;
      valid = false;
      expect(owner.lifecycle.isActive, isFalse);
      expect(owner.lifecycle.epoch, greaterThan(before));
      if (revoke) owner.revoke();
      valid = true;
      expect(owner.lifecycle.isActive, isFalse);
      events.add(DriverAuthEvent(DriverAuthEventKind.tokenRefreshed, identity));
      expect(owner.lifecycle.isActive, !revoke);
    });

    test('delayed expired startup recovery revoked=$revoke', () async {
      await owner.dispose();
      identity = null;
      owner = SessionEpochOwner(
          currentIdentity: () => identity,
          events: events.stream,
          startupIdentity: 'account-a');
      expect(owner.lifecycle.isActive, isFalse);
      events.add(const DriverAuthEvent(
          DriverAuthEventKind.initialSession, 'account-a'));
      if (revoke) owner.revoke();
      identity = 'account-a';
      events.add(DriverAuthEvent(DriverAuthEventKind.tokenRefreshed, identity));
      expect(owner.lifecycle.isActive, !revoke);
    });
  }
}
