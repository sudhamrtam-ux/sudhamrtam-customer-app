import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF82B440);

    final categories = [
      (Icons.local_drink_outlined, 'Fresh Milk', 'Cow & Buffalo'),
      (Icons.breakfast_dining_outlined, 'Curd', 'Fresh & Natural'),
      (Icons.spa_outlined, 'Raw Honey', 'Pure Sweetness'),
      (Icons.water_drop_outlined, 'Wood-Pressed Oils', 'Traditional Goodness'),
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Welcome to Sudhamrtam',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Pure farm goodness delivered to your doorstep.'),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: green,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pure Goodness, Naturally',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Fresh dairy, natural honey and traditional wood-pressed oils.',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Explore Our Products',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemBuilder: (context, index) {
              final category = categories[index];

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8F0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE1EBCF)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(category.$1, size: 36, color: green),
                    const SizedBox(height: 10),
                    Text(
                      category.$2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category.$3,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Purity • Tradition • Wellness',
              style: TextStyle(color: green, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
