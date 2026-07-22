import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:ridex/features/auth/presentation/screens/verify_otp_screen.dart';
import 'package:ridex/features/auth/presentation/widgets/jordan_phone_field.dart';

import 'helpers/test_app.dart';

void main() {
  test('Jordan phone formatting and validation are deterministic', () {
    expect(JordanPhone.normalize('079 123 4567'), '+962791234567');
    expect(JordanPhone.format('+962791234567'), '+962 79 123 4567');
    expect(JordanPhone.validate('+962 79 123 4567'), isNull);
    expect(JordanPhone.validate('+962 76 123 4567'), isNotNull);
  });

  testWidgets('email sign-in keeps the existing credential submit',
      (tester) async {
    final repository = _RecordingAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SignInScreen(backendConfigured: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Email'), findsWidgets);
    expect(find.text('Password'), findsOneWidget);
    final signIn = find.widgetWithText(ElevatedButton, 'Sign in');
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();

    expect(repository.email, 'demo@ridex.app');
    expect(repository.password, '123456');
    expect(repository.role, RideRole.rider);
  });

  testWidgets('production configuration disables phone sign-in',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SignInScreen(backendConfigured: true),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('Phone sign-in is not available'),
      findsOneWidget,
    );
    await tester.tap(find.text('Phone'));
    await tester.pump();
    expect(find.text('Mobile number'), findsNothing);
    expect(find.text('Email'), findsWidgets);
  });

  testWidgets('production OTP route never presents mock verification',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const VerifyOtpScreen(
            phone: '+962791234567',
            backendConfigured: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('482701'), findsNothing);
    expect(
      find.textContaining('not connected to the production backend'),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Verify and continue'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('mock phone OTP signs in as rider with deterministic code',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue to sign in'));
    await tester.tap(find.text('Continue to sign in'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Phone'));
    await tester.tap(find.text('Phone'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '0791234567');
    await tester.ensureVisible(find.text('Continue with phone'));
    await tester.tap(find.text('Continue with phone'));
    await tester.pumpAndSettle();

    expect(find.text('Verify your number'), findsOneWidget);
    expect(find.text('482701'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '482701');
    await tester.ensureVisible(find.text('Verify and continue'));
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Ahmed'), findsOneWidget);
  });
}

class _RecordingAuthRepository extends MockAuthRepository {
  String? email;
  String? password;
  RideRole? role;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    RideRole? role,
  }) async {
    this.email = email;
    this.password = password;
    this.role = role;
    return super.signIn(email: email, password: password, role: role);
  }
}
