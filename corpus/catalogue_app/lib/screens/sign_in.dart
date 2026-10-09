import 'package:flutter/material.dart';

import '../components/app_button.dart';
import '../components/section_header.dart';
import '../components/form_field.dart';
import '../tokens.dart';

enum SignInState { empty, focused, error, submitting }

/// Level 2: a sign-in form in four states. The focused state autofocuses the
/// email field; the test sets the keyboard inset.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.state = SignInState.empty});

  final SignInState state;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.state != SignInState.empty) {
      _email.text = widget.state == SignInState.error ? 'sam@example' : 'sam@example.com';
    }
    if (widget.state == SignInState.error || widget.state == SignInState.submitting) {
      _password.text = 'secret12';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool submitting = widget.state == SignInState.submitting;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SectionHeader('Welcome back'),
            LabeledField(
              key: const ValueKey<String>('email'),
              label: 'Email',
              controller: _email,
              focusNode: _emailFocus,
              autofocus: widget.state == SignInState.focused,
              enabled: !submitting,
              error: widget.state == SignInState.error ? 'Enter a valid email address' : null,
            ),
            LabeledField(
              key: const ValueKey<String>('password'),
              label: 'Password',
              controller: _password,
              obscure: true,
              enabled: !submitting,
            ),
            const SizedBox(height: Space.s),
            AppButton(key: const ValueKey<String>('submit'), label: 'Sign in', loading: submitting),
          ],
        ),
      ),
    );
  }
}
