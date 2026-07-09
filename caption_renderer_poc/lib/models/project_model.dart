class ProjectModel {
  final String id;
  final String name;
  final String videoPath;
  final DateTime updatedAt;
  final Map<String, dynamic>? captionResult;
  final String? style;
  final Map<String, dynamic>? customStyles;
  final Map<String, dynamic>? videoAdjustments;

  ProjectModel({
    required this.id,
    required this.name,
    required this.videoPath,
    required this.updatedAt,
    this.captionResult,
    this.style,
    this.customStyles,
    this.videoAdjustments,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'videoPath': videoPath,
      'updatedAt': updatedAt.toIso8601String(),
      if (captionResult != null) 'captionResult': captionResult,
      if (style != null) 'style': style,
      if (customStyles != null) 'customStyles': customStyles,
      if (videoAdjustments != null) 'videoAdjustments': videoAdjustments,
    };
  }

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: json['id'],
      name: json['name'],
      videoPath: json['videoPath'],
      updatedAt: DateTime.parse(json['updatedAt']),
      captionResult: json['captionResult'] as Map<String, dynamic>?,
      style: json['style'] as String?,
      customStyles: json['customStyles'] as Map<String, dynamic>?,
      videoAdjustments: json['videoAdjustments'] as Map<String, dynamic>?,
    );
  }
}
