enum FeatureSampleIssue {
  incompleteAudio,
  uninformativeAudio,
  incompleteVisual,
  uninformativeVisual,
}

/// Invalid evidence cannot become reusable rules, but can remain an interval.
final class FeatureSampleFailure extends FormatException {
  const FeatureSampleFailure(this.issue, super.message);
  final FeatureSampleIssue issue;
}
