import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/features/home/home_screen.dart';
import 'package:merzox/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:merzox/features/onboarding/view/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool onboardingSeen = prefs.getBool("onboarding_completed") ?? false;
  runApp(Merzox(direct: onboardingSeen));
}

class Merzox extends StatelessWidget {
  const Merzox({super.key, required this.direct});

  final bool direct;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (BuildContext context) => OnboardingBloc()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Merzox',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          fontFamily: 'Tajawal',
        ),
        home: direct ? HomeScreen(isGuest: true) : OnboardingScreen(),
      ),
    );
  }
}
