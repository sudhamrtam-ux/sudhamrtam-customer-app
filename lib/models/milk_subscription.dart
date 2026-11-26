enum MilkDeliveryFrequency { daily, alternateDays, selectedDays, randomDays }

enum MilkSubscriptionStatus { active, paused, cancelled }

/// Delivery shifts, in delivery order. Early morning milk is the
/// evening before's milk, kept cold overnight; changes to it close
/// at 9 PM the evening before (the server fixes the list then).
enum MilkDeliveryShift {
  earlyMorning,
  morning,
  evening;

  /// The server's name: early_morning, morning, evening.
  String get apiName => this == earlyMorning ? 'early_morning' : name;

  static MilkDeliveryShift fromApi(String value) =>
      value == 'early_morning' ? earlyMorning : values.byName(value);
}

// Each shift has its own quantity and delivery schedule.
class MilkShiftSchedule {
  final MilkDeliveryShift shift;

  // Quantity stored in millilitres.
  // Examples: 500 = 0.5 L, 1000 = 1 L.
  final int quantityMl;

  final MilkDeliveryFrequency frequency;

  // Monday = 1, Sunday = 7.
  final List<int> selectedWeekdays;

  // Individual delivery dates for Random Days.
  final List<DateTime> selectedRandomDates;

  final DateTime startDate;
  final DateTime? endDate;

  const MilkShiftSchedule({
    required this.shift,
    required this.quantityMl,
    required this.frequency,
    this.selectedWeekdays = const [],
    this.selectedRandomDates = const [],
    required this.startDate,
    this.endDate,
  });

  MilkShiftSchedule copyWith({
    MilkDeliveryShift? shift,
    int? quantityMl,
    MilkDeliveryFrequency? frequency,
    List<int>? selectedWeekdays,
    List<DateTime>? selectedRandomDates,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
  }) {
    return MilkShiftSchedule(
      shift: shift ?? this.shift,
      quantityMl: quantityMl ?? this.quantityMl,
      frequency: frequency ?? this.frequency,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      selectedRandomDates: selectedRandomDates ?? this.selectedRandomDates,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
    );
  }
}

class MilkSubscription {
  final String id;
  final String productId;

  // NEW: Independent delivery schedules.
  // A subscription may contain any of Early morning, Morning, Evening.
  final List<MilkShiftSchedule> shiftSchedules;

  // LEGACY FIELDS:
  // Retained temporarily for compatibility with existing
  // setup screens, saved cards, and subscription manager.
  // These will be migrated in later steps.
  final int quantity;
  final MilkDeliveryFrequency frequency;
  final List<int> selectedWeekdays;
  final List<DateTime> selectedRandomDates;
  final DateTime startDate;
  final DateTime? endDate;

  final MilkSubscriptionStatus status;

  /// When the plan was cancelled; null while open (or unknown for
  /// plans cancelled before the phone kept it).
  final DateTime? cancelledAt;

  /// Vacation: a paused plan delivers again from this date (the
  /// server restarts it). Null: paused until the customer resumes.
  final DateTime? resumeOn;

  /// Vacation days (owner decision 2026-11-11): no milk on these
  /// days (date only, sorted); the plan stays active. Any number of
  /// separate days or ranges.
  final List<DateTime> vacationDates;

  /// The server's approval: 'pending' (a new plan waiting for
  /// Sudhamrtam: no milk yet), 'approved' or 'rejected' (cancelled,
  /// with [rejectReason]). Null for plans kept only on the phone.
  final String? approval;
  final String? rejectReason;

  /// Sudhamrtam's note when approving (owner request 2026-11-26), e.g.
  /// why milk starts later than asked.
  final String? approvalNote;

  const MilkSubscription({
    required this.id,
    required this.productId,
    this.shiftSchedules = const [],
    required this.quantity,
    required this.frequency,
    this.selectedWeekdays = const [],
    this.selectedRandomDates = const [],
    required this.startDate,
    this.endDate,
    this.status = MilkSubscriptionStatus.active,
    this.cancelledAt,
    this.resumeOn,
    this.vacationDates = const [],
    this.approval,
    this.rejectReason,
    this.approvalNote,
  });

  /// Vacation days from [today] on.
  List<DateTime> vacationDaysFrom(DateTime today) {
    final from = DateTime(today.year, today.month, today.day);
    return [
      for (final d in vacationDates)
        if (!d.isBefore(from)) d,
    ];
  }

  /// No milk on [day]: one of the vacation days.
  bool isVacationDay(DateTime day) => vacationDates.any(
    (d) => d.year == day.year && d.month == day.month && d.day == day.day,
  );

  /// A new plan Sudhamrtam has not approved yet: no milk comes.
  bool get isWaitingForApproval =>
      approval == 'pending' && status != MilkSubscriptionStatus.cancelled;

  /// Sudhamrtam's approval note, shown until a week after milk starts.
  String? approvalNoteOn(DateTime today) {
    final note = approvalNote?.trim();
    if (note == null || note.isEmpty || approval != 'approved') return null;
    final until = startDate.add(const Duration(days: 7));
    return DateTime(today.year, today.month, today.day).isAfter(until)
        ? null
        : note;
  }

  /// Sudhamrtam did not approve this plan; see [rejectReason].
  bool get isRejected => approval == 'rejected';

  /// Paused with a return date that has not come yet.
  bool isOnVacation(DateTime today) =>
      status == MilkSubscriptionStatus.paused &&
      resumeOn != null &&
      DateTime(
        resumeOn!.year,
        resumeOn!.month,
        resumeOn!.day,
      ).isAfter(DateTime(today.year, today.month, today.day));

  // Retrieve a schedule for a specific shift.
  MilkShiftSchedule? scheduleFor(MilkDeliveryShift shift) {
    for (final schedule in shiftSchedules) {
      if (schedule.shift == shift) {
        return schedule;
      }
    }
    return null;
  }

  bool get hasMorningDelivery => scheduleFor(MilkDeliveryShift.morning) != null;

  bool get hasEveningDelivery => scheduleFor(MilkDeliveryShift.evening) != null;

  // Sum of configured quantities.
  // This is not necessarily the quantity delivered each day,
  // because Morning and Evening may follow different schedules.
  int get combinedQuantityMl {
    var total = 0;

    for (final schedule in shiftSchedules) {
      total += schedule.quantityMl;
    }

    return total;
  }

  MilkSubscription copyWith({
    String? id,
    String? productId,
    List<MilkShiftSchedule>? shiftSchedules,
    int? quantity,
    MilkDeliveryFrequency? frequency,
    List<int>? selectedWeekdays,
    List<DateTime>? selectedRandomDates,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    MilkSubscriptionStatus? status,
    DateTime? cancelledAt,
    DateTime? resumeOn,
    bool clearResumeOn = false,
    List<DateTime>? vacationDates,
  }) {
    return MilkSubscription(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      shiftSchedules: shiftSchedules ?? this.shiftSchedules,
      quantity: quantity ?? this.quantity,
      frequency: frequency ?? this.frequency,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      selectedRandomDates: selectedRandomDates ?? this.selectedRandomDates,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      status: status ?? this.status,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      resumeOn: clearResumeOn ? null : (resumeOn ?? this.resumeOn),
      vacationDates: vacationDates ?? this.vacationDates,
      approval: approval,
      rejectReason: rejectReason,
      approvalNote: approvalNote,
    );
  }
}
