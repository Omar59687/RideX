enum DriverApprovalStatus { pending, approved, rejected }

extension DriverApprovalStatusX on DriverApprovalStatus {
  String get label => switch (this) {
        DriverApprovalStatus.pending => 'Pending',
        DriverApprovalStatus.approved => 'Approved',
        DriverApprovalStatus.rejected => 'Rejected',
      };

  static DriverApprovalStatus fromDatabase(String value) {
    return switch (value) {
      'approved' => DriverApprovalStatus.approved,
      'rejected' => DriverApprovalStatus.rejected,
      'pending' => DriverApprovalStatus.pending,
      _ => throw FormatException('Unknown Driver approval status: $value'),
    };
  }
}
