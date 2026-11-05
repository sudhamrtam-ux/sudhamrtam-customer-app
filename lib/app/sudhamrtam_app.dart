import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/customer_shell.dart';
import '../models/cart_manager.dart';
import '../models/milk_subscription_manager.dart';

final CartManager sudhamrtamCart = CartManager();
final MilkSubscriptionManager sudhamrtamMilkSubscriptions =
    MilkSubscriptionManager();

class SudhamrtamApp extends StatelessWidget {
  const SudhamrtamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sudhamrtam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const CustomerShell(),
    );
  }
}
