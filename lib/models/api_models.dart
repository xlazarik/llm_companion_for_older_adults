class AskAudioRequest {
  final String session;
  final int id;
  final String audio; // base64 encoded
  final String? identifier;

  AskAudioRequest({
    required this.session,
    required this.id,
    required this.audio,
    this.identifier,
  });

  Map<String, dynamic> toJson() {
    return {
      'session': session,
      'id': id,
      'audio': audio,
      if (identifier != null) 'identifier': identifier,
    };
  }
}

class AskResponse {
  final int? unread;
  final String? assigned;
  final String? mode;
  final List<ChatItem>? chat;

  AskResponse({
    this.unread,
    this.assigned,
    this.mode,
    this.chat,
  });

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    return AskResponse(
      unread: json['unread'] as int?,
      assigned: json['assigned'] as String?,
      mode: json['mode'] as String?,
      chat: (json['chat'] as List<dynamic>?)
          ?.map((item) => ChatItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChatItem {
  final bool? answer;
  final String? text;
  final String? mode;
  final DateTime? inserted;
  final int? counter;
  final int? liked;
  final String? audioResponse; // base64 encoded audio

  ChatItem({
    this.answer,
    this.text,
    this.mode,
    this.inserted,
    this.counter,
    this.liked,
    this.audioResponse,
  });

  factory ChatItem.fromJson(Map<String, dynamic> json) {
    return ChatItem(
      answer: json['answer'] as bool?,
      text: json['text'] as String?,
      mode: json['mode'] as String?,
      inserted: json['inserted'] != null
          ? DateTime.parse(json['inserted'] as String)
          : null,
      counter: json['counter'] as int?,
      liked: json['liked'] as int?,
      audioResponse: json['audioResponse'] as String?,
    );
  }
}
