import 'package:flutter/material.dart';
import 'package:umami_analytics/umami_analytics.dart';

final umami = UmamiAnalytics(
  websiteId: 'your-website-id',
  endpoint: 'https://your-umami-instance.com/api/send',
  hostname: 'umami-analytics-example',
  queueConfig: UmamiQueueInMemory(maxSize: 100),
  enableEventLogging: true,
);

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umami Analytics Example',
      navigatorObservers: [
        UmamiNavigatorObserver(analytics: umami),
      ],
      routes: {
        '/': (_) => const HomePage(),
        '/about': (_) => const AboutPage(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                umami.trackEvent(
                  name: 'button_clicked',
                  url: '/',
                  data: {'button': 'navigate_about'},
                );
                Navigator.pushNamed(context, '/about');
              },
              child: const Text('Go to About'),
            ),
            ElevatedButton(
              onPressed: () {
                umami.trackEvent(name: 'manual_event', url: '/');
              },
              child: const Text('Track Custom Event'),
            ),
          ],
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(child: Text('About Page')),
    );
  }
}
