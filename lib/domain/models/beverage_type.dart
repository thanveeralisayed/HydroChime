enum BeverageType {
  water(multiplier: 1.0, displayName: 'Spring Water'),
  electrolytes(multiplier: 1.45, displayName: 'Cellular Electrolytes'),
  herbalTea(multiplier: 1.0, displayName: 'Herbal Tea'),
  coffee(multiplier: 0.8, displayName: 'Coffee & Black Tea');

  final double multiplier;
  final String displayName;

  const BeverageType({
    required this.multiplier,
    required this.displayName,
  });
}

